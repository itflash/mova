import 'package:flutter/material.dart';
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
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xAA000000)],
                  ),
                ),
                child: Text(
                  overlayLabel,
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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.attachments.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final current = widget.attachments[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: switch (current.kind) {
                      AttachmentKind.image => ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: _ResolvedAttachmentImage(
                              attachment: current,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
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
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await _controller!.initialize();
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

    if (_controller == null || !_controller!.value.isInitialized) {
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: VideoPlayer(_controller!)),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xB3000000)],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () {
                          final controller = _controller;
                          if (controller == null) return;
                          setState(() {
                            if (controller.value.isPlaying) {
                              controller.pause();
                            } else {
                              controller.play();
                            }
                          });
                        },
                        icon: Icon(
                          _controller!.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _controller!.value.isPlaying ? '播放中' : '点击播放',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
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
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
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
