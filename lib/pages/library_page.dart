import 'package:flutter/material.dart';
import '../app/spacing.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../app/app_state.dart';
import '../app/mock_data.dart';
import '../app/models.dart';
import 'category_management_page.dart';
import 'home_shell.dart';
import 'image_create_page.dart';
import 'video_frame_capture_page.dart';
import '../widgets/attachment_media.dart';
import '../widgets/app_dropdown.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final Set<String> _selectedAttachmentIds = {};

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    final visibleAttachments = appState.visibleLibrary;
    final isCompactMode = appState.libraryViewMode == LibraryViewMode.compact;
    if (!isCompactMode && _selectedAttachmentIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_selectedAttachmentIds.clear);
      });
    }

    return AppPageScaffold(
      eyebrow: 'Library',
      title: '素材库',
      subtitle: '文件、分类和素材角色。',
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            sliver: SliverList.list(
              children: [
                const SectionLabel('搜索与筛选'),
                _LibraryFilterPanel(state: appState),
                const SizedBox(height: 16),
                const SectionLabel('快速操作'),
                UtilityPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          CapsuleButton(
                            label: '打开相册',
                            icon: Icons.photo_library_outlined,
                            emphasized: true,
                            onPressed: () => _pickFiles(context, appState),
                          ),
                          CapsuleButton(
                            label: 'AI 生图',
                            icon: Icons.auto_awesome_rounded,
                            emphasized: false,
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ImageCreatePage(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '共 ${appState.library.length} 个素材，当前命中 ${visibleAttachments.length} 个。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SectionLabel('素材列表'),
                _LibraryViewToolbar(
                  mode: appState.libraryViewMode,
                  selectedCount: _selectedAttachmentIds.length,
                  visibleCount: visibleAttachments.length,
                  onModeChanged: (mode) {
                    appState.setLibraryViewMode(mode);
                    if (mode != LibraryViewMode.compact) {
                      setState(_selectedAttachmentIds.clear);
                    }
                  },
                  onSelectAll: isCompactMode
                      ? () {
                          setState(() {
                            final visibleIds = visibleAttachments
                                .map((item) => item.id)
                                .toSet();
                            if (_selectedAttachmentIds.length ==
                                visibleIds.length) {
                              _selectedAttachmentIds.clear();
                            } else {
                              _selectedAttachmentIds
                                ..clear()
                                ..addAll(visibleIds);
                            }
                          });
                        }
                      : null,
                  onDeleteSelected:
                      isCompactMode && _selectedAttachmentIds.isNotEmpty
                      ? () => _deleteSelectedAttachments(
                          context,
                          appState,
                          visibleAttachments,
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                if (appState.uploadErrorMessage != null) ...[
                  UtilityPanel(
                    child: Text(
                      appState.uploadErrorMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
          if (visibleAttachments.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverToBoxAdapter(
                child: _LibraryEmptyState(state: appState),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverList.separated(
                itemCount: visibleAttachments.length,
                itemBuilder: (context, index) {
                  final attachment = visibleAttachments[index];
                  if (isCompactMode) {
                    return _CompactAttachmentRow(
                      attachment: attachment,
                      previewAttachments: visibleAttachments,
                      selected: _selectedAttachmentIds.contains(attachment.id),
                      onSelectedChanged: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedAttachmentIds.add(attachment.id);
                          } else {
                            _selectedAttachmentIds.remove(attachment.id);
                          }
                        });
                      },
                    );
                  }
                  return _AttachmentCard(
                    attachment: attachment,
                    previewAttachments: visibleAttachments,
                  );
                },
                separatorBuilder: (_, _) =>
                    SizedBox(height: isCompactMode ? 8 : 16),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteSelectedAttachments(
    BuildContext context,
    AppState appState,
    List<Attachment> visibleAttachments,
  ) async {
    final selected = visibleAttachments
        .where((item) => _selectedAttachmentIds.contains(item.id))
        .toList();
    if (selected.isEmpty) return;
    final decision = await showModalBottomSheet<_DeleteAttachmentDecision>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _BatchDeleteAttachmentSheet(attachments: selected),
    );
    if (decision?.confirmed != true) return;
    final result = await appState.deleteAttachments(
      selected.map((item) => item.id),
      deleteRemote: decision!.deleteRemoteFile,
    );
    if (!context.mounted) return;
    setState(() {
      _selectedAttachmentIds.removeAll(selected.map((item) => item.id));
    });
    final failedCount = result.failures.length;
    final message = failedCount == 0
        ? '已删除 ${result.deletedCount} 个素材'
        : '已删除 ${result.deletedCount} 个素材，$failedCount 个失败';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LibraryFilterPanel extends StatefulWidget {
  const _LibraryFilterPanel({required this.state});

  final AppState state;

  @override
  State<_LibraryFilterPanel> createState() => _LibraryFilterPanelState();
}

class _LibraryFilterPanelState extends State<_LibraryFilterPanel> {
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return UtilityPanel(
      child: Column(
        children: [
          TextField(
            controller: TextEditingController(text: state.libraryQuery)
              ..selection = TextSelection.collapsed(
                offset: state.libraryQuery.length,
              ),
            onChanged: state.setLibraryQuery,
            decoration: const InputDecoration(
              hintText: '搜索素材名、文件名、分类',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),
          AppDropdownField<LibraryFilter>(
            value: state.libraryFilter,
            labelText: '素材类型',
            items: const [
              DropdownItemData(value: LibraryFilter.all, label: '全部'),
              DropdownItemData(value: LibraryFilter.image, label: '图片'),
              DropdownItemData(value: LibraryFilter.video, label: '视频'),
              DropdownItemData(value: LibraryFilter.audio, label: '音频'),
            ],
            onChanged: (value) {
              if (value != null) {
                state.setLibraryFilter(value);
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.hasActiveLibraryFilters
                          ? '已启用更多筛选'
                          : '更多筛选',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(width: 2),
                    AnimatedRotation(
                      turns: _showAdvanced ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.hasActiveLibraryFilters) ...[
                const Spacer(),
                TextButton(
                  onPressed: () {
                    state.clearLibraryFilters();
                    setState(() {
                      _showAdvanced = false;
                    });
                  },
                  child: const Text('清空'),
                ),
              ],
            ],
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '按分类筛选',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      ToolIconButton(
                        icon: Icons.tune_rounded,
                        tooltip: '管理分类',
                        onPressed: () => _openCategoryManagement(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text(uncategorizedCategoryLabel),
                        selected: state.selectedCategoryFilters.contains(
                          uncategorizedCategory,
                        ),
                        showCheckmark: false,
                        onSelected: (_) =>
                            state.toggleCategoryFilter(uncategorizedCategory),
                      ),
                      ...state.categories.map(
                        (category) => FilterChip(
                          label: Text(category),
                          selected: state.selectedCategoryFilters.contains(
                            category,
                          ),
                          showCheckmark: false,
                          onSelected: (_) =>
                              state.toggleCategoryFilter(category),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('最近使用排在前面'),
                    subtitle: Text(
                      state.libraryRecentFirst
                          ? '默认开启，便于反复复用素材'
                          : '已切换为按添加时间倒序',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    value: state.libraryRecentFirst,
                    onChanged: state.setLibraryRecentFirst,
                  ),
                ],
              ),
            ),
            crossFadeState: _showAdvanced
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _LibraryViewToolbar extends StatelessWidget {
  const _LibraryViewToolbar({
    required this.mode,
    required this.selectedCount,
    required this.visibleCount,
    required this.onModeChanged,
    required this.onSelectAll,
    required this.onDeleteSelected,
  });

  final LibraryViewMode mode;
  final int selectedCount;
  final int visibleCount;
  final ValueChanged<LibraryViewMode> onModeChanged;
  final VoidCallback? onSelectAll;
  final VoidCallback? onDeleteSelected;

  @override
  Widget build(BuildContext context) {
    return UtilityPanel(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<LibraryViewMode>(
            segments: const [
              ButtonSegment<LibraryViewMode>(
                value: LibraryViewMode.comfortable,
                icon: Icon(Icons.view_agenda_outlined, size: 18),
                label: Text('普通'),
              ),
              ButtonSegment<LibraryViewMode>(
                value: LibraryViewMode.compact,
                icon: Icon(Icons.format_list_bulleted_rounded, size: 18),
                label: Text('精简'),
              ),
            ],
            selected: {mode},
            emptySelectionAllowed: false,
            onSelectionChanged: (selected) => onModeChanged(selected.first),
          ),
          if (mode == LibraryViewMode.compact) ...[
            OutlinedButton.icon(
              onPressed: visibleCount == 0 ? null : onSelectAll,
              icon: const Icon(Icons.select_all_rounded, size: 18),
              label: Text(
                selectedCount == visibleCount && visibleCount > 0
                    ? '取消全选'
                    : '全选',
              ),
            ),
            FilledButton.icon(
              onPressed: onDeleteSelected,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(selectedCount == 0 ? '删除' : '删除 $selectedCount'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactAttachmentRow extends StatelessWidget {
  const _CompactAttachmentRow({
    required this.attachment,
    required this.previewAttachments,
    required this.selected,
    required this.onSelectedChanged,
  });

  final Attachment attachment;
  final List<Attachment> previewAttachments;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final canAccess = state.canAccessAttachment(attachment);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return UtilityPanel(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: (value) => onSelectedChanged(value ?? false),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: canAccess
                ? () => showAttachmentPreviewSheet(
                    context,
                    attachment,
                    attachments: previewAttachments,
                  )
                : null,
            child: _AttachmentThumbWithFileSize(
              attachment: attachment,
              width: 64,
              height: 64,
              radius: 10,
              overlayLabel: attachment.label,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      displayCategoryLabel(attachment.category),
                      style: theme.textTheme.labelSmall,
                    ),
                    Text(
                      state.storageProviderLabel(attachment.storageProvider),
                      style: theme.textTheme.labelSmall,
                    ),
                    Text(
                      _formatCompactDateTime(attachment.createdAt),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final hasFilters = state.hasActiveLibraryFilters;
    return UtilityPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasFilters ? '没有匹配结果' : '素材库还是空的',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            hasFilters ? '可以清空筛选，或者换个关键词继续找。' : '先上传几张图、视频或音频，后面创作时就能直接复用。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              CapsuleButton(
                label: hasFilters ? '清空筛选' : '打开相册',
                icon: hasFilters
                    ? Icons.filter_alt_off_rounded
                    : Icons.photo_library_outlined,
                emphasized: true,
                onPressed: hasFilters
                    ? state.clearLibraryFilters
                    : () => _pickFiles(context, state),
              ),
              if (!hasFilters)
                CapsuleButton(
                  label: '去图片创作',
                  icon: Icons.auto_awesome_rounded,
                  emphasized: false,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ImageCreatePage(),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _pickFiles(BuildContext context, AppState state) async {
  final uploaded = await state.pickAndUploadFiles();
  if (!context.mounted) return;
  final message = uploaded > 0
      ? '已上传 $uploaded 个素材，可在 Prompt 中 @ 引用'
      : state.uploadErrorMessage ?? '未选择素材';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _deleteAttachment(
  BuildContext context,
  AppState state,
  Attachment attachment,
) async {
  final decision = await showModalBottomSheet<_DeleteAttachmentDecision>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) => _DeleteAttachmentSheet(attachment: attachment),
  );
  if (decision == null || !decision.confirmed) return;
  try {
    await state.deleteAttachment(
      attachment.id,
      deleteRemote: decision.deleteRemoteFile,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(decision.deleteRemoteFile ? '素材和云端文件都已删除' : '素材已从列表移除'),
        ),
      );
  } on Exception catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(state.cleanErrorForDisplay(error))),
      );
  }
}

Future<void> _copyAttachmentUrl(
  BuildContext context,
  AppState state,
  Attachment attachment,
) async {
  final url = await state.resolveAttachmentShareUrl(attachment);
  if (url.trim().isEmpty) return;
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('已复制素材 URL')));
}

Future<void> _saveAttachmentToGallery(
  BuildContext context,
  AppState state,
  Attachment attachment,
) async {
  try {
    final saved = await state.saveAttachmentImageToGallery(attachment.id);
    if (!context.mounted) return;
    final message = saved == null ? '保存失败' : '已保存到系统相册';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  } on Exception catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(state.cleanErrorForDisplay(error))),
      );
  }
}

Future<void> _addAttachmentVideoToComposition(
  BuildContext context,
  AppState state,
  Attachment attachment,
) async {
  final added = await state.addAttachmentVideoToComposition(attachment.id);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(added ? '已添加到剪辑' : '添加失败')));
}

Future<void> _openVideoFrameCaptureFromLibrary(
  BuildContext context,
  AppState state,
  Attachment attachment,
) async {
  if (attachment.kind != AttachmentKind.video) return;
  var localUri = attachment.localResourceUri?.trim() ?? '';
  if (localUri.isEmpty) {
    final confirmed = await confirmAction(
      context,
      title: '需要先下载视频',
      message: '该视频当前只有云端版本，截帧前需要先下载到本地。是否现在下载？',
      confirmLabel: '下载并继续',
    );
    if (!confirmed || !context.mounted) return;
    final downloaded = await state.ensureAttachmentVideoLocal(attachment.id);
    if (!downloaded || !context.mounted) return;
    final refreshed = state.attachmentById(attachment.id);
    localUri = refreshed?.localResourceUri?.trim() ?? '';
    if (localUri.isEmpty) return;
    final jumpNow = await confirmAction(
      context,
      title: '下载完成',
      message: '视频已保存到本地，是否现在前往截帧页面？',
      confirmLabel: '立即前往',
    );
    if (!jumpNow || !context.mounted) return;
  }
  await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => VideoFrameCapturePage(
        source: VideoFrameSource(
          type: VideoFrameSourceType.attachment,
          label: attachment.label,
          sourceUri: localUri,
          attachmentId: attachment.id,
          fileName: attachment.localFileName ?? attachment.fileName,
        ),
        entryContext: VideoFrameEntryContext.library,
        defaultCategory: attachment.category,
      ),
    ),
  );
}

Future<void> _openCategoryManagement(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const CategoryManagementPage()),
  );
}

enum _AttachmentMenuAction { saveToGallery, copyUrl }

class _AttachmentCard extends StatefulWidget {
  const _AttachmentCard({
    required this.attachment,
    required this.previewAttachments,
  });

  final Attachment attachment;
  final List<Attachment> previewAttachments;

  @override
  State<_AttachmentCard> createState() => _AttachmentCardState();
}

class _DeleteAttachmentDecision {
  const _DeleteAttachmentDecision({
    required this.confirmed,
    required this.deleteRemoteFile,
  });

  final bool confirmed;
  final bool deleteRemoteFile;
}

class _DeleteAttachmentSheet extends StatefulWidget {
  const _DeleteAttachmentSheet({required this.attachment});

  final Attachment attachment;

  @override
  State<_DeleteAttachmentSheet> createState() => _DeleteAttachmentSheetState();
}

class _BatchDeleteAttachmentSheet extends StatefulWidget {
  const _BatchDeleteAttachmentSheet({required this.attachments});

  final List<Attachment> attachments;

  @override
  State<_BatchDeleteAttachmentSheet> createState() =>
      _BatchDeleteAttachmentSheetState();
}

class _BatchDeleteAttachmentSheetState
    extends State<_BatchDeleteAttachmentSheet> {
  bool _deleteRemoteFile = false;

  int get _remoteDeletableCount => widget.attachments
      .where((item) => item.objectKey?.trim().isNotEmpty == true)
      .length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final providerCounts = <StorageProvider, int>{};
    for (final attachment in widget.attachments) {
      providerCounts.update(
        attachment.storageProvider,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final missingObjectKeyCount =
        widget.attachments.length - _remoteDeletableCount;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: UtilityPanel(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Icon(
                      Icons.delete_sweep_rounded,
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('批量删除素材', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          '将删除 ${widget.attachments.length} 个素材记录。删除后引用会失效。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...providerCounts.entries.map(
                      (entry) => Text(
                        '${_storageProviderLabel(entry.key)}: ${entry.value} 个',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (missingObjectKeyCount > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '$missingObjectKeyCount 个素材缺少对象 Key，只能删除本地记录。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
                child: CheckboxListTile(
                  value: _remoteDeletableCount > 0 && _deleteRemoteFile,
                  onChanged: _remoteDeletableCount > 0
                      ? (value) =>
                            setState(() => _deleteRemoteFile = value ?? false)
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('同时删除云端文件'),
                  subtitle: Text(
                    _remoteDeletableCount > 0
                        ? '会按每个素材记录的云服务删除 $_remoteDeletableCount 个云端对象。'
                        : '所选素材没有可用对象 Key，只能删除本地记录。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(
                        const _DeleteAttachmentDecision(
                          confirmed: false,
                          deleteRemoteFile: false,
                        ),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        _DeleteAttachmentDecision(
                          confirmed: true,
                          deleteRemoteFile:
                              _remoteDeletableCount > 0 && _deleteRemoteFile,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                      ),
                      child: Text(
                        _remoteDeletableCount > 0 && _deleteRemoteFile
                            ? '删除素材和云端文件'
                            : '仅删除素材',
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

class _DeleteAttachmentSheetState extends State<_DeleteAttachmentSheet> {
  bool _deleteRemoteFile = false;

  bool get _supportsRemoteDelete =>
      widget.attachment.objectKey?.trim().isNotEmpty == true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final attachment = widget.attachment;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: UtilityPanel(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Icon(
                      Icons.delete_forever_rounded,
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('删除素材', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          '删除后，素材引用会失效。这个操作不可撤销。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      attachment.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
                child: CheckboxListTile(
                  value: _supportsRemoteDelete ? _deleteRemoteFile : false,
                  onChanged: _supportsRemoteDelete
                      ? (value) =>
                            setState(() => _deleteRemoteFile = value ?? false)
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('同时删除云端文件'),
                  subtitle: Text(
                    _supportsRemoteDelete
                        ? '会一并删除 ${_storageProviderLabel(attachment.storageProvider)} 上的原始对象。'
                        : '当前素材没有可用的对象 Key，只能删除本地记录。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(
                        const _DeleteAttachmentDecision(
                          confirmed: false,
                          deleteRemoteFile: false,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                      ),
                      child: const Text('保留素材'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        _DeleteAttachmentDecision(
                          confirmed: true,
                          deleteRemoteFile:
                              _supportsRemoteDelete && _deleteRemoteFile,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                      ),
                      child: Text(
                        _supportsRemoteDelete && _deleteRemoteFile
                            ? '删除素材和云端文件'
                            : '仅删除素材',
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

  String _storageProviderLabel(StorageProvider provider) {
    switch (provider) {
      case StorageProvider.qiniu:
        return '七牛';
      case StorageProvider.bitifulS4:
        return '缤纷云';
    }
  }
}

class _AttachmentCardState extends State<_AttachmentCard> {
  late final TextEditingController _labelController;
  late final FocusNode _labelFocusNode;
  bool _isEditingLabel = false;
  bool _showTagEditor = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.attachment.label);
    _labelFocusNode = FocusNode();
    _labelFocusNode.addListener(() {
      if (!_labelFocusNode.hasFocus) {
        _saveLabel();
        if (mounted && _isEditingLabel) {
          setState(() {
            _isEditingLabel = false;
          });
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant _AttachmentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.label != widget.attachment.label &&
        _labelController.text != widget.attachment.label) {
      _labelController.value = TextEditingValue(
        text: widget.attachment.label,
        selection: TextSelection.collapsed(
          offset: widget.attachment.label.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _labelFocusNode.dispose();
    super.dispose();
  }

  void _saveLabel() {
    AppScope.of(
      context,
    ).updateAttachmentLabel(widget.attachment.id, _labelController.text);
  }

  void _startEditingLabel() {
    if (_isEditingLabel) return;
    setState(() {
      _isEditingLabel = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _labelFocusNode.requestFocus();
      _labelController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _labelController.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final attachment = widget.attachment;
    final canAccess = state.canAccessAttachment(attachment);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final metaTextStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    return UtilityPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: canAccess
                    ? () => showAttachmentPreviewSheet(
                        context,
                        attachment,
                        attachments: widget.previewAttachments,
                      )
                    : null,
                child: _AttachmentThumbWithFileSize(
                  attachment: attachment,
                  width: 76,
                  height: 76,
                  radius: 14,
                  overlayLabel: attachment.kind == AttachmentKind.image
                      ? ''
                      : attachment.label,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _isEditingLabel
                              ? TextField(
                                  controller: _labelController,
                                  focusNode: _labelFocusNode,
                                  decoration: const InputDecoration(
                                    labelText: '素材名',
                                    isDense: true,
                                  ),
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) {
                                    _saveLabel();
                                    setState(() {
                                      _isEditingLabel = false;
                                    });
                                  },
                                  onTapOutside: (_) => _saveLabel(),
                                )
                              : _AttachmentLabelDisplay(
                                  label: attachment.label,
                                  onTap: _startEditingLabel,
                                ),
                        ),
                        const SizedBox(width: 4),
                        _AttachmentOverflowButton(
                          enabled: canAccess,
                          itemBuilder: (context) => [
                            if (attachment.kind == AttachmentKind.image)
                              const PopupMenuItem<_AttachmentMenuAction>(
                                value: _AttachmentMenuAction.saveToGallery,
                                child: _AttachmentMenuRow(
                                  icon: Icons.download_rounded,
                                  label: '保存到相册',
                                ),
                              ),
                            const PopupMenuItem<_AttachmentMenuAction>(
                              value: _AttachmentMenuAction.copyUrl,
                              child: _AttachmentMenuRow(
                                icon: Icons.content_copy_rounded,
                                label: '复制链接',
                              ),
                            ),
                          ],
                          onSelected: (action) {
                            switch (action) {
                              case _AttachmentMenuAction.saveToGallery:
                                _saveAttachmentToGallery(
                                  context,
                                  state,
                                  attachment,
                                );
                              case _AttachmentMenuAction.copyUrl:
                                _copyAttachmentUrl(context, state, attachment);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        compactFileName(attachment.fileName),
                        _formatCompactDateTime(attachment.createdAt),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaTextStyle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        displayCategoryLabel(attachment.category),
                        _roleLabel(attachment.role),
                        state.storageProviderLabel(attachment.storageProvider),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaTextStyle,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (attachment.status != AttachmentStatus.uploaded)
                          StatusPill(
                            label: _statusLabel(attachment.status),
                            tone: _statusColor(context, attachment.status),
                          ),
                        if (attachment.kind == AttachmentKind.video)
                          StatusPill(
                            label: _localStatusLabel(attachment),
                            tone: _localStatusColor(context, attachment),
                            busy:
                                attachment.localStatus ==
                                AttachmentLocalStatus.downloading,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AttachmentActionButton(
                icon: Icons.visibility_outlined,
                label: '预览',
                onPressed: canAccess
                    ? () => showAttachmentPreviewSheet(
                        context,
                        attachment,
                        attachments: widget.previewAttachments,
                      )
                    : null,
              ),
              if (attachment.kind == AttachmentKind.video) ...[
                _AttachmentActionButton(
                  icon: Icons.content_cut_rounded,
                  label: '添加到剪辑',
                  tooltip: '添加到剪辑',
                  onPressed: canAccess
                      ? () => _addAttachmentVideoToComposition(
                          context,
                          state,
                          attachment,
                        )
                      : null,
                ),
                _AttachmentActionButton(
                  icon: Icons.movie_creation_outlined,
                  label: '截帧',
                  onPressed: canAccess
                      ? () => _openVideoFrameCaptureFromLibrary(
                          context,
                          state,
                          attachment,
                        )
                      : null,
                ),
              ],
              _AttachmentActionButton(
                icon: Icons.delete_outline_rounded,
                label: '删除',
                onPressed: canAccess
                    ? () => _deleteAttachment(context, state, attachment)
                    : null,
              ),
              _AttachmentActionButton(
                icon: _showTagEditor
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.sell_outlined,
                label: _showTagEditor ? '收起' : '标签',
                onPressed: () =>
                    setState(() => _showTagEditor = !_showTagEditor),
              ),
            ],
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('素材角色', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _rolesForKind(attachment.kind)
                            .map(
                              (role) => FilterChip(
                                label: Text(_roleLabel(role)),
                                selected: attachment.role == role,
                                showCheckmark: false,
                                onSelected: (_) => state.updateAttachmentRole(
                                  attachment.id,
                                  role,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '分类标签',
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                          ToolIconButton(
                            icon: Icons.tune_rounded,
                            tooltip: '管理分类',
                            onPressed: () => _openCategoryManagement(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text(uncategorizedCategoryLabel),
                            selected: attachment.category.trim().isEmpty,
                            showCheckmark: false,
                            onSelected: (_) => state.updateAttachmentCategory(
                              attachment.id,
                              '',
                            ),
                          ),
                          ...state.categories.map(
                            (category) => FilterChip(
                              label: Text(category),
                              selected: attachment.category == category,
                              showCheckmark: false,
                              onSelected: (_) => state.updateAttachmentCategory(
                                attachment.id,
                                category,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            crossFadeState: _showTagEditor
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }

  List<AttachmentRole> _rolesForKind(AttachmentKind kind) {
    switch (kind) {
      case AttachmentKind.image:
        return const [
          AttachmentRole.firstFrame,
          AttachmentRole.lastFrame,
          AttachmentRole.referenceImage,
        ];
      case AttachmentKind.video:
        return const [AttachmentRole.referenceVideo];
      case AttachmentKind.audio:
        return const [AttachmentRole.referenceAudio];
    }
  }

  String _roleLabel(AttachmentRole role) {
    switch (role) {
      case AttachmentRole.firstFrame:
        return '首帧图';
      case AttachmentRole.lastFrame:
        return '尾帧图';
      case AttachmentRole.referenceImage:
        return '参考图';
      case AttachmentRole.referenceVideo:
        return '参考视频';
      case AttachmentRole.referenceAudio:
        return '参考音频';
    }
  }

  String _statusLabel(AttachmentStatus status) {
    switch (status) {
      case AttachmentStatus.queued:
        return '待上传';
      case AttachmentStatus.uploading:
        return '上传中';
      case AttachmentStatus.uploaded:
        return '';
      case AttachmentStatus.error:
        return '上传失败';
    }
  }

  Color _statusColor(BuildContext context, AttachmentStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case AttachmentStatus.queued:
        return scheme.onSurfaceVariant;
      case AttachmentStatus.uploading:
        return scheme.tertiary;
      case AttachmentStatus.uploaded:
        return scheme.onSurfaceVariant;
      case AttachmentStatus.error:
        return scheme.error;
    }
  }

  String _localStatusLabel(Attachment attachment) {
    switch (attachment.localStatus) {
      case AttachmentLocalStatus.none:
        return '仅云端';
      case AttachmentLocalStatus.downloading:
        return '下载中 ${attachment.localDownloadProgress}%';
      case AttachmentLocalStatus.ready:
        return '本地可截帧';
      case AttachmentLocalStatus.error:
        return '本地不可用';
    }
  }

  Color _localStatusColor(BuildContext context, Attachment attachment) {
    final scheme = Theme.of(context).colorScheme;
    switch (attachment.localStatus) {
      case AttachmentLocalStatus.none:
        return scheme.onSurfaceVariant;
      case AttachmentLocalStatus.downloading:
        return scheme.tertiary;
      case AttachmentLocalStatus.ready:
        return scheme.primary;
      case AttachmentLocalStatus.error:
        return scheme.error;
    }
  }
}

String _formatCompactDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
}

String _formatFileSize(int? bytes) {
  if (bytes == null || bytes < 0) return '大小未知';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  if (unitIndex == 0) return '${value.round()} ${units[unitIndex]}';
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unitIndex]}';
}

class _AttachmentThumbWithFileSize extends StatelessWidget {
  const _AttachmentThumbWithFileSize({
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
    final fileSize =
        attachment.fileSizeBytes == null || attachment.fileSizeBytes! < 0
        ? null
        : _formatFileSize(attachment.fileSizeBytes);
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AttachmentThumb(
          attachment: attachment,
          width: width,
          height: height,
          radius: radius,
          overlayLabel: overlayLabel,
        ),
        if (fileSize != null)
          Positioned(
            right: 5,
            top: 5,
            child: Container(
              constraints: BoxConstraints(maxWidth: width - 10),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.38),
                ),
              ),
              child: Text(
                fileSize,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  height: 1.05,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _storageProviderLabel(StorageProvider provider) {
  switch (provider) {
    case StorageProvider.qiniu:
      return '七牛云';
    case StorageProvider.bitifulS4:
      return '缤纷云（Bitiful）S4';
  }
}

class _AttachmentLabelDisplay extends StatelessWidget {
  const _AttachmentLabelDisplay({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.edit_outlined,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentActionButton extends StatelessWidget {
  const _AttachmentActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = colorScheme.onSurface;
    final background = colorScheme.surfaceContainerHighest;

    final button = TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _AttachmentOverflowButton extends StatelessWidget {
  const _AttachmentOverflowButton({
    required this.enabled,
    required this.itemBuilder,
    required this.onSelected,
  });

  final bool enabled;
  final PopupMenuItemBuilder<_AttachmentMenuAction> itemBuilder;
  final PopupMenuItemSelected<_AttachmentMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<_AttachmentMenuAction>(
      enabled: enabled,
      tooltip: '更多操作',
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: enabled
            ? colorScheme.onSurfaceVariant
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.42),
      ),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
    );
  }
}

class _AttachmentMenuRow extends StatelessWidget {
  const _AttachmentMenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}
