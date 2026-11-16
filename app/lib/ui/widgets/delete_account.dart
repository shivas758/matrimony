import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../services/link_launcher.dart';
import '../strings.dart';
import 'common.dart';

/// "Delete my account" (SPEC §9.20 F, a Google Play requirement): a sheet
/// explaining what happens, then the public deletion page opens in the
/// browser — the request is confirmed with the person by an admin.
Future<void> confirmDeleteAccount(BuildContext context) async {
  final go = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(S.deleteMyAccount, style: theme.textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(S.deleteMyAccountBody, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text(S.openDeletionPage),
              ),
              const SizedBox(height: 6),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
            ],
          ),
        ),
      );
    },
  );
  if (go != true || !context.mounted) return;
  final ok = await context.read<LinkLauncher>().launch(Uri.parse(AppConfig.deleteAccountUrl));
  if (!ok && context.mounted) showSnack(context, S.cannotOpenBrowser, error: true);
}
