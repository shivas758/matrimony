import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/auth_state.dart';
import '../../strings.dart';

/// Shown to agents whose account is still `pending` (or `suspended`).
/// They hold a valid token but every data route returns 403 (CLAUDE.md rule 2).
class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    await context.read<AuthState>().refreshAgent();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final agent = auth.agent;
    final suspended = agent?.isSuspended ?? false;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(agent?.fullName ?? ''),
        actions: [
          IconButton(
            tooltip: S.logout,
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _check,
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 40),
            Icon(
              suspended ? Icons.block_rounded : Icons.hourglass_top_rounded,
              size: 72,
              color: suspended ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              suspended ? S.suspendedTitle : S.pendingTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              suspended ? S.suspendedBody : S.pendingBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline),
            ),
            if (!suspended) ...[
              const SizedBox(height: 8),
              Text(
                S.pendingHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _checking ? null : _check,
                icon: _checking
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: const Text(S.checkAgain),
              ),
            ],
            if (agent != null && agent.communities.isNotEmpty) ...[
              const SizedBox(height: 40),
              Text(
                S.myCommunities.toUpperCase(),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in agent.communities) Chip(label: Text(c.name)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
