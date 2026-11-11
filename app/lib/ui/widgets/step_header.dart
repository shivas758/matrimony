import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme.dart';

/// The header of a multi-step form (SPEC §9.18 F): numbered, labelled steps
/// joined by a line — the current one highlighted, completed ones ticked.
/// With [onStepTapped] a step can be opened by tapping it ([canTap] narrows
/// which ones respond).
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.labels,
    required this.current,
    this.completed = const {},
    this.onStepTapped,
    this.canTap,
  });

  /// One label per step; a `\n` breaks it over two lines ("Family &\ncontact").
  final List<String> labels;

  /// Index of the step being shown.
  final int current;

  /// Indices drawn with a tick.
  final Set<int> completed;

  /// Called with the tapped step's index; null makes the header read-only.
  final ValueChanged<int>? onStepTapped;

  /// Which steps respond to a tap (all of them when null).
  final bool Function(int index)? canTap;

  bool _reached(int i) => i == current || completed.contains(i);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Large system fonts must not blow the header up; the form below scales.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: Material(
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: _StepCell(
                    index: i,
                    count: labels.length,
                    label: labels[i],
                    isCurrent: i == current,
                    isCompleted: completed.contains(i) && i != current,
                    lineBefore: i > 0 && _reached(i - 1) && _reached(i),
                    lineAfter: i < labels.length - 1 && _reached(i) && _reached(i + 1),
                    onTap: onStepTapped != null && i != current && (canTap?.call(i) ?? true)
                        ? () => onStepTapped!(i)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepCell extends StatelessWidget {
  const _StepCell({
    required this.index,
    required this.count,
    required this.label,
    required this.isCurrent,
    required this.isCompleted,
    required this.lineBefore,
    required this.lineAfter,
    required this.onTap,
  });

  static const double _dot = 28;

  final int index;
  final int count;
  final String label;
  final bool isCurrent;
  final bool isCompleted;

  /// The connecting line on each side is gold once both ends are reached.
  final bool lineBefore;
  final bool lineAfter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = index == 0;
    final last = index == count - 1;

    Widget line(bool visible, bool done) => Expanded(
          child: Container(
            height: 2,
            color: !visible
                ? Colors.transparent
                : done
                    ? AppColors.gold
                    : AppColors.rule,
          ),
        );

    final dot = Container(
      width: _dot,
      height: _dot,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCurrent
            ? AppColors.navy
            : isCompleted
                ? AppColors.gold
                : Colors.white,
        border: Border.all(
          color: isCurrent
              ? AppColors.navy
              : isCompleted
                  ? AppColors.gold
                  : AppColors.rule,
          width: 1.5,
        ),
      ),
      child: isCompleted
          ? const Icon(Icons.check_rounded, size: 17, color: AppColors.navyDeep)
          : Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 13,
                height: 1,
                fontWeight: FontWeight.w700,
                color: isCurrent ? Colors.white : AppColors.muted,
              ),
            ),
    );

    final cell = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              line(!first, lineBefore),
              dot,
              line(!last, lineAfter),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            // "Professional" must fit a quarter of a narrow phone: the label
            // shrinks to its cell instead of being cut off.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: isCurrent
                      ? AppColors.navy
                      : isCompleted
                          ? AppColors.ink
                          : AppColors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: onTap != null,
      selected: isCurrent,
      label: '${S.stepOf} ${index + 1} of $count: ${label.replaceAll('\n', ' ')}'
          '${isCompleted ? ', ${S.stepCompleted}' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: cell,
      ),
    );
  }
}
