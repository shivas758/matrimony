import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/safety.dart';
import '../../services/api_client.dart';
import '../../services/profile_service.dart';
import '../strings.dart';
import '../theme.dart';
import 'common.dart';

/// *Report profile* (SPEC §9.22 A): one of six reasons, optional details
/// (≤ 500), Submit → `POST /customer/profiles/:id/report`. Resolves to true
/// once the report is in (the caller thanks the person); false when closed.
/// A failed report stays open with the server's message.
Future<bool> showReportSheet(BuildContext context, {required int profileId}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ReportSheet(profileId: profileId),
  );
  return sent == true;
}

class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key, required this.profileId});

  final int profileId;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  final _details = TextEditingController();
  ReportReason? _reason;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ProfileService>().reportProfile(widget.profileId, reason, details: _details.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      // Not visible to me (404) / my own profile: the server words it best.
      final serverWords = (e.status == 404 || e.code == 'own_profile') && e.message.trim().isNotEmpty;
      setState(() => _error = serverWords ? e.message : friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Above the keyboard while typing the details.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              S.reportProfile,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.wine),
            ),
            const SizedBox(height: 6),
            Text(
              S.reportProfileBody,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 8),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (r) {
                if (!_busy) setState(() => _reason = r);
              },
              child: Column(
                children: [
                  for (final r in ReportReason.values)
                    RadioListTile<ReportReason>(
                      value: r,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(S.reportReasonLabel(r.apiValue), style: theme.textTheme.bodyLarge),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _details,
              enabled: !_busy,
              maxLength: 500,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: S.reportDetailsHint),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _reason == null || _busy ? null : _submit,
              icon: _busy ? const ButtonSpinner() : const Icon(Icons.flag_outlined),
              label: const Text(S.submitReport),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text(S.cancel),
            ),
          ],
        ),
      ),
    );
  }
}
