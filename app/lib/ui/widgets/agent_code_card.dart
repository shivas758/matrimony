import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme.dart';
import 'common.dart';

/// "Your agent code" — the agent's permanent code in large type, tap to copy
/// (SPEC §9.18 B / G). Shown on the pending-approval screen, in Settings and
/// right after the code is issued.
class AgentCodeCard extends StatelessWidget {
  const AgentCodeCard({super.key, required this.code, this.stateName, this.note = S.agentCodeHint});

  final String code;

  /// "Karnataka" — printed under the code when known.
  final String? stateName;

  /// The explanation under the code; null hides it.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.goldPale.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.gold.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => copyText(context, code, S.agentCodeCopied),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.yourAgentCode.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.goldDark,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // A long code (KA999ZZ) on a narrow phone shrinks, never clips.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        code,
                        maxLines: 1,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontFamily: AppTheme.bodyFont,
                          color: AppColors.navy,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    if ((stateName ?? '').isNotEmpty)
                      Text(
                        stateName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (note != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        note!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.copy_rounded, color: AppColors.navy),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
