import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/customer.dart';
import '../../../models/delete_request.dart';
import '../../../services/api_client.dart';
import '../../../services/clients_service.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../profiles/profile_detail_screen.dart';

/// Status colour for customers, interests and transfers — the request palette
/// plus the customer-specific states.
Color clientStatusColor(String status, ColorScheme scheme) => switch (status) {
      'active' || 'accepted' || 'approved' => AppColors.success,
      'pending' => AppColors.warning,
      'rejected' || 'declined' || 'revoked' => scheme.error,
      // suspended, withdrawn, expired, cancelled
      _ => scheme.outline,
    };

/// "1 interest" / "3 interests".
String interestsCountLabel(int n) => n == 1 ? '1 interest' : '$n interests';

/// Opens the phone app with the number. Never throws — a missing dialer
/// shows a snack instead.
Future<void> callNumber(BuildContext context, String phone) async {
  try {
    final ok = await launchUrl(Uri.parse('tel:$phone'));
    if (!ok && context.mounted) showSnack(context, S.cannotCall, error: true);
  } on PlatformException {
    if (context.mounted) showSnack(context, S.cannotCall, error: true);
  }
}

/// Opens a WhatsApp chat with the number (Indian numbers).
Future<void> whatsAppNumber(BuildContext context, String phone) async {
  try {
    final ok = await launchUrl(
      Uri.parse('https://wa.me/91$phone'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) showSnack(context, S.cannotCall, error: true);
  } on PlatformException {
    if (context.mounted) showSnack(context, S.cannotCall, error: true);
  }
}

/// Small "App" / "Form" pill: how the customer registered (SPEC §9.3).
class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final form = source == 'form';
    return StatusChip(
      label: form ? S.sourceForm : S.sourceApp,
      color: form ? const Color(0xFF00695C) : AppColors.navyLight,
      icon: form ? Icons.description_outlined : Icons.phone_android_rounded,
    );
  }
}

/// Photo + name + "Bride · 27 yrs · Community" row; tapping opens the profile.
/// The optional [label] is a small caption above the name ("Interested in").
class ProfileSummaryTile extends StatelessWidget {
  const ProfileSummaryTile({
    super.key,
    required this.profile,
    this.label,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });

  final ProfileSummary profile;
  final String? label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileDetailScreen(profileId: profile.id)),
      ),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 52,
                height: 52,
                child: AuthedPhoto(
                  url: profile.photoAbsoluteUrl,
                  api: api,
                  placeholderInitials: initialsOf(profile.fullName),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null)
                    Text(
                      label!.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.goldDark,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  Text(
                    profile.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (profile.subtitle.isNotEmpty)
                    Text(
                      profile.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                ],
              ),
            ),
            trailing ?? Icon(Icons.chevron_right_rounded, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

/// A person with a phone number and a Call button: the other party's agent
/// on an interest, a client's number on their detail screen. Copying the
/// number is one tap too — agents pass numbers on by WhatsApp constantly.
class ContactLine extends StatelessWidget {
  const ContactLine({
    super.key,
    required this.name,
    this.caption,
    this.subtitle,
    this.phone,
    this.icon = Icons.support_agent_rounded,
  });

  /// Small uppercase caption above the name ("Their agent").
  final String? caption;
  final String name;
  final String? subtitle;
  final String? phone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPhone = phone != null && phone!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.rule),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.navyTint,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: AppColors.navy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (caption != null)
                  Text(
                    caption!.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                if (hasPhone)
                  Text(
                    '+91 $phone',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          if (hasPhone) ...[
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: phone!));
                showSnack(context, 'Phone number copied');
              },
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                backgroundColor: AppColors.success.withValues(alpha: 0.14),
                foregroundColor: AppColors.success,
              ),
              onPressed: () => callNumber(context, phone!),
              icon: const Icon(Icons.call_rounded, size: 18),
              label: const Text(S.call),
            ),
          ],
        ],
      ),
    );
  }
}

/// Reject / Approve (or Decline / Accept) pair used by every decision row.
class DecisionRow extends StatelessWidget {
  const DecisionRow({
    super.key,
    required this.busy,
    required this.onReject,
    required this.onApprove,
    this.rejectLabel = S.reject,
    this.approveLabel = S.approve,
  });

  final bool busy;
  final VoidCallback onReject;
  final VoidCallback onApprove;
  final String rejectLabel;
  final String approveLabel;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: busy ? null : onReject,
              child: Text(rejectLabel),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: busy ? null : onApprove,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(approveLabel),
            ),
          ),
        ],
      );
}

/// Yes/no confirmation dialog; resolves true when the primary action is tapped.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final theme = Theme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Quoted note under a request.
class NoteBox extends StatelessWidget {
  const NoteBox(this.note, {super.key});

  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('"$note"', style: theme.textTheme.bodySmall),
    );
  }
}

/// Section title inside a list with a "N pending" pill.
class GroupHeader extends StatelessWidget {
  const GroupHeader(this.title, {super.key, this.count = 0, this.countLabel = 'pending'});

  final String title;
  final int count;
  final String countLabel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SectionHeader(
          title,
          trailing: count > 0
              ? StatusChip(label: '$count $countLabel', color: AppColors.warning)
              : null,
        ),
      );
}

/// "Paid in cash?" with an optional note (SPEC §9.13). Returns the note
/// ('' when none) on confirm, null on cancel.
Future<String?> askMarkPaid(BuildContext context, String profileName) async {
  final note = TextEditingController();
  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.markPaidTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.markPaidBody(profileName)),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLength: 300,
              decoration: const InputDecoration(hintText: S.markPaidNoteHint, isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.markPaidConfirm),
          ),
        ],
      ),
    );
    return ok == true ? note.text.trim() : null;
  } finally {
    note.dispose();
  }
}

/// A client's request to delete a paid profile (SPEC §9.13): who, which
/// profile, the reason, and Approve delete / Reject while pending. Shared by
/// the Clients → Deletes tab and the client detail screen.
class DeleteRequestTile extends StatelessWidget {
  const DeleteRequestTile({
    super.key,
    required this.request,
    required this.busy,
    this.onApprove,
    this.onReject,
    this.onOpenClient,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
  });

  final ProfileDeleteRequest request;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  /// Tapping the header opens the client (list screen only).
  final VoidCallback? onOpenClient;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;
    final decide = r.isPending && r.canDecide && onApprove != null && onReject != null;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.delete_outline_rounded, size: 20, color: theme.colorScheme.error),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: r.customer.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ' ${S.asksToDelete} ',
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
                TextSpan(text: r.profileName, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Text(
          formatDate(r.createdAt),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onOpenClient != null)
            InkWell(onTap: onOpenClient, child: header)
          else
            header,
          if (r.profile != null) ...[
            const SizedBox(height: 6),
            ProfileSummaryTile(
              profile: r.profile!,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            ),
          ],
          if ((r.reason ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            NoteBox(r.reason!),
          ],
          if (!decide) ...[
            const SizedBox(height: 10),
            StatusChip(
              label: r.statusLabel,
              color: r.isPending
                  ? AppColors.warning
                  : r.status == 'approved'
                      ? theme.colorScheme.error
                      : theme.colorScheme.outline,
            ),
          ] else ...[
            const SizedBox(height: 10),
            DecisionRow(
              busy: busy,
              onReject: onReject!,
              onApprove: onApprove!,
              approveLabel: S.approveDelete,
            ),
          ],
        ],
      ),
    );
  }
}

/// Confirms, then approves or rejects a delete request. Returns true when
/// something changed (the caller reloads).
Future<bool> decideDeleteRequest(
  BuildContext context,
  ProfileDeleteRequest r,
  String action,
) async {
  if (action == 'approve') {
    final ok = await confirmAction(
      context,
      title: '${S.approveDelete}?',
      body: S.approveDeleteBody(r.profileName),
      confirmLabel: S.approveDelete,
      destructive: true,
    );
    if (!ok || !context.mounted) return false;
  }
  try {
    final service = context.read<ClientsService>();
    if (action == 'approve') {
      await service.approveDeleteRequest(r.id);
    } else {
      await service.rejectDeleteRequest(r.id);
    }
    if (!context.mounted) return true;
    context.read<AuthState>().refreshNotifications();
    showSnack(context, action == 'approve' ? S.profileDeleted : S.deleteRejected);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
    return false;
  }
}
