import 'package:flutter/material.dart';

import '../../models/moderation.dart';
import '../strings.dart';
import '../theme.dart';

/// "Report profile" (SPEC §9.22 A): one of six reasons and optional details
/// (up to 500 characters). Pops `(reason, details)`, or null when closed.
class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key});

  static const maxDetails = 500;

  static Future<(ReportReason, String)?> show(BuildContext context) =>
      showModalBottomSheet<(ReportReason, String)>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => Padding(
          // Keeps the details field above the keyboard.
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: const ReportSheet(),
        ),
      );

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportReason? _reason;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reason = _reason;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(S.reportProfile, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy)),
          const SizedBox(height: 4),
          Text(
            S.reportProfileBody,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 8),
          RadioGroup<ReportReason>(
            groupValue: reason,
            onChanged: (v) => setState(() => _reason = v),
            child: Column(
              children: [
                for (final r in ReportReason.values)
                  RadioListTile<ReportReason>(
                    value: r,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(r.label, style: theme.textTheme.bodyLarge),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _details,
            maxLength: ReportSheet.maxDetails,
            maxLines: 4,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: S.reportDetailsLabel,
              hintText: S.reportDetailsHint,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: reason == null
                ? null
                : () => Navigator.pop(context, (reason, _details.text.trim())),
            icon: const Icon(Icons.flag_outlined),
            label: const Text(S.sendReport),
          ),
        ],
      ),
    );
  }
}
