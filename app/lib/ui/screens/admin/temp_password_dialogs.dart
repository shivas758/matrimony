import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../strings.dart';
import '../../widgets/common.dart';

/// Dialogs shared by the password-reset list and the agent list: pick a
/// temporary password, then hand it to the agent over WhatsApp or the phone.
/// The app never sends it anywhere itself (SPEC §4 Auth).

/// 8 characters from an alphabet without look-alikes (no 0/O, 1/l/I).
String generateTemporaryPassword() {
  const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final rng = Random.secure();
  return List.generate(8, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
}

/// Asks the admin to confirm (or edit) a temporary password. Returns null on cancel.
Future<String?> promptTemporaryPassword(BuildContext context, {required String agentName}) {
  final controller = TextEditingController(text: generateTemporaryPassword());
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${S.resetPassword} — $agentName'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(S.tempPasswordHint),
            const SizedBox(height: 16),
            TextFormField(
              controller: controller,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: S.temporaryPassword,
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  tooltip: 'New suggestion',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => controller.text = generateTemporaryPassword(),
                ),
              ),
              validator: (v) => (v ?? '').trim().length < 6 ? 'Use at least 6 characters' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(ctx, controller.text.trim());
          },
          child: const Text(S.confirm),
        ),
      ],
    ),
  );
}

/// After the server accepted it: show the password once, with copy / WhatsApp.
Future<void> showTemporaryPasswordIssued(
  BuildContext context, {
  required String agentName,
  required String phone,
  required String password,
}) {
  final message = 'Hello $agentName, your temporary password for the Mediator app is: '
      '$password\nLog in with it and set your own password when asked.';
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: const Text('Temporary password set'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$agentName · +91 $phone'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                password,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.tempPasswordHint,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: password));
              showSnack(ctx, 'Password copied');
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send on WhatsApp'),
            onPressed: () {
              final uri = Uri.parse('https://wa.me/91$phone?text=${Uri.encodeComponent(message)}');
              launchUrl(uri, mode: LaunchMode.externalApplication);
              Navigator.pop(ctx);
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.close)),
        ],
      );
    },
  );
}
