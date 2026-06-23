import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import '../app/spacing.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../app/app_scope.dart';
import '../app/app_state.dart';
import '../app/models.dart';
import '../services/preview_cache_service.dart';

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
                    borderRadius: BorderRadius.circular(AppRadius.sheet),
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
      borderRadius: BorderRadius.circular(AppRadius.card),
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
          imageProvider: CachedNetworkImageProvider(
            url,
            cacheKey: previewCacheKey(attachment),
          ),
          // 使用稳定 cacheKey 避免七牛签名 URL 刷新后缓存失效。
          // CachedNetworkImageProvider 自带磁盘缓存，签名变化仍命中同一份图片。
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

  /// 兜底下载状态，用于在 UI 上展示「正在准备预览 / 正在下载 N% / 预览准备失败」。
  _PreviewFallbackStatus _fallbackStatus = _PreviewFallbackStatus.idle;
  int _downloadProgress = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _initialize();
  }

  Future<void> _initialize() async {
    final state = AppScope.of(context);
    var url = '';
    try {
      url = await state.resolveAttachmentPreviewUrl(widget.attachment);
      if (!mounted || url.trim().isEmpty) {
        setState(() {
          _loading = false;
        });
        return;
      }
      await _initializeController(_createAttachmentVideoController(url));
    } catch (_) {
      await _disposeControllers();
      if (mounted) {
        setState(() => _fallbackStatus = _PreviewFallbackStatus.preparing);
      }
      await _initializeDownloadedFallback(state, url);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  /// 七牛私有视频远程流式播放失败后的兜底：先查本地预览缓存，命中直接播放；
  /// 未命中才下载签名 URL 到缓存文件，下载过程中展示进度。
  /// 缓存文件按素材稳定 key 存放，重复点击预览不会重复下载。
  Future<void> _initializeDownloadedFallback(AppState state, String url) async {
    if (!mounted || url.trim().isEmpty) return;
    final cacheService = PreviewCacheService.instance;
    try {
      // 先查本地缓存，命中则直接播放，避免重复下载大视频。
      final cached = await cacheService.videoCacheFile(widget.attachment);
      if (cached != null) {
        if (!mounted) return;
        await _initializeController(VideoPlayerController.file(cached));
        return;
      }
      // 未命中：下载到缓存文件，展示下载进度。
      if (mounted) {
        setState(() {
          _fallbackStatus = _PreviewFallbackStatus.downloading;
          _downloadProgress = 0;
        });
      }
      final file = await cacheService.downloadToVideoCache(
        widget.attachment,
        url,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _downloadProgress = progress);
          }
        },
      );
      if (!mounted) return;
      await _initializeController(VideoPlayerController.file(file));
    } catch (_) {
      // 下载或初始化失败：标记预览准备失败，展示错误占位。
      if (mounted) {
        setState(() => _fallbackStatus = _PreviewFallbackStatus.failed);
      }
    }
  }

  Future<void> _initializeController(VideoPlayerController controller) async {
    _controller = controller;
    await controller.initialize();
    if (!mounted) return;
    final primaryColor = Theme.of(context).colorScheme.primary;
    _chewieController = ChewieController(
      videoPlayerController: controller,
      aspectRatio: controller.value.aspectRatio == 0
          ? 16 / 9
          : controller.value.aspectRatio,
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
  }

  Future<void> _disposeControllers() async {
    _chewieController?.dispose();
    _chewieController = null;
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
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
      return _PreviewStatusBox(
        icon: Icons.movie_outlined,
        label: _fallbackStatus == _PreviewFallbackStatus.downloading
            ? '正在下载 $_downloadProgress%'
            : _fallbackStatus == _PreviewFallbackStatus.preparing
            ? '正在准备预览'
            : _fallbackStatus == _PreviewFallbackStatus.failed
            ? '预览准备失败'
            : widget.label,
        progress: _fallbackStatus == _PreviewFallbackStatus.downloading
            ? _downloadProgress / 100.0
            : null,
      );
    }

    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _chewieController == null) {
      if (_fallbackStatus == _PreviewFallbackStatus.downloading) {
        return _PreviewStatusBox(
          icon: Icons.movie_outlined,
          label: '正在下载 $_downloadProgress%',
          progress: _downloadProgress / 100.0,
        );
      }
      if (_fallbackStatus == _PreviewFallbackStatus.failed) {
        return _PreviewStatusBox(
          icon: Icons.error_outline_rounded,
          label: '预览准备失败',
        );
      }
      return _PreviewFallback(icon: Icons.movie_outlined, label: widget.label);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: ColoredBox(
        color: Colors.black,
        child: Chewie(controller: _chewieController!),
      ),
    );
  }
}

class MovaVideoControls extends StatefulWidget {
  const MovaVideoControls({super.key, this.trimStartMs, this.trimEndMs});

  final int? trimStartMs;
  final int? trimEndMs;

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
    final fullDuration = value.duration;
    final trimStart = (widget.trimStartMs ?? 0).toDouble();
    final trimEnd = (widget.trimEndMs != null && widget.trimEndMs! > 0
        ? widget.trimEndMs!.toDouble()
        : fullDuration.inMilliseconds.toDouble());
    final trimDuration = trimEnd - trimStart;
    final fullPos = value.position > fullDuration
        ? fullDuration
        : value.position;
    final relPos = (fullPos.inMilliseconds.toDouble() - trimStart).clamp(
      0.0,
      trimDuration,
    );
    final durationMs = trimDuration.clamp(1.0, double.infinity);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _togglePlay,
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
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    children: [
                      _VideoRoundButton(
                        tooltip: value.isPlaying ? '暂停' : '播放',
                        icon: value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onPressed: _togglePlay,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_formatDuration(Duration(milliseconds: relPos.round()))} / ${_formatDuration(Duration(milliseconds: trimDuration.round()))}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    padding: EdgeInsets.zero,
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
                    padding: EdgeInsets.zero,
                    min: 0,
                    max: durationMs,
                    value: relPos,
                    onChanged: (nextValue) {
                      controller.seekTo(
                        Duration(milliseconds: (trimStart + nextValue).round()),
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

class _ResolvedAttachmentImage extends StatefulWidget {
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
  State<_ResolvedAttachmentImage> createState() =>
      _ResolvedAttachmentImageState();
}

class _ResolvedAttachmentImageState extends State<_ResolvedAttachmentImage> {
  String? _url;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  Future<void> _resolveUrl() async {
    final url = await AppScope.of(
      context,
    ).resolveAttachmentPreviewUrl(widget.attachment);
    if (!mounted) return;
    setState(() {
      _url = url.trim().isEmpty ? null : url.trim();
      _loading = false;
    });
  }

  @override
  void didUpdateWidget(covariant _ResolvedAttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prev = oldWidget.attachment;
    final next = widget.attachment;
    if (prev.id != next.id ||
        prev.objectKey != next.objectKey ||
        prev.url != next.url ||
        prev.storageProvider != next.storageProvider) {
      // 列表项复用时 attachment 已变（例如刚上传新素材后列表重建），
      // 需重新解析预览 URL，否则会显示上一项的缓存图。
      _url = null;
      _loading = true;
      _resolveUrl();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _ThumbPlaceholder(width: widget.width, height: widget.height);
    }
    final url = _url;
    if (url == null) {
      return _FallbackThumb(
        icon: Icons.image_outlined,
        label: widget.attachment.label,
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, _) =>
          _ThumbPlaceholder(width: widget.width, height: widget.height),
      errorWidget: (_, _, _) => _FallbackThumb(
        icon: Icons.image_outlined,
        label: widget.attachment.label,
      ),
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
  // 缩略图用 ffmpeg 抽首帧缓存到本地，不再为每个列表项建 VideoPlayerController。
  // 后者会真正初始化原生解码器，列表里几十个视频项会同时建几十个解码器，
  // 是素材库滚动卡顿的主因。ffmpeg 抽帧轻量，且结果按 url 哈希缓存到磁盘，
  // 滚动回来直接读已有图片，不重复抽帧。
  String? _thumbPath;
  bool _loading = false;
  bool _initialized = false;
  String? _resolvedUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _ResolvedAttachmentVideoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_attachmentChanged(oldWidget.attachment, widget.attachment)) {
      // 列表项复用且 attachment 变了：重置缩略图状态并按新素材重新抽帧。
      _thumbPath = null;
      _resolvedUrl = null;
      _loadThumbnail();
    }
  }

  bool _attachmentChanged(Attachment a, Attachment b) {
    return a.id != b.id ||
        a.objectKey != b.objectKey ||
        a.url != b.url ||
        a.storageProvider != b.storageProvider;
  }

  Future<void> _loadThumbnail() async {
    setState(() => _loading = true);
    try {
      final url = await AppScope.of(
        context,
      ).resolveAttachmentPreviewUrl(widget.attachment);
      if (!mounted || url.trim().isEmpty) {
        setState(() => _loading = false);
        return;
      }
      _resolvedUrl = url.trim();
      // 用稳定的 previewCacheKey 做缓存文件名，避免签名 URL 刷新后
      // hash 变化导致缓存失效、每次滚动都重新抽帧。
      final stableKey = previewCacheKey(widget.attachment);
      final cached = await PreviewCacheService.instance.cachedVideoThumbnail(
        _resolvedUrl!,
        cacheKey: stableKey,
      );
      if (!mounted) return;
      setState(() {
        _thumbPath = cached;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _thumbPath;
    if (path != null && path.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(path),
            fit: BoxFit.cover,
            width: widget.width,
            height: widget.height,
            gaplessPlayback: true,
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
    if (_loading) {
      return _ThumbPlaceholder(width: widget.width, height: widget.height);
    }
    return _FallbackThumb(icon: Icons.movie_outlined, label: widget.label);
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
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

/// 视频兜底下载的状态，用于 UI 展示准备进度。
enum _PreviewFallbackStatus { idle, preparing, downloading, failed }

/// 预览状态占位框：展示图标 + 文字，可选进度条（兜底下载时用）。
/// 高度与 _PreviewFallback 保持一致（280），确保切换状态时布局不跳动。
class _PreviewStatusBox extends StatelessWidget {
  const _PreviewStatusBox({
    required this.icon,
    required this.label,
    this.progress,
  });

  final IconData icon;
  final String label;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
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
          if (progress != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHigh,
                ),
              ),
            ),
          ] else if (_isBusyLabel(label)) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isBusyLabel(String label) =>
      label.startsWith('正在准备') || label.startsWith('正在下载');
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
        borderRadius: BorderRadius.circular(AppRadius.card),
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
