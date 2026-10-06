import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../widgets/common.dart';

/// The one gate left in v1.1 (SPEC §9.12): a SUSPENDED account. Guests,
/// pending, rejected and active customers all land on Home. Shows the agent
/// (with Call) when there is one, a "Check again" and Logout.
class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key});

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  bool _checking = false;

  Future<void> _refresh() async {
    setState(() => _checking = true);
    try {
      await context.read<AuthState>().refreshCustomer();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, friendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = context.watch<AuthState>().customer;
    final agent = customer?.agent;
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        title: Text(customer?.fullName ?? ''),
        actions: [
          IconButton(
            tooltip: S.logout,
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: error.withValues(alpha: 0.12), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(Icons.pause_circle_rounded, size: 48, color: error),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              S.suspendedTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              S.suspendedBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 28),
            if (agent != null) ...[
              SurfaceCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(S.yourAgent),
                    AgentRow(agent: agent),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            OutlinedButton.icon(
              onPressed: _checking ? null : _refresh,
              icon: _checking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded),
              label: const Text(S.checkAgain),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => context.read<AuthState>().logout(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text(S.logout),
            ),
          ],
        ),
      ),
    );
  }
}
