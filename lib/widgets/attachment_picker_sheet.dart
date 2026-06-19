import 'package:flutter/material.dart';
import '../app/spacing.dart';

import '../app/app_state.dart';
import '../app/mock_data.dart';
import '../app/models.dart';
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
  });

  final AppState state;
  final String title;
  final String subtitle;
  final String initialQuery;
  final String initialCategory;
  final AttachmentKind? kind;
  final String? excludeAttachmentId;

  @override
  State<_AttachmentPickerSheet> createState() => _AttachmentPickerSheetState();
}

class _AttachmentPickerSheetState extends State<_AttachmentPickerSheet> {
  late final TextEditingController _queryController;
  late String _category;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _category = widget.initialCategory;
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attachments = widget.state.queryAttachments(
      query: _queryController.text,
      category: _category,
      kind: widget.kind,
      excludeAttachmentId: widget.excludeAttachmentId,
      uploadedOnly: true,
    );

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
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(widget.subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
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
                  '没有匹配的素材，可以先去素材页上传或补分类。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              ...attachments.map(
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
        ),
      ),
    );
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
    final colorScheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: colorScheme.primaryContainer,
      checkmarkColor: colorScheme.primary,
    );
  }
}
