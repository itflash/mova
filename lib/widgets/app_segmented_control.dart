import 'package:flutter/material.dart';

import '../app/spacing.dart';

/// A segment option for [AppSegmentedControl].
class AppSegment<T> {
  const AppSegment({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

/// iOS-style segmented control with a sliding solid-fill indicator.
///
/// The selected segment gets a solid [ColorScheme.primary] pill that slides
/// between segments. Unselected segments use [ColorScheme.onSurfaceVariant].
class AppSegmentedControl<T> extends StatefulWidget {
  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<AppSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  State<AppSegmentedControl<T>> createState() => _AppSegmentedControlState<T>();
}

class _AppSegmentedControlState<T> extends State<AppSegmentedControl<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _animation = AlwaysStoppedAnimation(_selectedIndex.toDouble());
  }

  int get _selectedIndex {
    final idx = widget.segments.indexWhere((s) => s.value == widget.selected);
    return idx < 0 ? 0 : idx;
  }

  @override
  void didUpdateWidget(covariant AppSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = oldWidget.segments.indexWhere(
      (s) => s.value == oldWidget.selected,
    );
    final newIndex = _selectedIndex;
    if (oldIndex != newIndex) {
      _animation = Tween<double>(
        begin: (oldIndex < 0 ? 0 : oldIndex).toDouble(),
        end: newIndex.toDouble(),
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final count = widget.segments.length;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = (constraints.maxWidth) / count;
          return SizedBox(
            height: 36,
            child: Stack(
              children: [
                // Sliding indicator.
                AnimatedBuilder(
                  animation: _animation,
                  builder: (context, _) {
                    final left = _animation.value * segmentWidth;
                    return Positioned(
                      left: left,
                      top: 0,
                      bottom: 0,
                      width: segmentWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Material(
                          color: colorScheme.primary,
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                          elevation: 0,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    );
                  },
                ),
                // Segment labels.
                Row(
                  children: [
                    for (var i = 0; i < count; i++)
                      Expanded(
                        child: _SegmentLabel(
                          segment: widget.segments[i],
                          selected: i == _selectedIndex,
                          onTap: () => widget.onChanged(widget.segments[i].value),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.segment,
    required this.selected,
    required this.onTap,
  });

  final AppSegment segment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;
    final weight = selected ? FontWeight.w600 : FontWeight.w500;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
          children: [
            if (segment.icon != null) ...[
              Icon(segment.icon, size: 17, color: color),
              const SizedBox(width: AppSpacing.tightGap),
            ],
            Flexible(
              child: Text(
                segment.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: weight,
                  height: 1.0,
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
