import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';
import '../models/manifest.dart';

enum ThemeModeSetting {
  auto,
  dark,
  light,
}

class ManifestInfo {
  final String filePath;
  final String fileName;
  final int collectionCount;
  final String? error;

  ManifestInfo({
    required this.filePath,
    required this.fileName,
    required this.collectionCount,
    this.error,
  });

  bool get hasError => error != null;
}

class SettingsProvider extends ChangeNotifier {
  static const String _manifestFolderKey = 'manifest_folder_path';
  static const String _thumbnailSizeKey = 'thumbnail_size';
  static const String _themeModeKey = 'theme_mode';
  static const String _keepScreenAwakeKey = 'keep_screen_awake';

  String? _manifestFolderPath;
  List<ManifestInfo> _manifests = [];
  List<StoryManifest> _loadedManifests = [];
  bool _isScanning = false;
  String? _scanError;
  int _thumbnailSizeIndex = 1; // 0 = small, 1 = medium, 2 = large
  ThemeModeSetting _themeMode = ThemeModeSetting.light;
  bool _keepScreenAwake = true; // Default to enabled

  String? get manifestFolderPath => _manifestFolderPath;
  List<ManifestInfo> get manifests => _manifests;
  List<StoryManifest> get loadedManifests => _loadedManifests;
  bool get isScanning => _isScanning;
  String? get scanError => _scanError;
  int get thumbnailSizeIndex => _thumbnailSizeIndex;
  ThemeModeSetting get themeMode => _themeMode;
  bool get keepScreenAwake => _keepScreenAwake;

  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case ThemeModeSetting.auto:
        return ThemeMode.system;
      case ThemeModeSetting.dark:
        return ThemeMode.dark;
      case ThemeModeSetting.light:
        return ThemeMode.light;
    }
  }

  List<StoryCollection> get allCollections {
    final collections = <StoryCollection>[];
    for (final manifest in _loadedManifests) {
      collections.addAll(manifest.collections);
    }
    return collections;
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _manifestFolderPath = prefs.getString(_manifestFolderKey);
    _thumbnailSizeIndex = (prefs.getInt(_thumbnailSizeKey) ?? 1).clamp(0, 2);
    final themeModeIndex = prefs.getInt(_themeModeKey) ?? 2; // default to light
    _themeMode = themeModeIndex >= 0 && themeModeIndex < ThemeModeSetting.values.length
        ? ThemeModeSetting.values[themeModeIndex]
        : ThemeModeSetting.light;
    _keepScreenAwake = prefs.getBool(_keepScreenAwakeKey) ?? true; // default to enabled
    if (_manifestFolderPath != null) {
      await scanForManifests();
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeModeSetting mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
    notifyListeners();
  }

  Future<void> setThumbnailSizeIndex(int index) async {
    if (index < 0 || index > 2) return;
    _thumbnailSizeIndex = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_thumbnailSizeKey, index);
    notifyListeners();
  }

  Future<void> setKeepScreenAwake(bool value) async {
    _keepScreenAwake = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepScreenAwakeKey, value);
    notifyListeners();
  }

  Future<void> setManifestFolderPath(String? path) async {
    _manifestFolderPath = path;
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString(_manifestFolderKey, path);
      await scanForManifests();
    } else {
      await prefs.remove(_manifestFolderKey);
      _manifests = [];
      _loadedManifests = [];
    }
    notifyListeners();
  }

  Future<void> scanForManifests() async {
    if (_manifestFolderPath == null) return;

    _isScanning = true;
    _scanError = null;
    _manifests = [];
    _loadedManifests = [];
    notifyListeners();

    try {
      final directory = Directory(_manifestFolderPath!);
      if (!await directory.exists()) {
        _scanError = 'Folder does not exist';
        _isScanning = false;
        notifyListeners();
        return;
      }

      final List<ManifestInfo> foundManifests = [];
      final List<StoryManifest> loadedManifests = [];

      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          if (fileName.endsWith('.yaml') || fileName.endsWith('.yml')) {
            if (fileName.contains('manifest')) {
              try {
                final content = await entity.readAsString();
                final yaml = loadYaml(content);
                if (yaml is YamlMap && yaml['collections'] is YamlList) {
                  final collectionsList = yaml['collections'] as YamlList;

                  final basePath = entity.parent.path;
                  final collections = <StoryCollection>[];
                  String? parseError;

                  for (final c in collectionsList) {
                    try {
                      if (c is Map) {
                        collections.add(StoryCollection.fromYaml(c));
                      }
                    } catch (e) {
                      parseError = e.toString();
                      debugPrint('Error parsing collection in ${entity.path}: $e');
                    }
                  }

                  foundManifests.add(ManifestInfo(
                    filePath: entity.path,
                    fileName: fileName,
                    collectionCount: collections.length,
                    error: parseError,
                  ));

                  if (collections.isNotEmpty) {
                    loadedManifests.add(StoryManifest(
                      filePath: entity.path,
                      basePath: basePath,
                      collections: collections,
                    ));
                  }
                } else {
                  // Valid YAML but wrong structure
                  foundManifests.add(ManifestInfo(
                    filePath: entity.path,
                    fileName: fileName,
                    collectionCount: 0,
                    error: 'Invalid manifest structure: missing "collections" list',
                  ));
                }
              } on FormatException catch (e) {
                // Malformed YAML
                foundManifests.add(ManifestInfo(
                  filePath: entity.path,
                  fileName: fileName,
                  collectionCount: 0,
                  error: 'Invalid YAML: ${e.message}',
                ));
                debugPrint('Error parsing YAML file ${entity.path}: $e');
              } on FileSystemException catch (e) {
                // Permission or access error
                foundManifests.add(ManifestInfo(
                  filePath: entity.path,
                  fileName: fileName,
                  collectionCount: 0,
                  error: 'Cannot read file: ${e.message}',
                ));
                debugPrint('Error reading file ${entity.path}: $e');
              } catch (e) {
                foundManifests.add(ManifestInfo(
                  filePath: entity.path,
                  fileName: fileName,
                  collectionCount: 0,
                  error: 'Error: $e',
                ));
                debugPrint('Error parsing YAML file ${entity.path}: $e');
              }
            }
          }
        }
      }

      _manifests = foundManifests;
      _loadedManifests = loadedManifests;
      _isScanning = false;
      notifyListeners();
    } catch (e) {
      _scanError = 'Error scanning folder: $e';
      _isScanning = false;
      notifyListeners();
    }
  }

  String getFullPath(StoryManifest manifest, String relativePath) {
    return '${manifest.basePath}${Platform.pathSeparator}$relativePath';
  }
}
