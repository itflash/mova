import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app/app_scope.dart';
import '../app/app_state.dart';
import '../app/composition_models.dart';
import 'home_shell.dart';

class CompositionPage extends StatelessWidget {
  const CompositionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final project = state.compositionProject;
    final isExporting = state.isExportingComposition;

    return AppPageScaffold(
      eyebrow: 'Clip',
      title: '视频剪辑',
      subtitle: '裁剪多个视频片段，添加转场和 BGM。',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 112),
        children: [
          const SectionLabel('片段'),
          UtilityPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.clips.isEmpty
                      ? '添加视频后，可以裁剪片段、调整顺序和设置转场。'
                      : '已添加 ${project.clips.length} 个视频片段，按顺序合成为一个视频。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (project.clips.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (final clip in project.clips) ...[
                    _CompositionClipCard(clip: clip, state: state),
                    const SizedBox(height: 12),
                  ],
                ],
                const SizedBox(height: 14),
                Tooltip(
                  message: '添加本地视频',
                  child: FilledButton.icon(
                    onPressed: state.pickAndAddLocalCompositionVideo,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('添加视频片段'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('输出设置'),
          UtilityPanel(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: project.output.resolution,
                  decoration: const InputDecoration(labelText: '分辨率'),
                  items: const [
                    DropdownMenuItem(
                      value: 'follow-first',
                      child: Text('跟随首个片段'),
                    ),
                    DropdownMenuItem(value: '720p', child: Text('720p')),
                    DropdownMenuItem(value: '1080p', child: Text('1080p')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    state.updateCompositionOutput(
                      project.output.copyWith(resolution: value),
                    );
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: project.output.ratio,
                  decoration: const InputDecoration(labelText: '比例'),
                  items: const [
                    DropdownMenuItem(
                      value: 'follow-first',
                      child: Text('跟随首个片段'),
                    ),
                    DropdownMenuItem(value: '16:9', child: Text('16:9')),
                    DropdownMenuItem(value: '9:16', child: Text('9:16')),
                    DropdownMenuItem(value: '1:1', child: Text('1:1')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    state.updateCompositionOutput(
                      project.output.copyWith(ratio: value),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('音频'),
          UtilityPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<CompositionAudioMode>(
                  initialValue: project.audio.mode,
                  decoration: const InputDecoration(labelText: '音频模式'),
                  items: CompositionAudioMode.values
                      .map(
                        (mode) => DropdownMenuItem(
                          value: mode,
                          child: Text(_audioModeLabel(mode)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    state.updateCompositionAudio(
                      project.audio.copyWith(mode: value),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: state.pickCompositionBgm,
                    icon: const Icon(Icons.music_note_rounded),
                    label: Text(project.audio.bgmSource?.label ?? '选择 BGM'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('导出'),
          UtilityPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: project.canExport && !isExporting
                      ? state.exportComposition
                      : null,
                  icon: isExporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_rounded),
                  label: Text(isExporting ? '导出中' : '导出合成视频'),
                ),
                if (state.compositionExportErrorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    state.compositionExportErrorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (state.compositionExportResult != null) ...[
                  const SizedBox(height: 10),
                  Text('已导出：${state.compositionExportResult!.fileName}'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final saved = await state
                              .saveCompositionExportToGallery();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(
                                  saved == null ? '保存失败' : '已保存到系统相册',
                                ),
                              ),
                            );
                        },
                        icon: const Icon(Icons.save_alt_rounded),
                        label: const Text('保存到相册/文件'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          try {
                            final attachmentId = await state
                                .importCompositionExportToLibrary();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    attachmentId == null ? '导入失败' : '已导入素材库',
                                  ),
                                ),
                              );
                          } on Exception catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    state.cleanErrorForDisplay(error),
                                  ),
                                ),
                              );
                          }
                        },
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('导入素材库'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompositionClipCard extends StatelessWidget {
  const _CompositionClipCard({required this.clip, required this.state});

  final CompositionClip clip;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.movie_creation_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clip.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '片段 ${_formatMs(clip.startMs)} - ${_formatMs(clip.endMs)} · ${_transitionLabel(clip.transitionType)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _CompositionClipPreview(uri: clip.sourceUri),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '点击“裁剪”可以重新设置开始和结束位置。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CompositionTransitionType>(
              initialValue: clip.transitionType,
              decoration: const InputDecoration(labelText: '转场'),
              items: CompositionTransitionType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(_transitionLabel(type)),
                    ),
                  )
                  .toList(),
              onChanged: (type) {
                if (type == null) return;
                state.updateCompositionClip(
                  clip.id,
                  (current) => current.copyWith(transitionType: type),
                );
              },
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _openTrimSheet(context, state, clip),
                  icon: const Icon(Icons.cut_rounded),
                  label: const Text('裁剪'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => state.moveCompositionClip(clip.id, -1),
                  icon: const Icon(Icons.arrow_upward_rounded),
                  label: const Text('上移'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => state.moveCompositionClip(clip.id, 1),
                  icon: const Icon(Icons.arrow_downward_rounded),
                  label: const Text('下移'),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () => state.removeCompositionClip(clip.id),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openTrimSheet(
  BuildContext context,
  AppState state,
  CompositionClip clip,
) async {
  final updated = await showModalBottomSheet<CompositionClip>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => _ClipTrimSheet(clip: clip),
  );
  if (updated == null) return;
  state.updateCompositionClip(clip.id, (_) => updated);
}

class _ClipTrimSheet extends StatefulWidget {
  const _ClipTrimSheet({required this.clip});

  final CompositionClip clip;

  @override
  State<_ClipTrimSheet> createState() => _ClipTrimSheetState();
}

class _ClipTrimSheetState extends State<_ClipTrimSheet> {
  late int _startMs;
  late int _endMs;
  int _positionMs = 0;
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startMs = widget.clip.startMs;
    _endMs = widget.clip.endMs;
    _positionMs = widget.clip.startMs;
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final controller = _createVideoController(widget.clip.sourceUri);
      await controller.initialize();
      await controller.setVolume(0);
      await controller.seekTo(Duration(milliseconds: _positionMs));
      controller.addListener(_syncPosition);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _syncPosition() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = controller.value.position.inMilliseconds;
    if ((next - _positionMs).abs() < 250) return;
    setState(() {
      _positionMs = next;
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_syncPosition);
    _controller?.dispose();
    super.dispose();
  }

  int get _durationMs {
    final controller = _controller;
    final duration = controller?.value.duration.inMilliseconds ?? 0;
    return duration > 0 ? duration : (_endMs > 0 ? _endMs : 1);
  }

  bool get _canSave => _endMs > _startMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final controller = _controller;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('裁剪片段', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          '拖动时间轴到目标位置，再设为开始或结束。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: _error != null
                      ? _PreviewFallback(label: '预览失败：$_error')
                      : controller == null || !controller.value.isInitialized
                      ? const _PreviewFallback(label: '载入预览中')
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            FittedBox(
                              fit: BoxFit.contain,
                              child: SizedBox(
                                width: controller.value.size.width,
                                height: controller.value.size.height,
                                child: VideoPlayer(controller),
                              ),
                            ),
                            Center(
                              child: IconButton.filled(
                                tooltip: controller.value.isPlaying
                                    ? '暂停'
                                    : '播放',
                                onPressed: () async {
                                  if (controller.value.isPlaying) {
                                    await controller.pause();
                                  } else {
                                    await controller.play();
                                  }
                                  if (mounted) setState(() {});
                                },
                                icon: Icon(
                                  controller.value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '当前位置 ${_formatMs(_positionMs)} · 范围 ${_formatMs(_startMs)} - ${_formatMs(_endMs)}',
                style: theme.textTheme.bodyMedium,
              ),
              Slider(
                value: _positionMs.clamp(0, _durationMs).toDouble(),
                min: 0,
                max: _durationMs.toDouble(),
                label: _formatMs(_positionMs),
                onChanged: controller == null
                    ? null
                    : (value) async {
                        final next = value.round();
                        setState(() {
                          _positionMs = next;
                        });
                        await controller.seekTo(Duration(milliseconds: next));
                      },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() {
                        _startMs = _positionMs.clamp(0, _endMs - 1);
                      });
                    },
                    icon: const Icon(Icons.first_page_rounded),
                    label: const Text('设为开始'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() {
                        _endMs = _positionMs.clamp(_startMs + 1, _durationMs);
                      });
                    },
                    icon: const Icon(Icons.last_page_rounded),
                    label: const Text('设为结束'),
                  ),
                ],
              ),
              if (!_canSave) ...[
                const SizedBox(height: 8),
                Text(
                  '结束时间必须晚于开始时间。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _canSave
                    ? () {
                        Navigator.of(context).pop(
                          widget.clip.copyWith(
                            startMs: _startMs,
                            endMs: _endMs,
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('保存裁剪'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompositionClipPreview extends StatefulWidget {
  const _CompositionClipPreview({required this.uri});

  final String uri;

  @override
  State<_CompositionClipPreview> createState() =>
      _CompositionClipPreviewState();
}

class _CompositionClipPreviewState extends State<_CompositionClipPreview> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(_CompositionClipPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) {
      _controller?.dispose();
      _controller = null;
      _error = null;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    try {
      final controller = _createVideoController(widget.uri);
      await controller.initialize();
      await controller.setVolume(0);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return _PreviewFallback(label: '预览失败：$_error');
    }
    if (controller == null || !controller.value.isInitialized) {
      return const _PreviewFallback(label: '载入预览中');
    }
    return GestureDetector(
      onTap: () async {
        if (controller.value.isPlaying) {
          await controller.pause();
        } else {
          await controller.play();
        }
        if (mounted) setState(() {});
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          if (!controller.value.isPlaying)
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewFallback extends StatelessWidget {
  const _PreviewFallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_outlined, color: Colors.white70, size: 36),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

VideoPlayerController _createVideoController(String value) {
  final uri = Uri.parse(value);
  if (value.startsWith('content://')) {
    return VideoPlayerController.contentUri(uri);
  }
  if (value.startsWith('file://')) {
    return VideoPlayerController.file(File(uri.toFilePath()));
  }
  if (value.startsWith('/')) {
    return VideoPlayerController.file(File(value));
  }
  return VideoPlayerController.networkUrl(uri);
}

String _formatMs(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _transitionLabel(CompositionTransitionType type) {
  return switch (type) {
    CompositionTransitionType.none => '无',
    CompositionTransitionType.fade => '淡入淡出',
    CompositionTransitionType.crossDissolve => '交叉溶解',
    CompositionTransitionType.black => '黑场过渡',
    CompositionTransitionType.whiteFlash => '白场闪切',
  };
}

String _audioModeLabel(CompositionAudioMode mode) {
  return switch (mode) {
    CompositionAudioMode.keepOriginal => '保留原声',
    CompositionAudioMode.muted => '静音',
    CompositionAudioMode.originalPlusBgm => '原声 + BGM',
    CompositionAudioMode.bgmOnly => '仅 BGM',
  };
}
