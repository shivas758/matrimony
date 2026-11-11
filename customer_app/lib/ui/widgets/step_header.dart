import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme.dart';

/// The numbered steps across the top of a multi-step form (SPEC §9.18 F):
/// the current step highlighted, completed ones ticked, upcoming ones muted,
/// joined by a line. Each step takes an equal share of the width and its
/// label wraps to two lines, so four steps fit a narrow phone.
///
/// With [onTap] set, a step whose [canTap] says yes (every step when
/// [canTap] is null) can be tapped to jump to it.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.labels,
    required this.current,
    this.completed = const {},
    this.onTap,
    this.canTap,
  }) : assert(current >= 0 && current < labels.length);

  /// One short label per step, in order.
  final List<String> labels;

  /// Zero-based index of the step being shown.
  final int current;

  /// Zero-based indexes of the steps to tick.
  final Set<int> completed;

  final ValueChanged<int>? onTap;
  final bool Function(int step)? canTap;

  static const double _dot = 30;

  bool _tappable(int i) => onTap != null && i != current && (canTap?.call(i) ?? true);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: _Step(
                number: i + 1,
                total: labels.length,
                label: labels[i],
                state: i == current
                    ? _StepState.current
                    : completed.contains(i)
                        ? _StepState.done
                        : _StepState.upcoming,
                // The line is gold up to the furthest ticked / current step.
                lineBefore: i == 0 ? null : (completed.contains(i - 1) || i - 1 == current) && (completed.contains(i) || i == current),
                lineAfter: i == labels.length - 1
                    ? null
                    : (completed.contains(i) || i == current) && (completed.contains(i + 1) || i + 1 == current),
                onTap: _tappable(i) ? () => onTap!(i) : null,
                textTheme: theme.textTheme,
              ),
            ),
        ],
      ),
    );
  }
}

enum _StepState { done, current, upcoming }

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.total,
    required this.label,
    required this.state,
    required this.lineBefore,
    required this.lineAfter,
    required this.onTap,
    required this.textTheme,
  });

  final int number;
  final int total;
  final String label;
  final _StepState state;

  /// Null = no line on that side (first / last step); true = a done stretch.
  final bool? lineBefore;
  final bool? lineAfter;
  final VoidCallback? onTap;
  final TextTheme textTheme;

  Widget _line(bool? done) => Expanded(
        child: done == null
            ? const SizedBox.shrink()
            : Container(height: 2, color: done ? AppColors.gold : AppColors.rule),
      );

  @override
  Widget build(BuildContext context) {
    final (fill, border, ink) = switch (state) {
      _StepState.done => (AppColors.success, AppColors.success, Colors.white),
      _StepState.current => (AppColors.wine, AppColors.gold, Colors.white),
      _StepState.upcoming => (Colors.white, AppColors.rule, AppColors.muted),
    };
    final Widget child = state == _StepState.done
        ? Icon(Icons.check_rounded, size: 18, color: ink)
        : Text('$number', style: TextStyle(fontWeight: FontWeight.w700, color: ink, fontSize: 14, height: 1));
    final labelStyle = textTheme.labelSmall?.copyWith(
      fontSize: 11.5,
      height: 1.2,
      letterSpacing: 0,
      fontWeight: state == _StepState.current ? FontWeight.w700 : FontWeight.w500,
      color: switch (state) {
        _StepState.current => AppColors.wine,
        _StepState.done => AppColors.ink,
        _StepState.upcoming => AppColors.muted,
      },
    );

    return Semantics(
      button: onTap != null,
      selected: state == _StepState.current,
      label: '${S.stepOf(number, total)}: $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _line(lineBefore),
                  Container(
                    width: StepHeader._dot,
                    height: StepHeader._dot,
                    decoration: BoxDecoration(
                      color: fill,
                      shape: BoxShape.circle,
                      border: Border.all(color: border, width: state == _StepState.current ? 2 : 1.4),
                    ),
                    alignment: Alignment.center,
                    child: child,
                  ),
                  _line(lineAfter),
                ],
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                // Several words wrap onto two lines; a single long word
                // ("Professional") shrinks to fit rather than break in two.
                child: label.trim().contains(' ')
                    ? Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle,
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label, maxLines: 1, softWrap: false, style: labelStyle),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
