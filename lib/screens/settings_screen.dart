import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  IconData get _backIcon {
    if (Platform.isIOS || Platform.isMacOS) {
      return Icons.arrow_back_ios_new;
    }
    return Icons.arrow_back;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Consumer<SettingsProvider>(
            builder: (context, settings, child) {
              return ListView(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: MediaQuery.of(context).padding.top + 56,
                  bottom: 16,
                ),
                children: [
                  _buildThemeSection(context, settings),
                  const SizedBox(height: 24),
                  _buildManifestFolderSection(context, settings),
                  const SizedBox(height: 24),
                  if (settings.manifestFolderPath != null)
                    _buildManifestListSection(context, settings),
                ],
              );
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(_backIcon),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Back',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSection(BuildContext context, SettingsProvider settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.palette,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Theme',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the app appearance.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SegmentedButton<ThemeModeSetting>(
              segments: const [
                ButtonSegment(
                  value: ThemeModeSetting.auto,
                  label: Text('Auto'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeModeSetting.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeModeSetting.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (Set<ThemeModeSetting> selection) {
                settings.setThemeMode(selection.first);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManifestFolderSection(
      BuildContext context, SettingsProvider settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Manifest Folder',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Select the folder containing your story manifest YAML files.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                settings.manifestFolderPath ?? 'No folder selected',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: settings.manifestFolderPath != null
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _selectFolder(context, settings),
                  icon: const Icon(Icons.folder_open),
                  label: Text(settings.manifestFolderPath == null
                      ? 'Select Folder'
                      : 'Change Folder'),
                ),
                if (settings.manifestFolderPath != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => settings.setManifestFolderPath(null),
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManifestListSection(
      BuildContext context, SettingsProvider settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.description,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Found Manifests',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (settings.isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    onPressed: () => settings.scanForManifests(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Rescan',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (settings.scanError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        settings.scanError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (settings.isScanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Scanning for manifest files...'),
                    ],
                  ),
                ),
              )
            else if (settings.manifests.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No manifest files found',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Looking for YAML files with "manifest" in the name',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: settings.manifests.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final manifest = settings.manifests[index];
                  return ListTile(
                    leading: Icon(
                      manifest.hasError ? Icons.error_outline : Icons.article,
                      color: manifest.hasError
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    title: Text(
                      manifest.fileName,
                      style: manifest.hasError
                          ? TextStyle(color: Theme.of(context).colorScheme.error)
                          : null,
                    ),
                    subtitle: Text(
                      manifest.hasError
                          ? manifest.error!
                          : '${manifest.collectionCount} collection${manifest.collectionCount == 1 ? '' : 's'}',
                      style: manifest.hasError
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            )
                          : null,
                    ),
                    trailing: manifest.hasError ? null : const Icon(Icons.chevron_right),
                    onTap: manifest.hasError
                        ? null
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Selected: ${manifest.fileName}'),
                              ),
                            );
                          },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectFolder(
      BuildContext context, SettingsProvider settings) async {
    // Request storage permission on Android
    if (Platform.isAndroid) {
      final hasPermission = await _requestStoragePermission(context);
      if (!hasPermission) {
        return;
      }
    }

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      await settings.setManifestFolderPath(selectedDirectory);
    }
  }

  Future<bool> _requestStoragePermission(BuildContext context) async {
    // Check if we already have permission
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    // Request the permission
    final status = await Permission.manageExternalStorage.request();

    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      // Show dialog to open settings
      if (context.mounted) {
        final shouldOpenSettings = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Storage Permission Required'),
            content: const Text(
              'This app needs access to storage to read your story files. '
              'Please grant "All files access" permission in Settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );

        if (shouldOpenSettings == true) {
          await openAppSettings();
        }
      }
      return false;
    }

    return false;
  }
}
