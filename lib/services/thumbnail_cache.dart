import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

class ThumbnailCache {
  static ThumbnailCache? _instance;
  static ThumbnailCache get instance => _instance ??= ThumbnailCache._();

  ThumbnailCache._();

  Directory? _cacheDir;

  Future<Directory> get cacheDir async {
    if (_cacheDir != null) return _cacheDir!;
    // Use application cache directory which works on all platforms
    final appDir = await getApplicationCacheDirectory();
    _cacheDir = Directory('${appDir.path}/thumbnails');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  String _getCacheKey(String pdfPath) {
    final bytes = utf8.encode(pdfPath);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  Future<File> _getCacheFile(String pdfPath) async {
    final dir = await cacheDir;
    final key = _getCacheKey(pdfPath);
    return File('${dir.path}/$key.png');
  }

  Future<Uint8List?> getThumbnail(String pdfPath) async {
    try {
      final cacheFile = await _getCacheFile(pdfPath);

      // Check if cached thumbnail exists and is newer than the PDF
      if (await cacheFile.exists()) {
        final pdfFile = File(pdfPath);
        if (await pdfFile.exists()) {
          final pdfModified = await pdfFile.lastModified();
          final cacheModified = await cacheFile.lastModified();
          if (cacheModified.isAfter(pdfModified)) {
            return await cacheFile.readAsBytes();
          }
        }
      }

      // Generate thumbnail
      final thumbnail = await _generateThumbnail(pdfPath);
      if (thumbnail != null) {
        await cacheFile.writeAsBytes(thumbnail);
      }
      return thumbnail;
    } catch (e) {
      debugPrint('Error getting thumbnail for $pdfPath: $e');
      return null;
    }
  }

  Future<Uint8List?> _generateThumbnail(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) return null;

      final document = await PdfDocument.openFile(pdfPath);
      final page = await document.getPage(1);
      final pageImage = await page.render(
        width: page.width * 0.5,
        height: page.height * 0.5,
        format: PdfPageImageFormat.png,
      );
      await page.close();
      await document.close();

      return pageImage?.bytes;
    } catch (e) {
      debugPrint('Error generating thumbnail for $pdfPath: $e');
      return null;
    }
  }

  Future<void> clearCache() async {
    try {
      final dir = await cacheDir;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create();
      }
    } catch (e) {
      debugPrint('Error clearing thumbnail cache: $e');
    }
  }
}
