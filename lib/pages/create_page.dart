import 'package:flutter/material.dart';
import '../app/spacing.dart';
import 'package:video_player/video_player.dart';

import '../app/app_scope.dart';
import '../app/app_state.dart';
import '../app/mock_data.dart';
import '../app/models.dart';
import '../widgets/app_segmented_control.dart';
import 'home_shell.dart';
import 'video_frame_capture_page.dart';
import '../widgets/attachment_media.dart';
import '../widgets/attachment_picker_sheet.dart';
import '../widgets/video_frame_source_sheet.dart';

class CreatePage extends StatefulWidget {
  const CreatePage({super.key});

  @override
  State<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends State<CreatePage> {
  late final TextEditingController _promptController;
  late final TextEditingController _durationController;
  late final TextEditingController _seedController;
  bool _mentionSheetOpen = false;
  bool _updatingController = false;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController();
    _durationController = TextEditingController();
    _seedController = TextEditingController();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _durationController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    _syncPrompt(state);
    _syncMetadataControllers(state);
    _handleMentionSheet(context, state);
   _ensureToolResolution(state);

   final canSubmit =
       state.isAgentEarthConfigured &&
       state.validationMessages.isEmpty &&
       !state.isSubmitting;
   final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return AppPageScaffold(
      eyebrow: 'Create',
      title: '创作',
      subtitle: '提示词、素材和参数。',
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 112),
            children: [
              SectionLabel('模式'),
              UtilityPanel(
                child: _ModeSelector(
                  modes: modes,
                  selectedMode: state.activeMode,
                  onChanged: state.setActiveMode,
                ),
              ),
              const SizedBox(height: 16),
              SectionLabel('描述'),
              UtilityPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeaderActionRow(
                      title: state.activeMode == ModeId.text
                          ? 'Prompt'
                          : state.supportsPromptMentions
                          ? '参考素材与 Prompt'
                          : '画面与动作描述',
                      actionLabel: state.prompt.isEmpty ? null : '清空',
                      onTap: state.prompt.isEmpty
                          ? null
                          : () {
                              _clearPrompt(context, state);
                            },
                    ),
                    if (state.usesFrameSlots)
                      _VideoFrameSlots(
                        state: state,
                        onPreview: (attachment) =>
                            _openAttachmentPreview(context, attachment),
                        onPickFirstFrame: () => _openVideoFramePicker(
                          context,
                          state,
                          role: AttachmentRole.firstFrame,
                        ),
                        onPickLastFrame: state.activeMode == ModeId.firstLast
                            ? () => _openVideoFramePicker(
                                context,
                                state,
                                role: AttachmentRole.lastFrame,
                              )
                            : null,
                        onCaptureFirstFrame: () => _openFrameCaptureFlow(
                          context,
                          state,
                          role: AttachmentRole.firstFrame,
                        ),
                        onCaptureLastFrame: state.activeMode == ModeId.firstLast
                            ? () => _openFrameCaptureFlow(
                                context,
                                state,
                                role: AttachmentRole.lastFrame,
                              )
                            : null,
                      )
                    else if (state.selectedAttachments.isNotEmpty)
                      _SelectedAttachmentStrip(
                        attachments: state.selectedAttachments,
                        onPreview: (attachment) =>
                            _openAttachmentPreview(context, attachment),
                        onReplace: (attachment) =>
                            _openReplacementSheet(context, state, attachment),
                      )
                    else
                      Text(
                        state.activeMode == ModeId.text
                            ? '描述镜头、动作和氛围。'
                            : '参考模式下可以在 Prompt 里输入 @ 插入素材标签。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: EdgeInsets.only(bottom: keyboardOpen ? 56 : 0),
                      child: Stack(
                        children: [
                          TextField(
                            controller: _promptController,
                            minLines: 6,
                            maxLines: 9,
                            onChanged: (value) {
                              _applyPromptChange(state, value);
                            },
                            onTap: () => _inspectMention(state),
                            decoration: InputDecoration(
                              hintText: state.activeMode == ModeId.text
                                  ? '描述镜头、动作和氛围。'
                                  : state.supportsPromptMentions
                                  ? '描述镜头、动作和氛围，也可以输入 @ 插入素材标签。'
                                  : '描述从首帧到尾帧之间的动作、镜头和氛围。',
                              counterText: '',
                            ),
                          ),
                          Positioned(
                            right: 12,
                            bottom: 8,
                            child: Text(
                              '${state.prompt.length}/5000',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: state.prompt.length > 5000
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (state.supportsPromptMentions) ...[
                      const SizedBox(height: 14),
                      UtilityTile(
                        title: '素材引用',
                        subtitle: '在光标处插入素材占位。',
                        trailing: ToolIconButton(
                          tooltip: '浏览素材',
                          icon: Icons.alternate_email_rounded,
                          onPressed: state.uploadedLibrary.isEmpty
                              ? null
                              : () => _openMentionSheet(context, state),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionLabel('参数'),
              UtilityPanel(
                child: Column(
                  children: [
                    _ValueRow(
                      label: '时长',
                      child: SizedBox(
                        width: 86,
                        child: _DurationStepperField(
                          controller: _durationController,
                          value: state.metadata.duration,
                          onChanged: (value) => state.updateMetadata(
                            (current) => current.copyWith(duration: value),
                          ),
                        ),
                      ),
                    ),
                    const PanelDivider(),
                    _ValueRow(
                      label: '分辨率',
                      child: SizedBox(
                        width: 120,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            alignment: Alignment.centerRight,
                            value: state.metadata.resolution,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            items: const [
                              DropdownMenuItem(
                                value: '480p',
                                child: Text('480p'),
                              ),
                              DropdownMenuItem(
                                value: '720p',
                                child: Text('720p'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              state.updateMetadata(
                                (current) =>
                                    current.copyWith(resolution: value),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const PanelDivider(),
                    _ValueRow(
                      label: '比例',
                      child: SizedBox(
                        width: 120,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            alignment: Alignment.centerRight,
                            value: state.metadata.ratio,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            items: const [
                              DropdownMenuItem(
                                value: '16:9',
                                child: Text('16:9'),
                              ),
                              DropdownMenuItem(
                                value: '9:16',
                                child: Text('9:16'),
                              ),
                              DropdownMenuItem(
                                value: '1:1',
                                child: Text('1:1'),
                              ),
                              DropdownMenuItem(
                                value: '4:3',
                                child: Text('4:3'),
                              ),
                              DropdownMenuItem(
                                value: 'adaptive',
                                child: Text('adaptive'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              state.updateMetadata(
                                (current) => current.copyWith(ratio: value),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const PanelDivider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('生成音频'),
                      subtitle: Text(
                        fieldHelp['generateAudio']!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      value: state.metadata.generateAudio,
                      onChanged: (value) => state.updateMetadata(
                        (current) => current.copyWith(generateAudio: value),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionLabel('高级与预览'),
              _PreviewDisclosureCard(
                title: 'Seed',
                subtitle: state.metadata.seed.trim().isEmpty
                    ? '默认留空，由上游随机生成。'
                    : '当前使用固定 Seed：${state.metadata.seed}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: TextField(
                        controller: _seedController,
                        textAlign: TextAlign.left,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '留空',
                        ),
                        onChanged: (value) => state.updateMetadata(
                          (current) => current.copyWith(seed: value),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '只有需要复现相近结果或做多轮微调时再填写。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _PreviewDisclosureCard(
                title: '请求预览',
                subtitle: '提交前查看将发送给 AgentEarth 的工具和参数。',
                child: _RequestPreviewCard(state: state),
              ),
              if (state.validationMessages.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionLabel('提示'),
                UtilityPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: state.validationMessages
                        .map(
                          (message) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              message,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              if (state.submitErrorMessage != null) ...[
                const SizedBox(height: 16),
                SectionLabel('提交失败'),
                UtilityPanel(
                  child: UtilityTile(
                    title: state.submitErrorMessage!,
                    subtitle: '任务没有被创建，也不会产生扣费执行记录。',
                    trailing: Icon(
                      Icons.error_outline_rounded,
                      color: Theme.of(context).colorScheme.error,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Positioned(
            right: 20,
            bottom: keyboardOpen
                ? MediaQuery.of(context).viewInsets.bottom + 12
                : 16,
            child: FloatingSubmitBar(
              resolution: state.activeToolResolution,
              label: '提交',
              submitting: state.isSubmitting,
              onPressed: canSubmit ? () => _submitTask(context, state) : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitTask(BuildContext context, AppState state) async {
    if (!state.isAgentEarthConfigured || state.validationMessages.isNotEmpty) {
      final submitted = await state.submitTask();
      if (submitted || !context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(state.submitErrorMessage ?? '提交失败')),
        );
      return;
    }

    final confirmed = await confirmAction(
      context,
      title: '提交生成任务？',
      message: '确认后会按当前参数创建视频生成任务，并可能消耗所选工具积分。提交后可在任务页查看进度。',
      confirmLabel: '确认提交',
    );
    if (!confirmed || !context.mounted) return;

    final submitted = await state.submitTask();
    if (submitted) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('任务已提交')));
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(state.submitErrorMessage ?? '提交失败')),
      );
  }

  void _ensureToolResolution(AppState state) {
    if (!state.isAgentEarthConfigured) return;
    if (state.activeToolResolution.status != ToolResolutionStatus.idle) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      state.resolveActiveTool();
    });
  }

  Future<void> _clearPrompt(BuildContext context, AppState state) async {
    final confirmed = await confirmAction(
      context,
      title: '清空内容？',
      message: '当前提示词和素材占位会被清空。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!confirmed) return;
    state.clearPrompt();
    _promptController.clear();
  }

  void _syncPrompt(AppState state) {
    if (_promptController.text == state.prompt) {
      return;
    }
    _updatingController = true;
    _promptController.value = TextEditingValue(
      text: state.prompt,
      selection: TextSelection.collapsed(offset: state.prompt.length),
    );
    _updatingController = false;
  }

  // 时长 / Seed 是简单文本字段：当外部 state 与 controller 文本不一致时
  // 同步一次（例如 copyTaskToCreate 复用了任务参数）。仅在文本不同时改写，
  // 避免用户正在输入时把光标重置到末尾。
  void _syncMetadataControllers(AppState state) {
    final duration = state.metadata.duration;
    if (_durationController.text != duration) {
      _durationController.value = TextEditingValue(
        text: duration,
        selection: TextSelection.collapsed(offset: duration.length),
      );
    }
    final seed = state.metadata.seed;
    if (_seedController.text != seed) {
      _seedController.value = TextEditingValue(
        text: seed,
        selection: TextSelection.collapsed(offset: seed.length),
      );
    }
  }

  void _inspectMention(AppState state) {
    final selection = _promptController.selection;
    final cursor = selection.baseOffset < 0
        ? _promptController.text.length
        : selection.baseOffset;
    state.inspectMention(_promptController.text, cursor);
  }

  void _applyPromptChange(AppState state, String nextText) {
    if (_updatingController) {
      return;
    }

    final previous = state.prompt;
    final selection = _promptController.selection;
    final cursor = selection.baseOffset < 0
        ? nextText.length
        : selection.baseOffset;
    final result = _normalizePromptEdit(previous, nextText, cursor);

    if (result.text != nextText || result.cursor != cursor) {
      _updatingController = true;
      _promptController.value = TextEditingValue(
        text: result.text,
        selection: TextSelection.collapsed(
          offset: result.cursor.clamp(0, result.text.length),
        ),
      );
      _updatingController = false;
    }

    state.updatePrompt(result.text);

    final insertedChar = result.insertedChar;
    if (state.supportsPromptMentions &&
        (insertedChar == '@' || state.mentionOpen)) {
      _inspectMention(state);
    } else if (result.text.length < previous.length) {
      state.closeMention();
    }
  }

  _PromptEditResult _normalizePromptEdit(
    String previous,
    String next,
    int cursor,
  ) {
    if (previous == next) {
      return _PromptEditResult(text: next, cursor: cursor);
    }

    final diffStart = _firstDiff(previous, next);
    final oldDiffEnd = _oldDiffEnd(previous, next, diffStart);
    var normalized = next;
    var normalizedCursor = cursor;
    var removedToken = false;

    for (final match in AppState.promptTokenPattern.allMatches(previous)) {
      if (match.start < oldDiffEnd && match.end > diffStart) {
        normalized = previous.replaceRange(match.start, match.end, '');
        normalizedCursor = match.start;
        removedToken = true;
        break;
      }
      if (!next.contains(match.group(0)!)) {
        final token = match.group(0)!;
        if (next.contains(token.replaceAll(RegExp(r'[@{}]'), ''))) {
          normalized = previous.replaceRange(match.start, match.end, '');
          normalizedCursor = match.start;
          removedToken = true;
          break;
        }
      }
    }

    final insertedChar =
        !removedToken &&
            next.length > previous.length &&
            diffStart < next.length
        ? next[diffStart]
        : null;

    return _PromptEditResult(
      text: normalized,
      cursor: normalizedCursor,
      insertedChar: insertedChar,
    );
  }

  int _firstDiff(String a, String b) {
    final min = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < min; i++) {
      if (a[i] != b[i]) return i;
    }
    return min;
  }

  int _oldDiffEnd(String oldText, String newText, int start) {
    var oldIndex = oldText.length - 1;
    var newIndex = newText.length - 1;
    while (oldIndex >= start &&
        newIndex >= start &&
        oldText[oldIndex] == newText[newIndex]) {
      oldIndex--;
      newIndex--;
    }
    return oldIndex + 1;
  }

  void _handleMentionSheet(BuildContext context, AppState state) {
    if (state.mentionOpen && !_mentionSheetOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openMentionSheet(context, state);
      });
    }
  }

  Future<void> _openMentionSheet(BuildContext context, AppState state) async {
    if (_mentionSheetOpen) return;
    _mentionSheetOpen = true;
    final picked = await showAttachmentPickerSheet(
      context: context,
      state: state,
      title: '选择素材',
      subtitle: '选择后会在光标处插入素材占位。',
      initialQuery: state.mentionQuery,
      initialCategory: state.mentionCategoryFilter,
    );
    if (picked != null) {
      final selection = _promptController.selection;
      final cursor = selection.baseOffset < 0
          ? _promptController.text.length
          : selection.baseOffset;
      state.selectMentionAttachment(picked.id, fallbackCursor: cursor);
      _syncPrompt(state);
    }

    _mentionSheetOpen = false;
    if (mounted) {
      state.closeMention();
    }
  }

  Future<void> _openVideoFramePicker(
    BuildContext context,
    AppState state, {
    required AttachmentRole role,
  }) async {
    final currentAttachment = role == AttachmentRole.firstFrame
        ? state.selectedFirstFrameAttachment
        : state.selectedLastFrameAttachment;
    final picked = await showAttachmentPickerSheet(
      context: context,
      state: state,
      title: role == AttachmentRole.firstFrame ? '选择首帧素材' : '选择尾帧素材',
      subtitle: role == AttachmentRole.firstFrame
          ? '这张图会作为视频起始画面。'
          : '这张图会作为视频收尾画面。',
      kind: AttachmentKind.image,
      excludeAttachmentId: currentAttachment?.id,
    );
    if (picked == null) return;
    state.selectVideoFrameAttachment(picked.id, role: role);
  }

  Future<void> _openFrameCaptureFlow(
    BuildContext context,
    AppState state, {
    required AttachmentRole role,
  }) async {
    final source = await showVideoSourceSheet(
      context: context,
      state: state,
      title: role == AttachmentRole.firstFrame ? '选择首帧视频来源' : '选择尾帧视频来源',
      subtitle: '可以从本地视频、云端素材或任务结果里截取画面。',
    );
    if (source == null || !context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VideoFrameCapturePage(
          source: source,
          entryContext: role == AttachmentRole.firstFrame
              ? VideoFrameEntryContext.createFirstFrame
              : VideoFrameEntryContext.createLastFrame,
        ),
      ),
    );
  }

  Future<void> _openReplacementSheet(
    BuildContext context,
    AppState state,
    Attachment currentAttachment,
  ) async {
    final compatible = state.uploadedLibrary.where((item) {
      if (item.id == currentAttachment.id) return false;
      if (item.kind != currentAttachment.kind) return false;
      return true;
    }).toList();

    if (compatible.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('没有可替换的同类型素材')));
      return;
    }
    final picked = await showAttachmentPickerSheet(
      context: context,
      state: state,
      title: '替换素材',
      subtitle: '保持当前位置不变，直接替换成另一个素材。',
      kind: currentAttachment.kind,
      excludeAttachmentId: currentAttachment.id,
    );
    if (picked == null) return;
    state.replaceSelectedAttachment(
      currentAttachmentId: currentAttachment.id,
      nextAttachmentId: picked.id,
    );
    _syncPrompt(state);
  }

  Future<void> _openAttachmentPreview(
    BuildContext context,
    Attachment attachment,
  ) async {
    await showAttachmentPreviewSheet(context, attachment);
  }
}

class _RequestPreviewCard extends StatelessWidget {
  const _RequestPreviewCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final resolution = state.activeToolResolution;
    return FutureBuilder<SeedanceRequestPreview>(
      future: state.resolveRequestPreview(),
      builder: (context, snapshot) {
        final preview = snapshot.data ?? state.requestPreview;
        final subtitle = switch (resolution.status) {
          ToolResolutionStatus.ready =>
            '使用 AgentEarth 推荐工具：${preview.toolName}',
          ToolResolutionStatus.loading =>
            '正在获取 AgentEarth 推荐工具，预览暂用固定 Seedance2 工具。',
          ToolResolutionStatus.error =>
            resolution.errorMessage ?? '推荐工具获取失败，已阻止直接扣费执行。',
          _ =>
            state.isAgentEarthConfigured
                ? '等待获取 AgentEarth 推荐工具。'
                : '填写 AgentEarth API Key 后会获取工具和积分。',
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UtilityTile(
              title: preview.toolName,
              subtitle: subtitle,
              trailing: Icon(
                resolution.status == ToolResolutionStatus.ready
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
                size: 18,
              ),
            ),
            const PanelDivider(),
            const SizedBox(height: 12),
            SelectableText(
              preview.prettyJson,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PreviewDisclosureCard extends StatefulWidget {
  const _PreviewDisclosureCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  State<_PreviewDisclosureCard> createState() => _PreviewDisclosureCardState();
}

class _PreviewDisclosureCardState extends State<_PreviewDisclosureCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return UtilityPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more_rounded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: widget.child,
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _PromptEditResult {
  const _PromptEditResult({
    required this.text,
    required this.cursor,
    this.insertedChar,
  });

  final String text;
  final int cursor;
  final String? insertedChar;
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.modes,
    required this.selectedMode,
    required this.onChanged,
  });

  final List<ModeOption> modes;
  final ModeId selectedMode;
  final ValueChanged<ModeId> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = modes.firstWhere((mode) => mode.id == selectedMode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSegmentedControl<ModeId>(
          segments: modes
              .map(
                (mode) => AppSegment<ModeId>(
                  value: mode.id,
                  label: _tabLabelForMode(mode.id),
                ),
              )
              .toList(),
          selected: selectedMode,
          onChanged: onChanged,
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Container(
            key: ValueKey(selected.id),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.52),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  selected.hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _modeSupportText(selected.id),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
                    height: 1.22,
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

String _tabLabelForMode(ModeId mode) => switch (mode) {
  ModeId.text => '文本',
  ModeId.firstFrame => '首帧',
  ModeId.firstLast => '首尾帧',
  ModeId.reference => '参考',
};

String _modeSupportText(ModeId mode) => switch (mode) {
  ModeId.text => '只靠 Prompt 出片，适合快速试创意和镜头方向。',
  ModeId.firstFrame => '首帧固定为起始画面，适合从静态图自然起镜。',
  ModeId.firstLast => '同时约束起始和结束构图，更适合需要控结尾的镜头。',
  ModeId.reference => '可结合图、视频、音频作为参考，让生成方向更稳定。',
};

class _HeaderActionRow extends StatelessWidget {
  const _HeaderActionRow({required this.title, this.actionLabel, this.onTap});

  final String title;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (actionLabel != null)
            Tooltip(
              message: actionLabel!,
              child: IconButton(
                onPressed: onTap,
                icon: const Icon(Icons.clear_rounded, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectedAttachmentStrip extends StatelessWidget {
  const _SelectedAttachmentStrip({
    required this.attachments,
    required this.onPreview,
    required this.onReplace,
  });

  final List<Attachment> attachments;
  final ValueChanged<Attachment> onPreview;
  final ValueChanged<Attachment> onReplace;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('已插入素材', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 10),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: attachments.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final attachment = attachments[index];
              return _SelectedAttachmentCard(
                attachment: attachment,
                onPreview: () => onPreview(attachment),
                onReplace: () => onReplace(attachment),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _VideoFrameSlots extends StatelessWidget {
  const _VideoFrameSlots({
    required this.state,
    required this.onPreview,
    required this.onPickFirstFrame,
    this.onPickLastFrame,
    required this.onCaptureFirstFrame,
    this.onCaptureLastFrame,
  });

  final AppState state;
  final ValueChanged<Attachment> onPreview;
  final VoidCallback onPickFirstFrame;
  final VoidCallback? onPickLastFrame;
  final VoidCallback onCaptureFirstFrame;
  final VoidCallback? onCaptureLastFrame;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final children = <Widget>[
      _VideoFrameSlotCard(
        title: '首帧素材',
        subtitle: '决定视频从哪一帧开始。',
        attachment: state.selectedFirstFrameAttachment,
        accentColor: colorScheme.primary,
        pickLabel: '选择首帧',
        onPick: onPickFirstFrame,
        onCapture: onCaptureFirstFrame,
        onPreview: state.selectedFirstFrameAttachment == null
            ? null
            : () => onPreview(state.selectedFirstFrameAttachment!),
        onClear: state.selectedFirstFrameAttachment == null
            ? null
            : () => state.clearVideoFrameAttachment(AttachmentRole.firstFrame),
      ),
    ];

    if (state.activeMode == ModeId.firstLast) {
      children.add(
        _VideoFrameSlotCard(
          title: '尾帧素材',
          subtitle: '决定视频收束到哪一帧。',
          attachment: state.selectedLastFrameAttachment,
          accentColor: colorScheme.tertiary,
          pickLabel: '选择尾帧',
          onPick: onPickLastFrame,
          onCapture: onCaptureLastFrame,
          onPreview: state.selectedLastFrameAttachment == null
              ? null
              : () => onPreview(state.selectedLastFrameAttachment!),
          onClear: state.selectedLastFrameAttachment == null
              ? null
              : () => state.clearVideoFrameAttachment(AttachmentRole.lastFrame),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('画面槽位', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 10),
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const SizedBox(height: 12),
        ],
        const SizedBox(height: 10),
        Text(
          state.activeMode == ModeId.firstFrame
              ? '首帧模式里，图片只负责定义起始画面；Prompt 只写动作和镜头，不再通过插入位置表达时序。'
              : '首尾帧模式里，首帧和尾帧会分别映射到 `image_url` 和 `end_image_url`。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _VideoFrameSlotCard extends StatelessWidget {
  const _VideoFrameSlotCard({
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.pickLabel,
    required this.onPick,
    required this.onCapture,
    this.attachment,
    this.onPreview,
    this.onClear,
  });

  final String title;
  final String subtitle;
  final Color accentColor;
  final String pickLabel;
  final VoidCallback? onPick;
  final VoidCallback? onCapture;
  final Attachment? attachment;
  final VoidCallback? onPreview;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasAttachment = attachment != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: hasAttachment
              ? accentColor.withValues(alpha: 0.22)
              : colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '已选择',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (hasAttachment)
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: onPreview,
              child: Ink(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    AttachmentThumb(
                      attachment: attachment!,
                      width: 112,
                      height: 76,
                      radius: 16,
                      overlayLabel: attachment!.label,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            attachment!.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${displayCategoryLabel(attachment!.category)} · ${compactFileName(attachment!.fileName)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '点开预览或继续更换来源',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: accentColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              '可以直接选择已有图片，或者先从本地/云端视频里截一帧作为起始画面。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(hasAttachment ? '更换素材' : pickLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onCapture,
                icon: const Icon(Icons.movie_creation_outlined, size: 18),
                label: const Text('从视频截帧'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  side: BorderSide(color: accentColor.withValues(alpha: 0.28)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
              ),
              if (onClear != null)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('清空'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectedAttachmentCard extends StatelessWidget {
  const _SelectedAttachmentCard({
    required this.attachment,
    required this.onPreview,
    required this.onReplace,
  });

  final Attachment attachment;
  final VoidCallback onPreview;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onPreview,
        child: Ink(
          width: 112,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _AttachmentThumb(
                    attachment: attachment,
                    width: 96,
                    height: 64,
                    radius: 18,
                    overlayLabel: attachment.label,
                  ),
                  Positioned(
                    right: -2,
                    top: -2,
                    child: GestureDetector(
                      onTap: onReplace,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 10,
                              color: colorScheme.shadow,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.swap_horiz_rounded,
                          size: 16,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({
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
    return AttachmentThumb(
      attachment: attachment,
      width: width,
      height: height,
      radius: radius,
      overlayLabel: overlayLabel,
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

class _DurationStepperField extends StatelessWidget {
  const _DurationStepperField({
    required this.controller,
    required this.value,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String value;
  final ValueChanged<String> onChanged;

  int? get _seconds => int.tryParse(value.trim());

  void _step(int delta) {
    final current = _seconds ?? AppState.minSeedanceDurationSeconds;
    final next = (current + delta).clamp(
      AppState.minSeedanceDurationSeconds,
      AppState.maxSeedanceDurationSeconds,
    );
    onChanged(next.toString());
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _seconds;
    final canDecrease =
        seconds == null || seconds > AppState.minSeedanceDurationSeconds;
    final canIncrease =
        seconds == null || seconds < AppState.maxSeedanceDurationSeconds;

    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _DurationStepChevron(
                    icon: Icons.keyboard_arrow_up_rounded,
                    tooltip: '增加 1 秒',
                    onPressed: canIncrease ? () => _step(1) : null,
                  ),
                  _DurationStepChevron(
                    icon: Icons.keyboard_arrow_down_rounded,
                    tooltip: '减少 1 秒',
                    onPressed: canDecrease ? () => _step(-1) : null,
                  ),
                ],
              ),
            ),
          ],
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 28,
          minHeight: 40,
        ),
      ),
      onChanged: onChanged,
    );
  }
}

class _DurationStepChevron extends StatelessWidget {
  const _DurationStepChevron({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        child: InkResponse(
          onTap: onPressed,
          radius: 13,
          containedInkWell: true,
          child: SizedBox(
            width: 22,
            height: 18,
            child: Icon(
              icon,
              size: 18,
              color: enabled
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.34),
            ),
          ),
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(width: 16),
          Align(alignment: Alignment.centerRight, child: child),
        ],
      ),
    );
  }
}
