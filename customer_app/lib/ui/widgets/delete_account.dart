import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../services/link_launcher.dart';
import '../strings.dart';
import '../theme.dart';
import 'common.dart';

/// *Delete my account* (SPEC §9.20 F, a Google Play requirement): on More and
/// on the suspended screen, so every signed-in customer can reach it.
class DeleteAccountTile extends StatelessWidget {
  const DeleteAccountTile({super.key});

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.person_remove_outlined, color: error),
        title: const Text(S.deleteAccount, style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text(S.deleteAccountSubtitle),
        trailing: const Icon(Icons.open_in_new_rounded, color: AppColors.muted, size: 20),
        onTap: () => confirmDeleteAccount(context),
      ),
    );
  }
}

/// Explains what happens, then opens the public deletion page
/// ([AppConfig.deleteAccountUrl]) in the browser. Nothing is deleted in the
/// app itself: the team confirms with the person on their registered number.
Future<void> confirmDeleteAccount(BuildContext context) async {
  final go = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              S.deleteAccount,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.wine),
            ),
            const SizedBox(height: 10),
            Text(
              S.deleteAccountBody,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.45),
            ),
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
      );
    },
  );
  if (go != true || !context.mounted) return;
  final opened = await context.read<LinkLauncher>().openExternal(Uri.parse(AppConfig.deleteAccountUrl));
  if (!opened && context.mounted) showSnack(context, S.linkOpenFailed, error: true);
}
