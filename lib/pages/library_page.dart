import 'package:flutter/material.dart';
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

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final visibleAttachments = state.visibleLibrary;

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
                _LibraryFilterPanel(state: state),
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
                            onPressed: () => _pickFiles(context, state),
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
                        '共 ${state.library.length} 个素材，当前命中 ${visibleAttachments.length} 个。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SectionLabel('素材列表'),
                if (state.uploadErrorMessage != null) ...[
                  UtilityPanel(
                    child: Text(
                      state.uploadErrorMessage!,
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
                child: _LibraryEmptyState(state: state),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverList.separated(
                itemCount: visibleAttachments.length,
                itemBuilder: (context, index) => _AttachmentCard(
                  attachment: visibleAttachments[index],
                  previewAttachments: visibleAttachments,
                ),
                separatorBuilder: (_, _) => const SizedBox(height: 16),
              ),
            ),
        ],
      ),
    );
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
          DropdownButtonFormField<LibraryFilter>(
            initialValue: state.libraryFilter,
            decoration: const InputDecoration(labelText: '素材类型'),
            items: const [
              DropdownMenuItem(value: LibraryFilter.all, child: Text('全部')),
              DropdownMenuItem(value: LibraryFilter.image, child: Text('图片')),
              DropdownMenuItem(value: LibraryFilter.video, child: Text('视频')),
              DropdownMenuItem(value: LibraryFilter.audio, child: Text('音频')),
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
              Expanded(
                child: Text(
                  state.hasActiveLibraryFilters ? '已启用更多筛选' : '更多筛选',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              if (state.hasActiveLibraryFilters)
                TextButton(
                  onPressed: () {
                    state.clearLibraryFilters();
                    setState(() {
                      _showAdvanced = false;
                    });
                  },
                  child: const Text('清空'),
                ),
              IconButton(
                tooltip: _showAdvanced ? '收起更多筛选' : '展开更多筛选',
                onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                icon: AnimatedRotation(
                  turns: _showAdvanced ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(Icons.expand_more_rounded),
                ),
              ),
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
                      borderRadius: BorderRadius.circular(14),
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
                  borderRadius: BorderRadius.circular(16),
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
                  borderRadius: BorderRadius.circular(16),
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
                          borderRadius: BorderRadius.circular(14),
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
                          borderRadius: BorderRadius.circular(14),
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
    final metaTextStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return UtilityPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 420;
              final infoColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isEditingLabel)
                    TextField(
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
                  else
                    _AttachmentLabelDisplay(
                      label: attachment.label,
                      onTap: _startEditingLabel,
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AttachmentMetaBadge(
                        icon: Icons.folder_open_rounded,
                        label: displayCategoryLabel(attachment.category),
                      ),
                      _AttachmentMetaBadge(
                        icon: Icons.schedule_rounded,
                        label: _formatCompactDateTime(attachment.createdAt),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _AttachmentMetaLine(
                    label: '文件名',
                    value: attachment.fileName,
                    style: metaTextStyle,
                  ),
                  const SizedBox(height: 4),
                  _AttachmentMetaLine(
                    label: '添加时间',
                    value: formatDateTime(attachment.createdAt),
                    style: metaTextStyle,
                  ),
                ],
              );

              final thumb = InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: canAccess
                    ? () => showAttachmentPreviewSheet(
                        context,
                        attachment,
                        attachments: widget.previewAttachments,
                      )
                    : null,
                child: AttachmentThumb(
                  attachment: attachment,
                  width: isCompact ? constraints.maxWidth : 104,
                  height: isCompact ? 176 : 84,
                  radius: 18,
                  overlayLabel: attachment.label,
                ),
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [thumb, const SizedBox(height: 12), infoColumn],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  thumb,
                  const SizedBox(width: 12),
                  Expanded(child: infoColumn),
                ],
              );
            },
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
              if (attachment.kind == AttachmentKind.video)
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
              _AttachmentActionButton(
                icon: Icons.delete_outline_rounded,
                label: '删除',
                onPressed: canAccess
                    ? () => _deleteAttachment(context, state, attachment)
                    : null,
              ),
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
                      _saveAttachmentToGallery(context, state, attachment);
                    case _AttachmentMenuAction.copyUrl:
                      _copyAttachmentUrl(context, state, attachment);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
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
          const SizedBox(height: 14),
          Text('素材角色', style: Theme.of(context).textTheme.labelMedium),
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
                    onSelected: (_) =>
                        state.updateAttachmentRole(attachment.id, role),
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
                selected: attachment.category.trim().isEmpty,
                showCheckmark: false,
                onSelected: (_) =>
                    state.updateAttachmentCategory(attachment.id, ''),
              ),
              ...state.categories.map(
                (category) => FilterChip(
                  label: Text(category),
                  selected: attachment.category == category,
                  showCheckmark: false,
                  onSelected: (_) =>
                      state.updateAttachmentCategory(attachment.id, category),
                ),
              ),
            ],
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
        return '可引用';
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
        return Colors.green.shade700;
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

class _AttachmentMetaBadge extends StatelessWidget {
  const _AttachmentMetaBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
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

class _AttachmentMetaLine extends StatelessWidget {
  const _AttachmentMetaLine({
    required this.label,
    required this.value,
    required this.style,
  });

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          TextSpan(
            text: '$label: ',
            style: style?.copyWith(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _AttachmentActionButton extends StatelessWidget {
  const _AttachmentActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = colorScheme.onSurface;
    final background = colorScheme.surfaceContainerHighest;

    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: enabled
              ? colorScheme.surfaceContainerHighest
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.more_horiz_rounded,
              size: 18,
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 6),
            Text(
              '更多',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: enabled
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentMenuRow extends StatelessWidget {
  const _AttachmentMenuRow({
    required this.icon,
    required this.label,
  });

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
