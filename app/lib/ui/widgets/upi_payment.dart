import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../config.dart';
import '../../models/payment.dart';
import '../../services/api_client.dart';
import '../../services/link_launcher.dart';
import '../strings.dart';
import '../theme.dart';
import 'common.dart';

// Direct UPI payment pieces (SPEC §9.20 E): the pay card (UPI app button,
// QR code, UPI ID), the UTR form and the payment-state note.

/// Amount, "Pay ₹… with UPI app" (opens [UpiInfo.uri] through the
/// [LinkLauncher] from Provider), a QR code of the same link — to pay from
/// another phone — and the UPI ID and name with a Copy button.
class UpiPayCard extends StatelessWidget {
  const UpiPayCard({super.key, required this.upi, this.title});

  final UpiInfo upi;

  /// Shown above the amount, e.g. "One-time fee for Kamma".
  final String? title;

  Future<void> _pay(BuildContext context) async {
    final ok = await context.read<LinkLauncher>().launch(Uri.parse(upi.uri));
    if (!ok && context.mounted) showSnack(context, S.upiNoApp, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) Text(title!, style: muted, textAlign: TextAlign.center),
          Text(
            S.rupees(upi.amountInr),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: AppColors.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _pay(context),
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: Text(S.payWithUpiApp(upi.amountInr)),
          ),
          const SizedBox(height: 16),
          Text(S.upiScanHint, style: muted, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.rule),
              ),
              child: QrImageView(
                data: upi.uri,
                size: 196,
                backgroundColor: Colors.white,
                semanticsLabel: 'UPI QR code',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.upiId, style: muted),
                    SelectableText(
                      upi.vpa,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (upi.name.isNotEmpty) Text(upi.name, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => copyText(context, upi.vpa, S.upiIdCopied),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text(S.copy),
              ),
            ],
          ),
          if (upi.reference != null) ...[
            const SizedBox(height: 6),
            Text('${S.upiReference}: ${upi.reference}', style: muted),
          ],
        ],
      ),
    );
  }
}

/// "UPI reference / UTR (12 digits)" + Submit for verification. [onSubmit]
/// gets the digits; an [ApiException] it throws (`utr_already_used`,
/// `wrong_status`, …) is shown under the field.
class UtrForm extends StatefulWidget {
  const UtrForm({super.key, required this.onSubmit, this.submitLabel = S.submitForVerification});

  final Future<void> Function(String utr) onSubmit;
  final String submitLabel;

  /// Exactly [AppConfig.utrLength] digits.
  static bool isValidUtr(String v) => RegExp('^\\d{${AppConfig.utrLength}}\$').hasMatch(v.trim());

  @override
  State<UtrForm> createState() => _UtrFormState();
}

class _UtrFormState extends State<UtrForm> {
  final _form = GlobalKey<FormState>();
  final _utr = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _utr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_utr.text.trim());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _utr,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(AppConfig.utrLength),
            ],
            style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1.5),
            decoration: const InputDecoration(
              labelText: S.utrLabel,
              helperText: S.utrHint,
              helperMaxLines: 3,
              prefixIcon: Icon(Icons.receipt_long_outlined),
            ),
            validator: (v) => UtrForm.isValidUtr(v ?? '') ? null : S.utrInvalid,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}

/// "Payment under verification" (submitted), "Payment not verified: …"
/// (failed) or "Paid" — a tinted note for a UPI payment's state.
class PaymentStateNote extends StatelessWidget {
  const PaymentStateNote({super.key, required this.status, this.utr, this.rejectReason});

  final String status;
  final String? utr;
  final String? rejectReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (IconData icon, Color color, String title, String? body) = switch (status) {
      PaymentStatus.submitted => (
        Icons.hourglass_top_rounded,
        AppColors.warning,
        S.paymentUnderVerification,
        S.paymentUnderVerificationBody,
      ),
      PaymentStatus.failed => (
        Icons.error_outline_rounded,
        theme.colorScheme.error,
        S.paymentNotVerified(rejectReason),
        null,
      ),
      PaymentStatus.paid => (
        Icons.check_circle_rounded,
        AppColors.success,
        S.paidWaitingApproval,
        null,
      ),
      _ => (Icons.currency_rupee_rounded, AppColors.navy, S.awaitingPayment, null),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(color: color)),
                if (body != null) ...[
                  const SizedBox(height: 2),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
                if (utr != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    S.utrValue(utr!),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
