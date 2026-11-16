import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/agent.dart';
import '../../state/auth_state.dart';
import '../screens/gift_codes_screen.dart';
import '../strings.dart';
import '../theme.dart';

/// Whether the "Not approved yet" banner shows for [agent] (SPEC §9.23 F):
/// a non-admin agent below the live-client mark, on a server that knows
/// approvals. Never for admins, approved agents or an older server.
bool showsApprovalBanner(Agent? agent) => agent != null && agent.needsApproval;

/// "Not approved yet — 3 of 10 clients live …" with a **Gift codes** button
/// (Profiles tab and More). Renders nothing when [showsApprovalBanner] is
/// false for the signed-in agent.
class ApprovalBanner extends StatelessWidget {
  const ApprovalBanner({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<AuthState>().agent;
    if (!showsApprovalBanner(agent)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final live = agent!.liveClientCount;
    final needed = agent.approvalClients;

    return Padding(
      padding: margin,
      child: Container(
        key: const ValueKey('approval-banner'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: AppColors.goldPale.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hourglass_top_rounded, size: 18, color: AppColors.goldDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    S.notApprovedTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  S.clientsShort(live, needed),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.goldDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: needed <= 0 ? 0 : (live / needed).clamp(0, 1).toDouble(),
                minHeight: 6,
                backgroundColor: Colors.white,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(height: 8),
            Text(S.notApprovedBody(live, needed), style: theme.textTheme.bodySmall),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GiftCodesScreen()),
                ),
                icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                label: const Text(S.giftCodes),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
