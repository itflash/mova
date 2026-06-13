import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app/app_scope.dart';
import '../app/models.dart';
import 'home_shell.dart';

class VideoFrameCapturePage extends StatefulWidget {
  const VideoFrameCapturePage({
    super.key,
    required this.source,
    required this.entryContext,
    this.defaultCategory = '',
  });

  final VideoFrameSource source;
  final VideoFrameEntryContext entryContext;
  final String defaultCategory;

  @override
  State<VideoFrameCapturePage> createState() => _VideoFrameCapturePageState();
}

class _VideoFrameCapturePageState extends State<VideoFrameCapturePage> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _capturing = false;
  String? _error;
  double _selectedMs = 0;
  Future<void>? _pendingSeek;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final source = widget.source.sourceUri.trim();
      if (source.isEmpty) {
        throw const FileSystemException('缺少可用的视频地址。');
      }
      AppScope.read(context).rememberVideoFrameSource(widget.source);
      final uri = Uri.parse(source);
      final controller = source.startsWith('content://')
          ? VideoPlayerController.contentUri(uri)
          : source.startsWith('file://')
          ? VideoPlayerController.file(File(uri.toFilePath()))
          : source.startsWith('/')
          ? VideoPlayerController.file(File(source))
          : VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('PlatformException(', '')
            .replaceFirst(RegExp(r', null\)$'), '');
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Duration get _duration => _controller?.value.duration ?? Duration.zero;

  int get _selectedPositionMs {
    final maxMs = _duration.inMilliseconds;
    if (maxMs <= 0) return 0;
    return _selectedMs.round().clamp(0, maxMs);
  }

  Future<void> _jumpToMs(int milliseconds) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final maxMs = _duration.inMilliseconds;
    final next = milliseconds.clamp(0, maxMs);
    final seekFuture = () async {
      await controller.pause();
      await controller.seekTo(Duration(milliseconds: next));
      if (!mounted) return;
      setState(() {
        _selectedMs = next.toDouble();
      });
    }();
    _pendingSeek = seekFuture;
    await seekFuture;
    if (identical(_pendingSeek, seekFuture)) {
      _pendingSeek = null;
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() {
      _capturing = true;
    });
    try {
      final state = AppScope.of(context);
      await _pendingSeek;
      final effectivePositionMs = controller.value.position.inMilliseconds
          .clamp(0, _duration.inMilliseconds);
      if (mounted && effectivePositionMs != _selectedPositionMs) {
        setState(() {
          _selectedMs = effectivePositionMs.toDouble();
        });
      }
      final result = await state.captureVideoFrame(
        sourceUri: widget.source.sourceUri,
        positionMs: effectivePositionMs,
        suggestedFileName:
            'frame-${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      if (!mounted) return;
      final action = await showModalBottomSheet<_CapturedFrameAction>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) => _CapturedFrameResultSheet(
          frame: result,
          entryContext: widget.entryContext,
          defaultLabel:
              '${widget.source.label}-${_formatTimestamp(Duration(milliseconds: result.positionMs)).replaceAll(':', '-').replaceAll('.', '-')}',
          defaultCategory: widget.defaultCategory,
        ),
      );
      if (!mounted || action == null) return;
      switch (action.type) {
        case _CapturedFrameActionType.retry:
          return;
        case _CapturedFrameActionType.localOnly:
          Navigator.of(context).pop();
        case _CapturedFrameActionType.saveToGallery:
          final saved = await state.saveCapturedFrameToGallery(result);
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(saved == null ? '保存失败' : '已保存到系统相册')),
            );
          return;
        case _CapturedFrameActionType.upload:
          final attachmentId = await state.importCapturedFrameToLibrary(
            result,
            label: action.label,
            category: action.category,
            role: action.role,
          );
          if (!mounted) return;
          if (widget.entryContext == VideoFrameEntryContext.createFirstFrame) {
            state.selectVideoFrameAttachment(
              attachmentId,
              role: AttachmentRole.firstFrame,
            );
          } else if (widget.entryContext ==
              VideoFrameEntryContext.createLastFrame) {
            state.selectVideoFrameAttachment(
              attachmentId,
              role: AttachmentRole.lastFrame,
            );
          }
          Navigator.of(context).pop(true);
      }
    } on Exception catch (error) {
      if (!mounted) return;
      final state = AppScope.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(state.cleanErrorForDisplay(error))),
        );
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = _controller;
    final duration = _duration;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.75),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '视频截帧',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.source.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? _CaptureErrorState(message: _error!)
                        : controller == null || !controller.value.isInitialized
                        ? const _CaptureErrorState(message: '视频暂时无法预览。')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: ColoredBox(
                                    color: Colors.black,
                                    child: Center(
                                      child: AspectRatio(
                                        aspectRatio:
                                            controller.value.aspectRatio == 0
                                            ? 16 / 9
                                            : controller.value.aspectRatio,
                                        child: VideoPlayer(controller),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                '${_formatTimestamp(Duration(milliseconds: _selectedPositionMs))} / ${_formatTimestamp(duration)}',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 10),
                              Slider(
                                value: duration.inMilliseconds <= 0
                                    ? 0
                                    : _selectedMs.clamp(
                                        0,
                                        duration.inMilliseconds.toDouble(),
                                      ),
                                max: duration.inMilliseconds <= 0
                                    ? 1
                                    : duration.inMilliseconds.toDouble(),
                                onChanged: (value) async {
                                  setState(() {
                                    _selectedMs = value;
                                  });
                                },
                                onChangeEnd: (value) => _jumpToMs(value.round()),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  CapsuleButton(
                                    label: '首帧',
                                    icon: Icons.first_page_rounded,
                                    onPressed: () => _jumpToMs(0),
                                  ),
                                  CapsuleButton(
                                    label: '尾帧',
                                    icon: Icons.last_page_rounded,
                                    onPressed: () => _jumpToMs(
                                      duration.inMilliseconds,
                                    ),
                                  ),
                                  CapsuleButton(
                                    label: '-1s',
                                    icon: Icons.replay_10_rounded,
                                    onPressed: () => _jumpToMs(
                                      _selectedPositionMs - 1000,
                                    ),
                                  ),
                                  CapsuleButton(
                                    label: '+1s',
                                    icon: Icons.forward_10_rounded,
                                    onPressed: () => _jumpToMs(
                                      _selectedPositionMs + 1000,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _loading || _error != null || _capturing ? null : _capture,
                    icon: _capturing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_back_outlined),
                    label: Text(_capturing ? '正在截取…' : '完成截取'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptureErrorState extends StatelessWidget {
  const _CaptureErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.movie_creation_outlined,
            size: 36,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            '视频暂时不可用',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

enum _CapturedFrameActionType { upload, saveToGallery, localOnly, retry }

class _CapturedFrameAction {
  const _CapturedFrameAction({
    required this.type,
    this.label = '',
    this.category = '',
    this.role = AttachmentRole.referenceImage,
  });

  final _CapturedFrameActionType type;
  final String label;
  final String category;
  final AttachmentRole role;
}

class _CapturedFrameResultSheet extends StatefulWidget {
  const _CapturedFrameResultSheet({
    required this.frame,
    required this.entryContext,
    required this.defaultLabel,
    required this.defaultCategory,
  });

  final CapturedFrameResult frame;
  final VideoFrameEntryContext entryContext;
  final String defaultLabel;
  final String defaultCategory;

  @override
  State<_CapturedFrameResultSheet> createState() =>
      _CapturedFrameResultSheetState();
}

class _CapturedFrameResultSheetState extends State<_CapturedFrameResultSheet> {
  late final TextEditingController _labelController;
  late final TextEditingController _categoryController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.defaultLabel);
    _categoryController = TextEditingController(text: widget.defaultCategory);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageFile = File(widget.frame.path);
    final state = AppScope.of(context);
    final isCreateEntry =
        widget.entryContext == VideoFrameEntryContext.createFirstFrame ||
        widget.entryContext == VideoFrameEntryContext.createLastFrame;
    final defaultRole =
        widget.entryContext == VideoFrameEntryContext.createLastFrame
        ? AttachmentRole.lastFrame
        : isCreateEntry
        ? AttachmentRole.firstFrame
        : AttachmentRole.referenceImage;

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
            Text('已截取画面', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '这张画面可以上传到素材库，也可以只用于本次操作。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.file(
                imageFile,
                fit: BoxFit.cover,
                height: 220,
                errorBuilder: (_, _, _) => Container(
                  height: 220,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(labelText: '素材名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: '分类'),
            ),
            const SizedBox(height: 18),
            if (!state.isCurrentStorageConfigured) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '当前还没有可用的${state.currentStorageProviderLabel}配置，暂时不能上传到素材库。你仍然可以先保存到相册。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: state.isCurrentStorageConfigured
                  ? () => Navigator.of(context).pop(
                      _CapturedFrameAction(
                        type: _CapturedFrameActionType.upload,
                        label: _labelController.text.trim().isEmpty
                            ? widget.defaultLabel
                            : _labelController.text.trim(),
                        category: _categoryController.text.trim(),
                        role: defaultRole,
                      ),
                    )
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(isCreateEntry ? '上传到素材库并使用' : '上传到素材库'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(
                const _CapturedFrameAction(
                  type: _CapturedFrameActionType.saveToGallery,
                ),
              ),
              icon: const Icon(Icons.download_rounded),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              label: const Text('保存到相册'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(
                const _CapturedFrameAction(type: _CapturedFrameActionType.localOnly),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(isCreateEntry ? '稍后再处理' : '仅保存到本地'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                const _CapturedFrameAction(type: _CapturedFrameActionType.retry),
              ),
              child: const Text('重新截取'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTimestamp(Duration value) {
  String two(int number) => number.toString().padLeft(2, '0');
  final minutes = two(value.inMinutes.remainder(60));
  final seconds = two(value.inSeconds.remainder(60));
  final millis = value.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
  return '$minutes:$seconds.$millis';
}
