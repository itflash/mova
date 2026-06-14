import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

import '../app/app_scope.dart';
import '../app/models.dart';

Future<void> showAttachmentPreviewSheet(
  BuildContext context,
  Attachment attachment, {
  List<Attachment>? attachments,
}) {
  final previewItems = attachments ?? [attachment];
  final initialIndex = previewItems.indexWhere(
    (item) => item.id == attachment.id,
  );
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => AttachmentPreviewSheet(
      attachments: previewItems,
      initialIndex: initialIndex == -1 ? 0 : initialIndex,
    ),
  );
}

String compactFileName(String value) {
  if (value.length <= 26) return value;
  final extensionIndex = value.lastIndexOf('.');
  if (extensionIndex <= 0 || extensionIndex >= value.length - 1) {
    return '${value.substring(0, 10)}...${value.substring(value.length - 8)}';
  }
  final ext = value.substring(extensionIndex);
  final name = value.substring(0, extensionIndex);
  if (name.length <= 16) return value;
  return '${name.substring(0, 10)}...$ext';
}

String formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

class AttachmentThumb extends StatelessWidget {
  const AttachmentThumb({
    super.key,
    required this.attachment,
    required this.width,
    required this.height,
    required this.radius,
    required this.overlayLabel,
  });

  final Attachment attachment;
  final double width;
  final double height;
  final double radius;
  final String overlayLabel;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).colorScheme.surfaceContainer;
    final trimmedOverlayLabel = overlayLabel.trim();
    Widget child;
    switch (attachment.kind) {
      case AttachmentKind.image:
        child = _ResolvedAttachmentImage(
          attachment: attachment,
          width: width,
          height: height,
          fit: BoxFit.cover,
        );
      case AttachmentKind.video:
        child = _ResolvedAttachmentVideoThumb(
          attachment: attachment,
          width: width,
          height: height,
          label: attachment.label,
        );
      case AttachmentKind.audio:
        child = _FallbackThumb(
          icon: Icons.graphic_eq_rounded,
          label: attachment.label,
        );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        color: background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (trimmedOverlayLabel.isNotEmpty)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xAA000000)],
                    ),
                  ),
                  child: Text(
                    trimmedOverlayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AttachmentPreviewSheet extends StatefulWidget {
  const AttachmentPreviewSheet({
    super.key,
    required this.attachments,
    required this.initialIndex,
  });

  final List<Attachment> attachments;
  final int initialIndex;

  @override
  State<AttachmentPreviewSheet> createState() => _AttachmentPreviewSheetState();
}

class _AttachmentPreviewSheetState extends State<AttachmentPreviewSheet> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _imageZoomed = false;
  OverlayEntry? _feedbackEntry;
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _feedbackEntry?.remove();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _saveCurrentImageToGallery(Attachment attachment) async {
    final state = AppScope.of(context);
    try {
      final saved = await state.saveAttachmentImageToGallery(attachment.id);
      if (!mounted) return;
      _showFeedback(saved == null ? '保存失败' : '已保存到系统相册');
    } on Exception catch (error) {
      if (!mounted) return;
      _showFeedback(state.cleanErrorForDisplay(error), isError: true);
    }
  }

  void _showFeedback(String message, {bool isError = false}) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final background = isError
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.inverseSurface;
    final foreground = isError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onInverseSurface;

    _feedbackTimer?.cancel();
    _feedbackEntry?.remove();
    _feedbackEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: 20,
        right: 20,
        bottom: mediaQuery.padding.bottom + 28,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isError
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 20,
                          color: foreground,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_feedbackEntry!);
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      _feedbackEntry?.remove();
      _feedbackEntry = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachments[_currentIndex];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    attachment.label,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (widget.attachments.length > 1)
                  Text(
                    '${_currentIndex + 1}/${widget.attachments.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (attachment.kind == AttachmentKind.image) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '保存到相册',
                    onPressed: () => _saveCurrentImageToGallery(attachment),
                    icon: const Icon(Icons.save_alt_rounded, size: 20),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${attachment.category} · 添加于 ${formatDateTime(attachment.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 360,
              child: PhotoViewGestureDetectorScope(
                axis: Axis.horizontal,
                child: PageView.builder(
                  controller: _pageController,
                  physics: _imageZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: widget.attachments.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                      _imageZoomed = false;
                    });
                  },
                  itemBuilder: (context, index) {
                    final current = widget.attachments[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: switch (current.kind) {
                        AttachmentKind.image => _ZoomableAttachmentImage(
                          attachment: current,
                          onZoomChanged: (zoomed) {
                            if (_currentIndex != index ||
                                _imageZoomed == zoomed) {
                              return;
                            }
                            setState(() => _imageZoomed = zoomed);
                          },
                        ),
                        AttachmentKind.video => PreviewVideoPlayer(
                          attachment: current,
                          label: current.label,
                        ),
                        AttachmentKind.audio => const _PreviewFallback(
                          icon: Icons.graphic_eq_rounded,
                          label: '音频素材暂不支持预览画面',
                        ),
                      },
                    );
                  },
                ),
              ),
            ),
            if (widget.attachments.length > 1) ...[
              const SizedBox(height: 12),
              Text(
                '左右滑动查看前后素材',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ZoomableAttachmentImage extends StatefulWidget {
  const _ZoomableAttachmentImage({
    required this.attachment,
    required this.onZoomChanged,
  });

  final Attachment attachment;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableAttachmentImage> createState() =>
      _ZoomableAttachmentImageState();
}

class _ZoomableAttachmentImageState extends State<_ZoomableAttachmentImage> {
  late final PhotoViewController _photoViewController;
  late final StreamSubscription<PhotoViewControllerValue>
  _photoViewSubscription;

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    _photoViewSubscription = _photoViewController.outputStateStream.listen(
      _notifyZoomChanged,
    );
  }

  @override
  void dispose() {
    _photoViewSubscription.cancel();
    _photoViewController.dispose();
    super.dispose();
  }

  void _notifyZoomChanged(PhotoViewControllerValue value) {
    widget.onZoomChanged((value.scale ?? 1) > 1.05);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: 1,
        child: _ResolvedAttachmentPhotoView(
          attachment: widget.attachment,
          controller: _photoViewController,
          onScaleEnd: (_, _, value) => _notifyZoomChanged(value),
        ),
      ),
    );
  }
}

class _ResolvedAttachmentPhotoView extends StatelessWidget {
  const _ResolvedAttachmentPhotoView({
    required this.attachment,
    required this.controller,
    required this.onScaleEnd,
  });

  final Attachment attachment;
  final PhotoViewController controller;
  final PhotoViewImageScaleEndCallback onScaleEnd;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return FutureBuilder<String>(
      future: state.resolveAttachmentPreviewUrl(attachment),
      builder: (context, snapshot) {
        final url = snapshot.data?.trim() ?? '';
        if (url.isEmpty) {
          return _FallbackThumb(
            icon: Icons.image_outlined,
            label: attachment.label,
          );
        }
        return PhotoView(
          imageProvider: NetworkImage(url),
          controller: controller,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          minScale: PhotoViewComputedScale.contained,
          initialScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 4,
          enablePanAlways: true,
          gaplessPlayback: true,
          onScaleEnd: onScaleEnd,
          loadingBuilder: (context, event) => ColoredBox(
            color: Colors.black,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  value: event?.expectedTotalBytes == null
                      ? null
                      : event!.cumulativeBytesLoaded /
                            event.expectedTotalBytes!,
                ),
              ),
            ),
          ),
          errorBuilder: (_, _, _) => _FallbackThumb(
            icon: Icons.image_outlined,
            label: attachment.label,
          ),
        );
      },
    );
  }
}

class PreviewVideoPlayer extends StatefulWidget {
  const PreviewVideoPlayer({
    super.key,
    required this.attachment,
    required this.label,
  });

  final Attachment attachment;
  final String label;

  @override
  State<PreviewVideoPlayer> createState() => _PreviewVideoPlayerState();
}

class _PreviewVideoPlayerState extends State<PreviewVideoPlayer> {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  bool _loading = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final url = await AppScope.of(
        context,
      ).resolveAttachmentPreviewUrl(widget.attachment);
      if (!mounted || url.trim().isEmpty) {
        setState(() {
          _loading = false;
        });
        return;
      }
      _controller = _createAttachmentVideoController(url);
      await _controller!.initialize();
      if (!mounted) return;
      final primaryColor = Theme.of(context).colorScheme.primary;
      _chewieController = ChewieController(
        videoPlayerController: _controller!,
        aspectRatio: _controller!.value.aspectRatio == 0
            ? 16 / 9
            : _controller!.value.aspectRatio,
        autoPlay: false,
        looping: false,
        showOptions: false,
        allowPlaybackSpeedChanging: false,
        customControls: const MovaVideoControls(),
        placeholder: const ColoredBox(color: Colors.black),
        materialProgressColors: ChewieProgressColors(
          playedColor: primaryColor,
          handleColor: primaryColor,
          bufferedColor: Colors.white38,
          backgroundColor: Colors.white24,
        ),
      );
    } catch (_) {
      // Keep preview fallback non-blocking when temporary authorization fails.
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 280,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _chewieController == null) {
      return _PreviewFallback(icon: Icons.movie_outlined, label: widget.label);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio == 0
              ? 16 / 9
              : _controller!.value.aspectRatio,
          child: Chewie(controller: _chewieController!),
        ),
      ),
    );
  }
}

class MovaVideoControls extends StatefulWidget {
  const MovaVideoControls({super.key});

  @override
  State<MovaVideoControls> createState() => _MovaVideoControlsState();
}

class _MovaVideoControlsState extends State<MovaVideoControls> {
  VideoPlayerController? _videoController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = ChewieController.of(context).videoPlayerController;
    if (_videoController == nextController) return;
    _videoController?.removeListener(_handleVideoChanged);
    _videoController = nextController..addListener(_handleVideoChanged);
  }

  @override
  void dispose() {
    _videoController?.removeListener(_handleVideoChanged);
    super.dispose();
  }

  void _handleVideoChanged() {
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    final controller = _videoController;
    if (controller == null) return;
    controller.value.isPlaying ? controller.pause() : controller.play();
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final chewieController = ChewieController.of(context);
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final value = controller.value;
    final duration = value.duration;
    final position = value.position > duration ? duration : value.position;
    final durationMs = duration.inMilliseconds.toDouble().clamp(
      1,
      double.infinity,
    );
    final positionMs = position.inMilliseconds.toDouble().clamp(0, durationMs);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _togglePlay,
          ),
        ),
        if (!value.isPlaying)
          Center(
            child: _VideoRoundButton(
              tooltip: '播放',
              icon: Icons.play_arrow_rounded,
              onPressed: _togglePlay,
              size: 50,
              iconSize: 30,
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xB8000000)],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _VideoRoundButton(
                      tooltip: value.isPlaying ? '暂停' : '播放',
                      icon: value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onPressed: _togglePlay,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${_formatDuration(position)} / ${_formatDuration(duration)}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _VideoRoundButton(
                      tooltip: chewieController.isFullScreen ? '退出全屏' : '全屏',
                      onPressed: chewieController.toggleFullScreen,
                      icon: chewieController.isFullScreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      size: 40,
                      iconSize: 22,
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Theme.of(context).colorScheme.primary,
                    overlayColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.18),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Slider(
                    min: 0,
                    max: durationMs.toDouble(),
                    value: positionMs.toDouble(),
                    onChanged: (nextValue) {
                      controller.seekTo(
                        Duration(milliseconds: nextValue.round()),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoRoundButton extends StatelessWidget {
  const _VideoRoundButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 36,
    this.iconSize = 22,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.52),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
      ),
    );
  }
}

class _ResolvedAttachmentImage extends StatelessWidget {
  const _ResolvedAttachmentImage({
    required this.attachment,
    this.width,
    this.height,
    required this.fit,
  });

  final Attachment attachment;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return FutureBuilder<String>(
      future: state.resolveAttachmentPreviewUrl(attachment),
      builder: (context, snapshot) {
        final url = snapshot.data?.trim() ?? '';
        if (url.isEmpty) {
          return _FallbackThumb(
            icon: Icons.image_outlined,
            label: attachment.label,
          );
        }
        return Image.network(
          url,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) => _FallbackThumb(
            icon: Icons.image_outlined,
            label: attachment.label,
          ),
        );
      },
    );
  }
}

class _ResolvedAttachmentVideoThumb extends StatefulWidget {
  const _ResolvedAttachmentVideoThumb({
    required this.attachment,
    required this.width,
    required this.height,
    required this.label,
  });

  final Attachment attachment;
  final double width;
  final double height;
  final String label;

  @override
  State<_ResolvedAttachmentVideoThumb> createState() =>
      _ResolvedAttachmentVideoThumbState();
}

class _ResolvedAttachmentVideoThumbState
    extends State<_ResolvedAttachmentVideoThumb> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final url = await AppScope.of(
        context,
      ).resolveAttachmentPreviewUrl(widget.attachment);
      if (!mounted || url.trim().isEmpty) {
        return;
      }
      _controller = _createAttachmentVideoController(url);
      await _controller!.initialize();
    } catch (_) {
      // Keep thumb fallback non-blocking when temporary authorization fails.
    }
    if (!mounted) return;
    setState(() {
      _ready = _controller?.value.isInitialized ?? false;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return _FallbackThumb(icon: Icons.movie_outlined, label: widget.label);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
        const Center(
          child: Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ],
    );
  }
}

class _VideoThumb extends StatefulWidget {
  const _VideoThumb({
    required this.url,
    required this.width,
    required this.height,
    required this.label,
  });

  final String url;
  final double width;
  final double height;
  final String label;

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = _createAttachmentVideoController(widget.url)
      ..initialize()
          .then((_) {
            if (!mounted) return;
            setState(() {
              _ready = true;
            });
          })
          .catchError((_) {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return _FallbackThumb(icon: Icons.movie_outlined, label: widget.label);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
        const Center(
          child: Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ],
    );
  }
}

VideoPlayerController _createAttachmentVideoController(String value) {
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return VideoPlayerController.networkUrl(uri);
  }
  if (uri != null && uri.scheme == 'content' && Platform.isAndroid) {
    return VideoPlayerController.contentUri(uri);
  }
  if (uri != null && uri.scheme == 'file') {
    return VideoPlayerController.file(File.fromUri(uri));
  }
  if (value.startsWith('/')) {
    return VideoPlayerController.file(File(value));
  }
  return VideoPlayerController.networkUrl(Uri.parse(value));
}

class _FallbackThumb extends StatelessWidget {
  const _FallbackThumb({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewFallback extends StatelessWidget {
  const _PreviewFallback({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
