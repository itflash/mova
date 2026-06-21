import 'dart:io';

import 'package:flutter/material.dart';
import '../app/spacing.dart';
import 'package:video_player/video_player.dart';

import '../app/app_scope.dart';
import '../app/app_state.dart';
import '../app/composition_models.dart';
import '../app/models.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/attachment_picker_sheet.dart';
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Tooltip(
                      message: '添加本地视频',
                      child: FilledButton.icon(
                        onPressed: state.pickAndAddLocalCompositionVideo,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('添加视频片段'),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          _pickAndAddAttachmentVideo(context, state),
                      icon: const Icon(Icons.video_library_rounded, size: 18),
                      label: const Text('素材库视频'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('输出设置'),
          UtilityPanel(
            child: Column(
              children: [
                AppDropdownField<String>(
                  value: project.output.resolution,
                  labelText: '分辨率',
                  items: const [
                    DropdownItemData(value: 'follow-first', label: '跟随首个片段'),
                    DropdownItemData(value: '720p', label: '720p'),
                    DropdownItemData(value: '1080p', label: '1080p'),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    state.updateCompositionOutput(
                      project.output.copyWith(resolution: value),
                    );
                  },
                ),
                const SizedBox(height: 14),
                AppDropdownField<String>(
                  value: project.output.ratio,
                  labelText: '比例',
                  items: const [
                    DropdownItemData(value: 'follow-first', label: '跟随首个片段'),
                    DropdownItemData(value: '16:9', label: '16:9'),
                    DropdownItemData(value: '9:16', label: '9:16'),
                    DropdownItemData(value: '1:1', label: '1:1'),
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
                AppDropdownField<CompositionAudioMode>(
                  value: project.audio.mode,
                  labelText: '音频模式',
                  items: CompositionAudioMode.values
                      .map(
                        (mode) => DropdownItemData(
                          value: mode,
                          label: _audioModeLabel(mode),
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
                  child: _NeutralActionButton(
                    onPressed: state.pickCompositionBgm,
                    icon: const Icon(Icons.music_note_rounded),
                    label: project.audio.bgmSource?.label ?? '选择 BGM',
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
                  InlineAlert(
                    title: '导出失败',
                    message: state.compositionExportErrorMessage!,
                    tone: InlineAlertTone.error,
                  ),
                ],
                if (isExporting) ...[
                  const SizedBox(height: 12),
                  ProgressRow(
                    label: state.compositionExportStage.isEmpty
                        ? '正在导出'
                        : state.compositionExportStage,
                    helper: '${state.compositionExportProgress}%',
                    value: state.compositionExportProgress <= 0
                        ? null
                        : state.compositionExportProgress / 100,
                  ),
                ],
                if (state.compositionExportResult != null) ...[
                  const SizedBox(height: 10),
                  InlineAlert(
                    title: '导出完成',
                    message: '已导出：${state.compositionExportResult!.fileName}',
                    tone: InlineAlertTone.success,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _NeutralActionButton(
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
                        label: '保存到相册/文件',
                      ),
                      _NeutralActionButton(
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
                        label: '导入素材库',
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

Future<void> _pickAndAddAttachmentVideo(
  BuildContext context,
  AppState state,
) async {
  final picked = await showAttachmentPickerSheet(
    context: context,
    state: state,
    title: '选择素材库视频',
    subtitle: '从素材库选择一个视频加入剪辑。',
    kind: AttachmentKind.video,
  );
  if (picked == null) return;

  try {
    final added = await state.addAttachmentVideoToComposition(picked.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(added ? '已添加到剪辑' : '添加失败')));
  } on Exception catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(state.cleanErrorForDisplay(error))),
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
                    borderRadius: BorderRadius.circular(AppRadius.control),
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
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: _CompositionClipPreview(uri: clip.sourceUri),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Tooltip(
                      message: '更换视频',
                      child: Material(
                        color: theme.colorScheme.surface,
                        shape: const CircleBorder(),
                        elevation: 2,
                        shadowColor: theme.colorScheme.shadow,
                        child: InkWell(
                          onTap: () =>
                              state.pickAndReplaceCompositionVideo(clip.id),
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: Icon(
                              Icons.swap_horiz_rounded,
                              size: 16,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
            AppDropdownField<CompositionTransitionType>(
              value: clip.transitionType,
              labelText: '转场',
              items: CompositionTransitionType.values
                  .map(
                    (type) => DropdownItemData(
                      value: type,
                      label: _transitionLabel(type),
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
            _ClipActionBar(
              onTrim: () => _openTrimSheet(context, state, clip),
              onMoveUp: () => state.moveCompositionClip(clip.id, -1),
              onMoveDown: () => state.moveCompositionClip(clip.id, 1),
              onDelete: () => state.removeCompositionClip(clip.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipActionBar extends StatelessWidget {
  const _ClipActionBar({
    required this.onTrim,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final VoidCallback onTrim;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ClipIconActionButton(
          label: '裁剪',
          icon: Icons.cut_rounded,
          onPressed: onTrim,
        ),
        _ClipIconActionButton(
          label: '上移',
          icon: Icons.arrow_upward_rounded,
          onPressed: onMoveUp,
        ),
        _ClipIconActionButton(
          label: '下移',
          icon: Icons.arrow_downward_rounded,
          onPressed: onMoveDown,
        ),
        _ClipIconActionButton(
          label: '删除',
          icon: Icons.delete_outline_rounded,
          onPressed: onDelete,
          foregroundColor: theme.colorScheme.error,
          backgroundColor: theme.colorScheme.errorContainer.withValues(
            alpha: 0.45,
          ),
          borderColor: theme.colorScheme.error.withValues(alpha: 0.45),
        ),
      ],
    );
  }
}

class _ClipIconActionButton extends StatelessWidget {
  const _ClipIconActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.foregroundColor,
    this.backgroundColor,
    this.borderColor,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = foregroundColor ?? theme.colorScheme.onSurfaceVariant;
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor:
            backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
        foregroundColor: color,
        fixedSize: const Size(40, 40),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        side: BorderSide(
          color:
              borderColor ??
              theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      icon: Icon(icon, size: 19),
    );
  }
}

class _NeutralActionButton extends StatelessWidget {
  const _NeutralActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          foregroundColor: theme.colorScheme.onSurface,
          disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.55),
          disabledForegroundColor: theme.colorScheme.onSurfaceVariant
              .withValues(alpha: 0.45),
          minimumSize: const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
        icon: IconTheme.merge(data: const IconThemeData(size: 18), child: icon),
        label: Text(label),
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
                  borderRadius: BorderRadius.circular(AppRadius.card),
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
              _TrimTimeline(
                durationMs: _durationMs,
                positionMs: _positionMs,
                startMs: _startMs,
                endMs: _endMs,
                enabled: controller != null,
                onChanged: controller == null
                    ? null
                    : (next) async {
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
                  _NeutralActionButton(
                    onPressed: () {
                      setState(() {
                        _startMs = _positionMs.clamp(0, _endMs - 1);
                      });
                    },
                    icon: const Icon(Icons.first_page_rounded),
                    label: '设为开始',
                  ),
                  _NeutralActionButton(
                    onPressed: () {
                      setState(() {
                        _endMs = _positionMs.clamp(_startMs + 1, _durationMs);
                      });
                    },
                    icon: const Icon(Icons.last_page_rounded),
                    label: '设为结束',
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

class _TrimTimeline extends StatelessWidget {
  const _TrimTimeline({
    required this.durationMs,
    required this.positionMs,
    required this.startMs,
    required this.endMs,
    required this.enabled,
    required this.onChanged,
  });

  final int durationMs;
  final int positionMs;
  final int startMs;
  final int endMs;
  final bool enabled;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = durationMs <= 0 ? 1 : durationMs;
    final start = startMs.clamp(0, max).toDouble() / max;
    final end = endMs.clamp(0, max).toDouble() / max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label:
              '裁剪时间轴，开始 ${_formatMs(startMs)}，结束 ${_formatMs(endMs)}，当前位置 ${_formatMs(positionMs)}',
          child: SizedBox(
            height: 48,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final startX = width * start;
                final endX = width * end;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 20,
                      right: 20,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20 + (startX - 20).clamp(0, width - 40),
                      width: (endX - startX).clamp(0, width - 40),
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (startX - 8).clamp(0, width - 16),
                      child: _TimelineMarker(color: theme.colorScheme.primary),
                    ),
                    Positioned(
                      left: (endX - 8).clamp(0, width - 16),
                      child: _TimelineMarker(color: theme.colorScheme.tertiary),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                        secondaryActiveTrackColor: Colors.transparent,
                        disabledActiveTrackColor: Colors.transparent,
                        disabledInactiveTrackColor: Colors.transparent,
                        trackHeight: 0,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                          disabledThumbRadius: 8,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                      ),
                      child: Slider(
                        value: positionMs.clamp(0, max).toDouble(),
                        min: 0,
                        max: max.toDouble(),
                        label: _formatMs(positionMs),
                        onChanged: enabled
                            ? (value) => onChanged?.call(value.round())
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineMarker extends StatelessWidget {
  const _TimelineMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 2,
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
  bool _ready = false;
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
      _ready = false;
      _error = null;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final controller = _createVideoController(widget.uri);
    _controller = controller;
    try {
      final missingFile = _missingLocalVideoPath(widget.uri);
      if (missingFile != null) {
        throw StateError('本地视频文件不存在：$missingFile');
      }
      await controller.initialize();
      await controller.setVolume(0);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _error = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Composition preview failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _ready = false;
        _error = _previewErrorMessage(error);
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
    if (!_ready || controller == null || !controller.value.isInitialized) {
      return _PreviewFallback(label: _error ?? '视频暂不可播放');
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        controller.value.isPlaying
            ? await controller.pause()
            : await controller.play();
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
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.13),
                  Colors.black.withValues(alpha: 0.54),
                ],
              ),
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

String? _missingLocalVideoPath(String value) {
  final uri = Uri.tryParse(value);
  if (uri != null && uri.scheme == 'file') {
    final path = uri.toFilePath();
    return File(path).existsSync() ? null : path;
  }
  if (value.startsWith('/')) {
    return File(value).existsSync() ? null : value;
  }
  return null;
}

String _previewErrorMessage(Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '');
  if (raw.contains('本地视频文件不存在')) {
    return '视频文件已失效，请重新选择。';
  }
  return '视频暂不可播放，请更换视频后重试。';
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
