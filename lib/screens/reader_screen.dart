import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class ReaderScreen extends StatefulWidget {
  final String? pdfPath;
  final List<String>? audioPaths;
  final String? title;

  const ReaderScreen({
    super.key,
    this.pdfPath,
    this.audioPaths,
    this.title,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  late String? _pdfPath;
  List<String> _audioPaths = [];
  int _currentTrackIndex = 0;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  int _currentPage = 0;
  int _totalPages = 0;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _shouldAutoplay = true;
  bool _isHoveringControls = false;
  bool _isAudioReady = false;

  // PDF rendering with pdfx
  PdfDocument? _pdfDocument;
  List<Uint8List?> _pageImages = [];
  bool _isLoadingPdf = true;
  bool _isPdfFullyLoaded = false;
  final PageController _pageController = PageController();

  // Gesture state tracking
  final Map<int, TransformationController> _transformControllers = {};
  bool _isZoomed = false;
  Orientation? _lastOrientation;
  // Key to force rebuild of gesture widgets on orientation change
  int _gestureRebuildKey = 0;

  @override
  void initState() {
    super.initState();
    _pdfPath = widget.pdfPath;
    _audioPaths = widget.audioPaths ?? [];
    _setupAudioListeners();
    if (_audioPaths.isNotEmpty) {
      _initializeAudio();
    }
    if (_pdfPath != null) {
      _loadPdf();
    }
    _startHideTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != null && _lastOrientation != orientation) {
      // Orientation changed - reset all zoom states and force gesture widget rebuild
      _resetAllZoom();
      // Increment key to force complete rebuild of gesture handling widgets
      // This ensures gesture recognizers are recreated fresh
      _gestureRebuildKey++;
    }
    _lastOrientation = orientation;
  }

  void _resetAllZoom() {
    for (final controller in _transformControllers.values) {
      controller.value = Matrix4.identity();
    }
    if (_isZoomed) {
      setState(() {
        _isZoomed = false;
      });
    }
  }

  Future<void> _loadPdf() async {
    try {
      final document = await PdfDocument.openFile(_pdfPath!);
      final pageCount = document.pagesCount;

      // Mark PDF as ready once document is open
      if (mounted) {
        setState(() {
          _pdfDocument = document;
          _totalPages = pageCount;
          _isLoadingPdf = false;
          _isPdfFullyLoaded = true;
        });

        // Start autoplay now that PDF document is open
        if (_shouldAutoplay && _audioPaths.isNotEmpty) {
          _shouldAutoplay = false;
          _startAutoplay();
        }
      }

      // Pre-render all pages as images
      final List<Uint8List?> images = List.filled(pageCount, null);

      // Render pages in parallel batches for speed
      const batchSize = 3;
      for (int i = 0; i < pageCount; i += batchSize) {
        final futures = <Future<void>>[];
        for (int j = i; j < i + batchSize && j < pageCount; j++) {
          futures.add(_renderPage(document, j, images));
        }
        await Future.wait(futures);

        // Update state after each batch so user sees progress
        if (mounted) {
          setState(() {
            _pageImages = List.from(images);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading PDF: $e');
      if (mounted) {
        setState(() {
          _isLoadingPdf = false;
          _isPdfFullyLoaded = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading PDF: $e')),
        );
      }
    }
  }

  Future<void> _renderPage(
      PdfDocument document, int pageIndex, List<Uint8List?> images) async {
    try {
      final page = await document.getPage(pageIndex + 1); // 1-indexed
      final pageImage = await page.render(
        width: page.width * 2, // 2x for quality
        height: page.height * 2,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      await page.close();

      if (pageImage != null) {
        images[pageIndex] = pageImage.bytes;
      }
    } catch (e) {
      debugPrint('Error rendering page ${pageIndex + 1}: $e');
    }
  }

  Future<void> _initializeAudio() async {
    // Configure audio session for proper Android audio focus handling
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());

    if (Platform.isAndroid) {
      await session.setActive(true);
    }

    await _loadTrack(0);
    _isAudioReady = true;

    // If PDF already loaded while we were initializing audio, start autoplay
    if (_shouldAutoplay && _isPdfFullyLoaded && mounted) {
      _shouldAutoplay = false;
      _startAutoplay();
    }
  }

  Future<void> _startAutoplay() async {
    // Wait for both PDF to be fully loaded and audio to be ready
    while ((!_isAudioReady || !_isPdfFullyLoaded) && mounted) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (mounted && _isAudioReady && _isPdfFullyLoaded) {
      await _audioPlayer.play();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_isHoveringControls) {
        setState(() {
          _controlsVisible = false;
        });
      }
    });
  }

  void _showControls() {
    setState(() {
      _controlsVisible = true;
    });
    _startHideTimer();
  }

  void _onControlInteraction() {
    _startHideTimer();
  }

  void _setupAudioListeners() {
    _audioPlayer.durationStream.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration ?? Duration.zero;
        });
      }
    });

    _audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
        if (state.processingState == ProcessingState.completed) {
          _onTrackComplete();
        }
      }
    });
  }

  Future<void> _loadTrack(int index) async {
    if (index < 0 || index >= _audioPaths.length) return;
    try {
      await _audioPlayer.setFilePath(_audioPaths[index]);
      setState(() {
        _currentTrackIndex = index;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading audio: $e')),
        );
      }
    }
  }

  void _onTrackComplete() {
    if (_currentTrackIndex < _audioPaths.length - 1) {
      _loadTrack(_currentTrackIndex + 1);
      _audioPlayer.play();
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _audioPlayer.dispose();
    _pdfDocument?.close();
    _pageController.dispose();
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    _transformControllers.clear();
    super.dispose();
  }

  TransformationController _getTransformController(int index) {
    if (!_transformControllers.containsKey(index)) {
      final controller = TransformationController();
      controller.addListener(() => _onTransformChanged(controller));
      _transformControllers[index] = controller;
    }
    return _transformControllers[index]!;
  }

  void _onTransformChanged(TransformationController controller) {
    final scale = controller.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05; // Small threshold to avoid floating point issues
    if (zoomed != _isZoomed) {
      setState(() {
        _isZoomed = zoomed;
      });
    }
  }

  void _resetZoom(int pageIndex) {
    final controller = _transformControllers[pageIndex];
    if (controller != null) {
      controller.value = Matrix4.identity();
    }
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  String _getCurrentTrackName() {
    if (_audioPaths.isEmpty) return 'No audio loaded';
    final path = _audioPaths[_currentTrackIndex];
    final fileName = path.split(Platform.pathSeparator).last;
    final name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return name;
  }

  void _goToPreviousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToNextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  IconData get _backIcon {
    // Use platform-appropriate back icon
    if (Platform.isIOS || Platform.isMacOS) {
      return Icons.arrow_back_ios_new;
    }
    return Icons.arrow_back;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            // PDF Viewer using PageView with pre-rendered images
            Positioned.fill(
              child: _pdfPath != null
                  ? _buildPdfViewer()
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.picture_as_pdf,
                            size: 64,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No PDF loaded',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            // Floating audio player - only render when visible to avoid blocking gestures
            if (_controlsVisible)
              Positioned(
                left: MediaQuery.of(context).padding.left + 16,
                right: MediaQuery.of(context).padding.right + 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
                child: MouseRegion(
                  onEnter: (_) {
                    _isHoveringControls = true;
                    _hideTimer?.cancel();
                  },
                  onExit: (_) {
                    _isHoveringControls = false;
                    _startHideTimer();
                  },
                  child: _buildAudioControls(),
                ),
              ),
            // Floating back button - only render when visible to avoid blocking gestures
            if (_controlsVisible)
              Positioned(
                left: MediaQuery.of(context).padding.left + 8,
                top: MediaQuery.of(context).padding.top + 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.7),
                    shape: BoxShape.circle,
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
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back',
                  ),
                ),
              ),
            // Page indicator - only render when visible to avoid blocking gestures
            if (_totalPages > 0 && _controlsVisible)
              Positioned(
                right: MediaQuery.of(context).padding.right + 8,
                top: MediaQuery.of(context).padding.top + 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '${_currentPage + 1} / $_totalPages',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfViewer() {
    if (_isLoadingPdf && _pageImages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading pages...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    // Use PhotoViewGestureDetectorScope pattern - wrap PageView with axis awareness
    return _GestureAwarePageView(
      // Use key to force complete rebuild on orientation change
      key: ValueKey('gesture_view_$_gestureRebuildKey'),
      pageController: _pageController,
      isZoomed: _isZoomed,
      initialPage: _currentPage,
      totalPages: _totalPages > 0 ? _totalPages : _pageImages.length,
      onPageChanged: (index) {
        setState(() {
          _currentPage = index;
        });
      },
      itemBuilder: (context, index) {
        final imageBytes = index < _pageImages.length ? _pageImages[index] : null;

        if (imageBytes == null) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        return _buildPageWithGestures(imageBytes, index);
      },
    );
  }

  Widget _buildPageWithGestures(Uint8List imageBytes, int pageIndex) {
    final transformController = _getTransformController(pageIndex);

    return _ZoomablePage(
      // Key includes rebuild counter to force fresh gesture recognizers on orientation change
      key: ValueKey('page_${pageIndex}_$_gestureRebuildKey'),
      transformationController: transformController,
      onSingleTap: _toggleControls,
      onDoubleTap: () => _resetZoom(pageIndex),
      child: Center(
        child: Image.memory(
          imageBytes,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _showControls();
        _togglePlayPause();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _showControls();
        _goToPreviousPage();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _showControls();
        _goToNextPage();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _buildAudioControls() {
    final remaining = _duration - _position;
    return GestureDetector(
      onTap: _onControlInteraction,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Track name
            if (_audioPaths.isNotEmpty) ...[
              Text(
                _getCurrentTrackName(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (_audioPaths.length > 1)
                Text(
                  'Track ${_currentTrackIndex + 1} of ${_audioPaths.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              const SizedBox(height: 8),
            ],
            // Progress slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 24),
              ),
              child: Slider(
                value: _position.inSeconds.toDouble(),
                max: _duration.inSeconds.toDouble() > 0
                    ? _duration.inSeconds.toDouble()
                    : 1.0,
                onChanged: (value) async {
                  _onControlInteraction();
                  await _audioPlayer.seek(Duration(seconds: value.toInt()));
                },
              ),
            ),
            // Time display
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_position),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '-${_formatDuration(remaining)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Playback controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_audioPaths.length > 1)
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    iconSize: 32,
                    onPressed: _currentTrackIndex > 0
                        ? () {
                            _onControlInteraction();
                            _loadTrack(_currentTrackIndex - 1);
                          }
                        : null,
                  ),
                IconButton(
                  icon: const Icon(Icons.replay_10),
                  iconSize: 32,
                  onPressed: () async {
                    _onControlInteraction();
                    final newPosition =
                        _position - const Duration(seconds: 10);
                    await _audioPlayer.seek(
                      newPosition < Duration.zero
                          ? Duration.zero
                          : newPosition,
                    );
                  },
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause_circle : Icons.play_circle,
                    size: 64,
                  ),
                  onPressed: () {
                    _onControlInteraction();
                    _togglePlayPause();
                  },
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.forward_10),
                  iconSize: 32,
                  onPressed: () async {
                    _onControlInteraction();
                    final newPosition =
                        _position + const Duration(seconds: 10);
                    await _audioPlayer.seek(
                      newPosition > _duration ? _duration : newPosition,
                    );
                  },
                ),
                if (_audioPaths.length > 1)
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    iconSize: 32,
                    onPressed: _currentTrackIndex < _audioPaths.length - 1
                        ? () {
                            _onControlInteraction();
                            _loadTrack(_currentTrackIndex + 1);
                          }
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A PageView that properly handles gesture conflicts with zooming content.
/// Uses a custom gesture recognizer to let pinch-to-zoom win when needed.
class _GestureAwarePageView extends StatefulWidget {
  final PageController pageController;
  final bool isZoomed;
  final int initialPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final IndexedWidgetBuilder itemBuilder;

  const _GestureAwarePageView({
    super.key,
    required this.pageController,
    required this.isZoomed,
    required this.initialPage,
    required this.totalPages,
    required this.onPageChanged,
    required this.itemBuilder,
  });

  @override
  State<_GestureAwarePageView> createState() => _GestureAwarePageViewState();
}

class _GestureAwarePageViewState extends State<_GestureAwarePageView> {
  int _pointerCount = 0;
  late PageController _internalController;

  @override
  void initState() {
    super.initState();
    // Create a new controller starting at the current page
    // This handles the case where we're rebuilt due to orientation change
    _internalController = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _internalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Wrap in Listener to track pointer count for multi-touch detection.
    // This is more reliable than trying to intercept gestures.
    return Listener(
      onPointerDown: (_) {
        setState(() => _pointerCount++);
      },
      onPointerUp: (_) {
        setState(() {
          _pointerCount--;
          if (_pointerCount < 0) _pointerCount = 0;
        });
      },
      onPointerCancel: (_) {
        setState(() {
          _pointerCount--;
          if (_pointerCount < 0) _pointerCount = 0;
        });
      },
      child: PageView.builder(
        controller: _internalController,
        // Disable PageView swiping when:
        // 1. Content is zoomed (allow panning within the zoomed content)
        // 2. Two or more fingers are down (pinching)
        physics: (widget.isZoomed || _pointerCount >= 2)
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics(),
        itemCount: widget.totalPages,
        onPageChanged: widget.onPageChanged,
        itemBuilder: widget.itemBuilder,
      ),
    );
  }
}

/// A zoomable page widget that properly handles tap, double-tap, pan, and zoom gestures
/// without conflicting with the parent PageView.
///
/// Key insight from photo_view: Use GestureDetector INSIDE InteractiveViewer's child,
/// not wrapping it. This avoids gesture arena conflicts.
class _ZoomablePage extends StatefulWidget {
  final TransformationController transformationController;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;
  final Widget child;

  const _ZoomablePage({
    super.key,
    required this.transformationController,
    required this.onSingleTap,
    required this.onDoubleTap,
    required this.child,
  });

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _animateResetZoom() {
    _animation = Matrix4Tween(
      begin: widget.transformationController.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animation!.addListener(() {
      widget.transformationController.value = _animation!.value;
    });

    _animationController.forward(from: 0);
    widget.onDoubleTap();
  }

  @override
  Widget build(BuildContext context) {
    // Use LayoutBuilder to get actual viewport size, then create a constrained
    // InteractiveViewer child that fills the full viewport for gesture detection.
    // This ensures pinch/zoom and swipe work from anywhere on screen.
    return LayoutBuilder(
      builder: (context, constraints) {
        return InteractiveViewer(
          transformationController: widget.transformationController,
          minScale: 1.0,
          maxScale: 4.0,
          panEnabled: true,
          scaleEnabled: true,
          // Constrain the viewport to prevent panning beyond the content at 1x scale
          constrained: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSingleTap,
            onDoubleTap: _animateResetZoom,
            // Use a SizedBox with the exact viewport dimensions to ensure
            // gestures are detected across the full screen area
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}
