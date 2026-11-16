import 'package:flutter/material.dart';

import '../strings.dart';

/// Asks for a reason / note of 3–200 characters before a rejection (a UPI
/// payment, SPEC §9.20 D; an account-deletion request, §9.20 F) and pops
/// the trimmed text, or null when cancelled. With [optional] (the report
/// actions, §9.22 A) an empty note is fine and pops `''`.
class ReasonDialog extends StatefulWidget {
  const ReasonDialog({
    super.key,
    required this.title,
    required this.body,
    this.label = S.rejectReasonLabel,
    this.hint,
    this.confirmLabel = S.reject,
    this.optional = false,
    this.destructive = true,
  });

  final String title;
  final String body;
  final String label;
  final String? hint;
  final String confirmLabel;

  /// The note may be left empty.
  final bool optional;

  /// A red confirm button.
  final bool destructive;

  static const minLength = 3;
  static const maxLength = 200;

  static bool isValidReason(String v, {bool optional = false}) {
    final t = v.trim();
    if (optional && t.isEmpty) return true;
    return t.length >= minLength && t.length <= maxLength;
  }

  @override
  State<ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<ReasonDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) Navigator.pop(context, _reason.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reason,
              autofocus: true,
              maxLength: ReasonDialog.maxLength,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
              validator: (v) => ReasonDialog.isValidReason(v ?? '', optional: widget.optional)
                  ? null
                  : S.rejectReasonInvalid,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error)
              : null,
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
