import 'package:flutter/material.dart';

import '../app/spacing.dart';

/// A dropdown selector styled to match the app's input fields.
///
/// Uses [PopupMenuButton] under the hood for full visual control,
/// rendered to look like a filled text field with a chevron icon.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelText,
    this.hintText,
    this.isExpanded = false,
  });

  final T? value;
  final List<DropdownItemData<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? labelText;
  final String? hintText;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = items.cast<DropdownItemData<T>?>().firstWhere(
          (item) => item?.value == value,
          orElse: () => null,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (labelText != null) ...[
          Text(
            labelText!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        LayoutBuilder(
          builder: (context, constraints) => PopupMenuButton<T>(
            enabled: onChanged != null,
            tooltip: hintText ?? labelText ?? '',
            onSelected: onChanged,
            position: PopupMenuPosition.under,
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              maxWidth: constraints.maxWidth,
            ),
          itemBuilder: (context) => items
              .map((item) => PopupMenuItem<T>(
                    value: item.value,
                    child: Row(
                      children: [
                        if (item.icon != null) ...[
                          Icon(item.icon,
                              size: 18, color: cs.onSurfaceVariant),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            item.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: item.value == value
                                  ? cs.primary
                                  : cs.onSurface,
                              fontWeight: item.value == value
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (item.value == value)
                          Icon(Icons.check_rounded, size: 18, color: cs.primary),
                      ],
                    ),
                  ))
              .toList(),
          child: _buildField(
            context,
            selected?.label ?? hintText ?? '',
          ),
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    BuildContext context,
    String displayText,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasValue = value != null;

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  displayText,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: hasValue
                        ? cs.onSurface
                        : cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Data model for dropdown items, decoupled from widget internals.
class DropdownItemData<T> {
  const DropdownItemData({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}
