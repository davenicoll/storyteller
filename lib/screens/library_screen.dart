import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/manifest.dart';
import '../providers/settings_provider.dart';
import '../services/thumbnail_cache.dart';
import 'reader_screen.dart';

enum ThumbnailSize {
  small(100, 0.5),
  medium(200, 1.0),
  large(400, 2.0);

  final double maxCrossAxisExtent;
  final double scale;

  const ThumbnailSize(this.maxCrossAxisExtent, this.scale);
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  ThumbnailSize _getThumbnailSize(int index) {
    return ThumbnailSize.values[index.clamp(0, 2)];
  }

  void _cycleThumbnailSize() {
    final settings = context.read<SettingsProvider>();
    final nextIndex = (settings.thumbnailSizeIndex + 1) % 3;
    settings.setThumbnailSizeIndex(nextIndex);
  }

  IconData _getSizeIcon(int index) {
    switch (index) {
      case 0:
        return Icons.grid_view;
      case 1:
        return Icons.grid_on;
      case 2:
        return Icons.square_rounded;
      default:
        return Icons.grid_on;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          if (settings.isScanning) {
            return Stack(
              children: [
                const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading library...'),
                    ],
                  ),
                ),
                _buildSettingsButton(context),
              ],
            );
          }

          if (settings.loadedManifests.isEmpty) {
            return Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.library_books,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No stories found',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set a manifest folder in Settings',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/settings'),
                        icon: const Icon(Icons.settings),
                        label: const Text('Open Settings'),
                      ),
                    ],
                  ),
                ),
                _buildSettingsButton(context),
              ],
            );
          }

          final thumbnailSize = _getThumbnailSize(settings.thumbnailSizeIndex);

          return Stack(
            children: [
              ListView.builder(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: MediaQuery.of(context).padding.top + 16,
                  bottom: 16,
                ),
                itemCount: settings.loadedManifests.length,
                itemBuilder: (context, index) {
                  final manifest = settings.loadedManifests[index];
                  return _ManifestSection(
                    manifest: manifest,
                    thumbnailSize: thumbnailSize,
                  );
                },
              ),
              _buildSizeButton(context, settings),
              _buildSettingsButton(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSizeButton(BuildContext context, SettingsProvider settings) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 56,
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
          onPressed: _cycleThumbnailSize,
          icon: Icon(_getSizeIcon(settings.thumbnailSizeIndex)),
          tooltip: 'Change thumbnail size',
        ),
      ),
    );
  }

  Widget _buildSettingsButton(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 8,
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
          onPressed: () => Navigator.pushNamed(context, '/settings'),
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
        ),
      ),
    );
  }
}

class _ManifestSection extends StatelessWidget {
  final StoryManifest manifest;
  final ThumbnailSize thumbnailSize;

  const _ManifestSection({
    required this.manifest,
    required this.thumbnailSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final collection in manifest.collections)
          _CollectionSection(
            manifest: manifest,
            collection: collection,
            thumbnailSize: thumbnailSize,
          ),
      ],
    );
  }
}

class _CollectionSection extends StatelessWidget {
  final StoryManifest manifest;
  final StoryCollection collection;
  final ThumbnailSize thumbnailSize;

  const _CollectionSection({
    required this.manifest,
    required this.collection,
    required this.thumbnailSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          collection.name,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: thumbnailSize.maxCrossAxisExtent,
            childAspectRatio: 0.7,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: collection.parts.length,
          itemBuilder: (context, index) {
            final part = collection.parts[index];
            return _PartCard(manifest: manifest, part: part);
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _PartCard extends StatefulWidget {
  final StoryManifest manifest;
  final StoryPart part;

  const _PartCard({
    required this.manifest,
    required this.part,
  });

  @override
  State<_PartCard> createState() => _PartCardState();
}

class _PartCardState extends State<_PartCard> {
  Uint8List? _thumbnail;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    try {
      final pdfPath =
          '${widget.manifest.basePath}${Platform.pathSeparator}${widget.part.pdf}';
      final thumbnail = await ThumbnailCache.instance.getThumbnail(pdfPath);

      if (mounted) {
        setState(() {
          _thumbnail = thumbnail;
          _isLoading = false;
          _hasError = thumbnail == null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final pdfPath =
              '${widget.manifest.basePath}${Platform.pathSeparator}${widget.part.pdf}';
          final audioPaths = widget.part.audio
              .map((a) =>
                  '${widget.manifest.basePath}${Platform.pathSeparator}$a')
              .toList();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReaderScreen(
                pdfPath: pdfPath,
                audioPaths: audioPaths,
                title: widget.part.name,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildThumbnail(context),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _getShortName(widget.part.name),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_thumbnail != null) {
      return Image.memory(
        _thumbnail!,
        fit: BoxFit.cover,
      );
    }

    return Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Center(
        child: Icon(
          _hasError ? Icons.error_outline : Icons.auto_stories,
          size: 48,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  String _getShortName(String name) {
    final match = RegExp(r'Part (\d+)').firstMatch(name);
    if (match != null) {
      return 'Part ${match.group(1)}';
    }
    if (name.contains('Christmas')) return 'Christmas';
    if (name.contains('Bonus')) return 'Bonus';
    return name;
  }
}
