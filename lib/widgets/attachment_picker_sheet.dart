import 'package:flutter/material.dart';
import '../app/spacing.dart';

import '../app/app_state.dart';
import '../app/mock_data.dart';
import '../app/models.dart';
import '../pages/home_shell.dart';
import 'attachment_media.dart';

Future<Attachment?> showAttachmentPickerSheet({
  required BuildContext context,
  required AppState state,
  required String title,
  required String subtitle,
  String initialQuery = '',
  String initialCategory = 'all',
  AttachmentKind? kind,
  String? excludeAttachmentId,
  AttachmentRole ephemeralRole = AttachmentRole.referenceImage,
  bool allowEphemeral = true,
}) {
  return showModalBottomSheet<Attachment>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return _AttachmentPickerSheet(
        state: state,
        title: title,
        subtitle: subtitle,
        initialQuery: initialQuery,
        initialCategory: initialCategory,
        kind: kind,
        excludeAttachmentId: excludeAttachmentId,
        ephemeralRole: ephemeralRole,
        allowEphemeral: allowEphemeral,
      );
    },
  );
}

class _AttachmentPickerSheet extends StatefulWidget {
  const _AttachmentPickerSheet({
    required this.state,
    required this.title,
    required this.subtitle,
    required this.initialQuery,
    required this.initialCategory,
    this.kind,
    this.excludeAttachmentId,
    required this.ephemeralRole,
    required this.allowEphemeral,
  });

  final AppState state;
  final String title;
  final String subtitle;
  final String initialQuery;
  final String initialCategory;
  final AttachmentKind? kind;
  final String? excludeAttachmentId;
  final AttachmentRole ephemeralRole;
  final bool allowEphemeral;

  @override
  State<_AttachmentPickerSheet> createState() => _AttachmentPickerSheetState();
}

class _AttachmentPickerSheetState extends State<_AttachmentPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _queryController;
  late String _category;
  late final TabController _tabController;
  bool _uploadingEphemeral = false;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _category = widget.initialCategory;
    _tabController = TabController(
      length: widget.allowEphemeral ? 2 : 1,
      vsync: this,
    );
    _tabController.addListener(_handleTabChanged);
    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _queryController.dispose();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _handleTabChanged() {
    if (mounted) setState(() {});
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final showTabs = widget.allowEphemeral;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(widget.subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            if (showTabs) ...[
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: '素材库'),
                  Tab(text: '手机相册'),
                ],
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: showTabs
                  ? TabBarView(
                      controller: _tabController,
                      children: [_buildLibraryTab(), _buildDeviceTab()],
                    )
                  : _buildLibraryTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryTab() {
    final attachments = widget.state.queryAttachments(
      query: _queryController.text,
      category: _category,
      kind: widget.kind,
      excludeAttachmentId: widget.excludeAttachmentId,
      uploadedOnly: true,
    );
    return ListView(
      children: [
        const SizedBox(height: 8),
        TextField(
          controller: _queryController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: '搜索素材名、文件名、分类',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CategoryChip(
              label: '全部',
              selected: _category == 'all',
              onTap: () => setState(() => _category = 'all'),
            ),
            _CategoryChip(
              label: uncategorizedCategoryLabel,
              selected: _category == uncategorizedCategory,
              onTap: () =>
                  setState(() => _category = uncategorizedCategory),
            ),
            ...widget.state.categories.map(
              (item) => _CategoryChip(
                label: item,
                selected: _category == item,
                onTap: () => setState(() => _category = item),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('最近使用排在前面'),
          subtitle: Text(
            widget.state.libraryRecentFirst ? '已按最近使用排序' : '已按添加时间倒序',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          value: widget.state.libraryRecentFirst,
          onChanged: (value) {
            widget.state.setLibraryRecentFirst(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 8),
        if (attachments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              widget.allowEphemeral
                  ? '素材库暂无匹配内容，也可以切到"手机相册"临时上传一张。'
                  : '没有匹配的素材，可以先去素材页上传或补分类。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          ...groupAttachmentsByTask(attachments).map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: group.isTaskGroup
                  ? _PickerTaskGroupRow(
                      group: group,
                      selectedIds: widget.state.selectedAttachmentIds,
                      onPick: (attachment) =>
                          Navigator.of(context).pop(attachment),
                    )
                  : _AttachmentPickerCard(
                      attachment: group.representative,
                      selected: widget.state.selectedAttachmentIds.contains(
                        group.representative.id,
                      ),
                      onTap: () =>
                          Navigator.of(context).pop(group.representative),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _buildDeviceTab() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ephemerals = widget.state.ephemeralAttachments
        .where((item) => widget.kind == null || item.kind == widget.kind)
        .where((item) => item.id != widget.excludeAttachmentId)
        .toList();
    final uploadError = widget.state.uploadErrorMessage;

    return ListView(
      children: [
        const SizedBox(height: 8),
        Text(
          '从相册直接挑一张素材，AgentEarth 会临时托管上传，本次任务用完就丢，不进素材库。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            icon: _uploadingEphemeral
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _uploadingEphemeral ? null : _pickEphemeral,
            label: Text(_uploadingEphemeral ? '正在上传…' : '从相册 / 文件里选…'),
          ),
        ),
        if (uploadError != null && uploadError.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            uploadError,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (ephemerals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '本次会话还没有临时素材。选完之后可以在这里复用。',
              style: theme.textTheme.bodySmall,
            ),
          )
        else ...[
          Text('本次会话的临时素材', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          ...ephemerals.map(
            (attachment) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AttachmentPickerCard(
                attachment: attachment,
                selected: widget.state.selectedAttachmentIds.contains(
                  attachment.id,
                ),
                onTap: () => Navigator.of(context).pop(attachment),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickEphemeral() async {
    setState(() => _uploadingEphemeral = true);
    try {
      final attachment = await widget.state.pickEphemeralAttachment(
        kindFilter: widget.kind,
        role: widget.ephemeralRole,
      );
      if (!mounted) return;
      if (attachment != null) {
        Navigator.of(context).pop(attachment);
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingEphemeral = false);
      }
    }
  }
}

class _AttachmentPickerCard extends StatelessWidget {
  const _AttachmentPickerCard({
    required this.attachment,
    required this.selected,
    required this.onTap,
  });

  final Attachment attachment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              AttachmentThumb(
                attachment: attachment,
                width: 108,
                height: 76,
                radius: 18,
                overlayLabel: attachment.label,
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${displayCategoryLabel(attachment.category)} · ${compactFileName(attachment.fileName)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '添加于 ${formatDateTime(attachment.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.chevron_right_rounded,
                size: 20,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 同任务多素材的横向选择行：一行展示该任务的全部产出，点哪张就选哪张。
class _PickerTaskGroupRow extends StatelessWidget {
  const _PickerTaskGroupRow({
    required this.group,
    required this.selectedIds,
    required this.onPick,
  });

  final AttachmentGroup group;
  final List<String> selectedIds;
  final ValueChanged<Attachment> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final representative = group.representative;
    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '同任务 ${group.count} 张',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${displayCategoryLabel(representative.category)} · ${formatDateTime(representative.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: group.items.length,
                itemBuilder: (context, index) {
                  final attachment = group.items[index];
                  final selected = selectedIds.contains(attachment.id);
                  return InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    onTap: () => onPick(attachment),
                    child: Container(
                      width: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(
                          color: selected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: AttachmentThumb(
                                attachment: attachment,
                                width: 100,
                                height: 100,
                                radius: 0,
                                overlayLabel: attachment.label,
                              ),
                            ),
                            if (selected)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.check_rounded,
                                    size: 14,
                                    color: colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(width: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TagChip(
      label: label,
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
