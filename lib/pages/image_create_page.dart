import 'package:flutter/material.dart';
import '../widgets/app_segmented_control.dart';
import '../app/spacing.dart';

import '../app/app_scope.dart';
import '../app/app_state.dart';
import '../app/models.dart';
import '../widgets/attachment_media.dart';
import '../widgets/attachment_picker_sheet.dart';
import 'home_shell.dart';

class ImageCreatePage extends StatefulWidget {
  const ImageCreatePage({super.key});

  @override
  State<ImageCreatePage> createState() => _ImageCreatePageState();
}

class _ImageCreatePageState extends State<ImageCreatePage> {
  late final TextEditingController _promptController;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    _syncPrompt(state);
    _ensureImageToolResolution(state);

    final theme = Theme.of(context);
    final isEditMode = state.activeImageMode == ImageCreateMode.imageToImage;
    final hasPrompt = state.imagePrompt.trim().isNotEmpty;
    final hasRequiredReferences =
        !isEditMode || state.selectedImageAttachments.isNotEmpty;
    final canSubmit =
        hasPrompt && hasRequiredReferences && !state.isSubmittingImageTask;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: AppPageScaffold(
          eyebrow: 'Create',
          title: '图片创作',
          subtitle: isEditMode ? '用参考图继续改图并自动入库。' : '生成图片并自动入库到素材库。',
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 112),
                children: [
                  SectionLabel('模式'),
                  UtilityPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ImageModeSelector(state: state),
                        const SizedBox(height: 12),
                        Text(
                          isEditMode
                              ? '上传或选择参考图，再用提示词描述你希望怎么改。'
                              : '使用文字描述直接生成图片。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (isEditMode) ...[
                    const SizedBox(height: 16),
                    SectionLabel('参考图'),
                    UtilityPanel(
                      child: _ImageReferenceSection(
                        state: state,
                        onAdd: () => _openReferencePicker(context, state),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SectionLabel('描述'),
                  UtilityPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ImagePromptHeader(
                          actionLabel: state.imagePrompt.isEmpty ? null : '清空',
                          onTap: state.imagePrompt.isEmpty
                              ? null
                              : () => _clearImagePrompt(context, state),
                        ),
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: keyboardOpen ? 56 : 0,
                          ),
                          child: Stack(
                            children: [
                              TextField(
                                controller: _promptController,
                                minLines: 4,
                                maxLines: 7,
                                onChanged: state.updateImagePrompt,
                                decoration: InputDecoration(
                                  hintText: isEditMode
                                      ? '描述你要如何修改参考图，比如替换背景、改服装、变风格。'
                                      : '描述主体、风格、镜头、构图、光线、材质和氛围。',
                                  counterText: '',
                                ),
                              ),
                              Positioned(
                                right: 12,
                                bottom: 8,
                                child: Text(
                                  '${state.imagePrompt.length}/2000',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: state.imagePrompt.length > 2000
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                   ),
                  ),
                  const SizedBox(height: 16),
                  SectionLabel('参数'),
                  UtilityPanel(
                    child: Column(
                      children: [
                        _DropdownRow<String>(
                          label: '比例',
                          value: state.imageMetadata.aspectRatio,
                          items: const ['1:1', '4:3', '16:9', '9:16'],
                          onChanged: (v) {
                            state.updateImageMetadata(
                              (current) => current.copyWith(aspectRatio: v),
                            );
                          },
                        ),
                        const PanelDivider(),
                        _DropdownRow<String>(
                          label: '质量',
                          value: state.imageMetadata.quality,
                          items: const ['low', 'medium', 'high'],
                          onChanged: (v) {
                            state.updateImageMetadata(
                              (current) => current.copyWith(quality: v),
                            );
                          },
                        ),
                        const PanelDivider(),
                        _DropdownRow<String>(
                          label: '张数',
                          value: '${state.imageMetadata.numImages}',
                          items: const ['1', '2', '3', '4'],
                          onChanged: (v) {
                            state.updateImageMetadata(
                              (current) => current.copyWith(
                                numImages: int.tryParse(v) ?? 1,
                              ),
                            );
                          },
                        ),
                        const PanelDivider(),
                        _DropdownRow<String>(
                          label: '输出格式',
                          value: state.imageMetadata.outputFormat,
                          items: const ['png', 'jpeg', 'webp'],
                          onChanged: (v) {
                            state.updateImageMetadata(
                              (current) => current.copyWith(outputFormat: v),
                            );
                          },
                        ),
                        const PanelDivider(),
                        _DropdownRow<String>(
                          label: '分类',
                          value: state.imageMetadata.category,
                          items: ['', ...state.categories],
                          displayItems: ['(默认)', ...state.categories],
                          onChanged: (v) {
                            state.updateImageMetadata(
                              (current) => current.copyWith(category: v),
                            );
                          },
                        ),
                        const PanelDivider(),
                        _DropdownRow<AttachmentRole>(
                          label: '入库角色',
                          value: state.imageMetadata.role,
                          items: const [
                            AttachmentRole.referenceImage,
                            AttachmentRole.firstFrame,
                            AttachmentRole.lastFrame,
                          ],
                          displayItems: const ['参考图', '首帧图', '尾帧图'],
                          onChanged: (v) {
                            state.updateImageMetadata(
                              (current) => current.copyWith(role: v),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionLabel('高级与预览'),
                  _ImagePreviewDisclosureCard(
                    title: '请求预览',
                    subtitle: '提交前查看当前会调用的图片工具和参数。',
                    child: _ImageRequestPreviewCard(state: state),
                  ),
                  if (state.imageSubmitErrorMessage != null) ...[
                    const SizedBox(height: 16),
                    SectionLabel('提交失败'),
                    UtilityPanel(
                      child: UtilityTile(
                        title: state.imageSubmitErrorMessage!,
                        subtitle: '任务没有被创建，也不会产生扣费执行记录。',
                        trailing: Icon(
                          Icons.error_outline_rounded,
                          color: theme.colorScheme.error,
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
                    resolution: state.imageToolResolution,
                    label: '提交',
                    submitting: state.isSubmittingImageTask,
                    onPressed: canSubmit
                        ? () => _submitImageTask(context, state)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _syncPrompt(AppState state) {
    if (_promptController.text != state.imagePrompt) {
      _promptController.value = TextEditingValue(
        text: state.imagePrompt,
        selection: TextSelection.collapsed(offset: state.imagePrompt.length),
      );
    }
  }

  Future<void> _clearImagePrompt(BuildContext context, AppState state) async {
    final confirmed = await confirmAction(
      context,
      title: '清空内容？',
      message: '当前图片提示词会被清空。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!confirmed) return;
    state.updateImagePrompt('');
    _promptController.clear();
  }

  Future<void> _submitImageTask(BuildContext context, AppState state) async {
    final confirmed = await confirmAction(
      context,
      title: '提交图片任务？',
      message: '确认后会按当前参考图、提示词和参数创建图片生成任务，并可能消耗所选工具积分。',
      confirmLabel: '确认提交',
    );
    if (!confirmed || !context.mounted) return;

    final submitted = await state.submitImageTask();
    if (!context.mounted) return;

    if (submitted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('图片任务已提交')));
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      }
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(state.imageSubmitErrorMessage ?? '提交失败')),
        );
    }
  }

  Future<void> _openReferencePicker(
    BuildContext context,
    AppState state,
  ) async {
    final picked = await showAttachmentPickerSheet(
      context: context,
      state: state,
      title: '选择参考图',
      subtitle: '图生图会把这些图片作为编辑输入传给 AgentEarth。',
      kind: AttachmentKind.image,
    );
    if (picked == null) return;
    state.addImageReferenceAttachment(picked.id);
  }

  void _ensureImageToolResolution(AppState state) {
    if (!state.isAgentEarthConfigured) return;
    if (state.imageToolResolution.status != ToolResolutionStatus.idle) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      state.resolveImageTool();
    });
  }
}

class _ImageModeSelector extends StatelessWidget {
  const _ImageModeSelector({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppSegmentedControl<ImageCreateMode>(
      segments: const [
        AppSegment(
          value: ImageCreateMode.textToImage,
          icon: Icons.auto_awesome_outlined,
          label: '文生图',
        ),
        AppSegment(
          value: ImageCreateMode.imageToImage,
          icon: Icons.draw_outlined,
          label: '图生图',
        ),
      ],
      selected: state.activeImageMode,
      onChanged: state.setActiveImageMode,
    );
  }
}

class _ImagePromptHeader extends StatelessWidget {
  const _ImagePromptHeader({this.actionLabel, this.onTap});

  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Prompt',
              style: Theme.of(context).textTheme.titleMedium,
            ),
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

class _ImageReferenceSection extends StatelessWidget {
  const _ImageReferenceSection({required this.state, required this.onAdd});

  final AppState state;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final attachments = state.selectedImageAttachments;
    final hasPrompt = state.imagePrompt.trim().isNotEmpty;
    final hasReference = attachments.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hasReference
                    ? colorScheme.primary.withValues(alpha: 0.10)
                    : colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasReference
                    ? Icons.check_rounded
                    : Icons.add_photo_alternate_outlined,
                size: 18,
                color: hasReference
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasReference ? '参考图已就绪' : '先放一张输入图',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasReference
                        ? '已选 ${attachments.length} 张，提交时按当前顺序作为编辑输入。'
                        : '选择参考图后，再用提示词描述你希望怎么改。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onAdd,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 38),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
              icon: Icon(
                hasReference ? Icons.add_rounded : Icons.image_outlined,
                size: 17,
              ),
              label: Text(hasReference ? '添加' : '选择'),
            ),
          ],
        ),
        if (attachments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '已选素材',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              _ReferenceFlowHint(
                hasReference: hasReference,
                hasPrompt: hasPrompt,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: attachments.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final attachment = attachments[index];
                return _ImageReferenceCard(
                  index: index,
                  attachment: attachment,
                  onRemove: () =>
                      state.removeImageReferenceAttachment(attachment.id),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _ImageReferenceCard extends StatelessWidget {
  const _ImageReferenceCard({
    required this.index,
    required this.attachment,
    required this.onRemove,
  });

  final int index;
  final Attachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 112,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.72),
                  ),
                ),
                child: AttachmentThumb(
                  attachment: attachment,
                  width: 104,
                  height: 70,
                  radius: 12,
                  overlayLabel: attachment.label,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '图 ${index + 1}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Positioned(
            right: -5,
            top: -5,
            child: Material(
              color: colorScheme.surface,
              elevation: 1,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(5),
                  child: Icon(Icons.close_rounded, size: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceFlowHint extends StatelessWidget {
  const _ReferenceFlowHint({
    required this.hasReference,
    required this.hasPrompt,
  });

  final bool hasReference;
  final bool hasPrompt;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ReferenceFlowStep(index: 1, label: '选图', active: hasReference),
        _FlowSeparator(active: hasReference),
        _ReferenceFlowStep(index: 2, label: '提示词', active: hasPrompt),
        _FlowSeparator(active: hasReference && hasPrompt),
        _ReferenceFlowStep(
          index: 3,
          label: '提交',
          active: hasReference && hasPrompt,
        ),
      ],
    );
  }
}

class _ReferenceFlowStep extends StatelessWidget {
  const _ReferenceFlowStep({
    required this.index,
    required this.label,
    required this.active,
  });

  final int index;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = active ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? colorScheme.primary.withValues(alpha: 0.10)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _FlowSeparator extends StatelessWidget {
  const _FlowSeparator({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Icon(
      Icons.chevron_right_rounded,
      size: 14,
      color: active
          ? colorScheme.primary.withValues(alpha: 0.62)
          : colorScheme.onSurfaceVariant.withValues(alpha: 0.34),
    );
  }
}

class _ImageRequestPreviewCard extends StatelessWidget {
  const _ImageRequestPreviewCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final resolution = state.imageToolResolution;
    return FutureBuilder<SeedanceRequestPreview>(
      future: state.resolveImageRequestPreview(),
      builder: (context, snapshot) {
        final preview = snapshot.data ?? state.imageRequestPreview;
        final isEditMode =
            state.activeImageMode == ImageCreateMode.imageToImage;
        final subtitle = switch (resolution.status) {
          ToolResolutionStatus.ready =>
            '使用 AgentEarth 推荐工具：${preview.toolName}',
          ToolResolutionStatus.loading =>
            isEditMode
                ? '正在获取 AgentEarth 推荐工具，预览暂用固定 GPT Image 2 编辑工具。'
                : '正在获取 AgentEarth 推荐工具，预览暂用固定 GPT Image 2 工具。',
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

class _ImagePreviewDisclosureCard extends StatefulWidget {
  const _ImagePreviewDisclosureCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  State<_ImagePreviewDisclosureCard> createState() =>
      _ImagePreviewDisclosureCardState();
}

class _ImagePreviewDisclosureCardState
    extends State<_ImagePreviewDisclosureCard> {
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

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    this.displayItems,
    this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final List<String>? displayItems;
  final ValueChanged<T>? onChanged;

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
          SizedBox(
            width: 120,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                isExpanded: true,
                alignment: Alignment.centerRight,
                value: value,
                borderRadius: BorderRadius.circular(AppRadius.card),
                items: List.generate(items.length, (i) {
                  final label = displayItems != null
                      ? displayItems![i]
                      : items[i].toString();
                  return DropdownMenuItem(value: items[i], child: Text(label));
                }),
                onChanged: (v) {
                  if (v != null) onChanged?.call(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
