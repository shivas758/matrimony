import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../models/payment.dart';
import '../../../services/api_client.dart';
import '../../../services/payment_service.dart';
import '../../../services/upi_launcher.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Where a UPI registration fee stands on the checkout page.
enum UpiPhase {
  /// Fetching the profile's open UPI payment.
  loading,

  /// That failed — [UpiCheckout] shows the reason and *Try again*.
  error,

  /// Step 1 pay (UPI app / QR / UPI ID) and step 2 the UTR. A payment an
  /// admin did not verify is back here, with the reason.
  ready,

  /// The UTR is in; an admin verifies it ("Payment under verification").
  submitted,
}

/// The UPI part of the checkout (SPEC §9.20 B / E), shown by the checkout
/// screen when the server's provider is `upi`:
/// 1. *Pay ₹150 with UPI app* — opens the payment's `upi://pay` link with a
///    UPI app ([UpiLauncher]); the same link as a QR code (pay from another
///    phone) and the UPI ID with *Copy*.
/// 2. The 12-digit UTR → *Submit for verification* → "Payment under
///    verification". A rejected payment shows the admin's reason and takes a
///    corrected UTR (same payment) — or they pay again.
///
/// Never calls `/confirm`. `already_paid` / `payment_provider_changed` go to
/// [onHandOff] (the checkout screen closes as paid / follows the new provider).
class UpiCheckout extends StatefulWidget {
  const UpiCheckout({
    super.key,
    required this.profileId,
    required this.fee,
    required this.onPaid,
    required this.onHandOff,
  });

  final int profileId;

  /// The registration fee in rupees (the payment's own amount wins).
  final num? fee;

  /// The payment came back verified — the checkout shows its success view.
  final Future<void> Function(PaymentResult result) onPaid;

  /// `already_paid` and `payment_provider_changed`: the checkout screen's own
  /// handling.
  final Future<void> Function(ApiException e) onHandOff;

  @override
  State<UpiCheckout> createState() => _UpiCheckoutState();
}

class _UpiCheckoutState extends State<UpiCheckout> {
  final _utr = TextEditingController();
  late UpiPhase _phase;
  Payment? _payment;

  /// What went wrong loading the payment (phase [UpiPhase.error]).
  String? _loadError;

  /// A submit that failed for another reason than the UTR itself.
  String? _error;
  String? _utrError;

  /// The UTR just submitted (before the account refresh carries it).
  String? _submittedUtr;
  bool _busy = false;
  bool _checking = false;

  /// No UPI app could open the link — point to the QR / UPI ID.
  bool _noApp = false;

  @override
  void initState() {
    super.initState();
    // Already being verified (my profile row says so) → show that straight
    // away; the load below confirms it (or finds it was decided meanwhile).
    final row = context.read<AuthState>().customer?.myProfile(widget.profileId);
    _phase = row?.payment?.isSubmitted == true ? UpiPhase.submitted : UpiPhase.loading;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _utr.dispose();
    super.dispose();
  }

  /// The profile's open UPI payment (created / failed — reused by the
  /// server), or "under review" / "already paid".
  Future<void> _load() async {
    try {
      final payment = await context.read<PaymentService>().openUpi(widget.profileId);
      if (!mounted) return;
      if (payment.isPaid) {
        await widget.onHandOff(ApiException('already_paid', S.errAlreadyPaid, status: 409));
        return;
      }
      setState(() {
        _payment = payment;
        _loadError = null;
        _phase = payment.isSubmitted ? UpiPhase.submitted : UpiPhase.ready;
        // Not verified: offer the UTR they typed, to correct it.
        if (payment.isFailed && _utr.text.isEmpty && payment.utr != null) _utr.text = payment.utr!;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'payment_under_review':
          setState(() => _phase = UpiPhase.submitted);
          // My profile row carries the UTR being verified.
          await context.read<AuthState>().refresh();
        case 'already_paid':
        case 'payment_provider_changed':
          await widget.onHandOff(e);
        default:
          if (_phase == UpiPhase.submitted) {
            showSnack(context, friendlyMessage(e), error: true);
          } else {
            setState(() {
              _phase = UpiPhase.error;
              _loadError = friendlyMessage(e);
            });
          }
      }
    }
  }

  Future<void> _retry() async {
    setState(() {
      _phase = UpiPhase.loading;
      _loadError = null;
    });
    await _load();
  }

  Future<void> _checkStatus() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await _load();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openUpiApp(UpiDetails upi) async {
    final opened = await context.read<UpiLauncher>().open(upi.uri);
    if (mounted) setState(() => _noApp = !opened);
  }

  Future<void> _submit() async {
    final payment = _payment;
    if (payment == null || _busy) return;
    final utr = PaymentService.normalizeUtr(_utr.text);
    if (!PaymentService.isValidUtr(utr)) {
      setState(() => _utrError = S.utrInvalid);
      return;
    }
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthState>();
    setState(() {
      _busy = true;
      _utrError = null;
      _error = null;
    });
    try {
      final result = await context.read<PaymentService>().submitUtr(payment.id, utr);
      if (!mounted) return;
      if (result.payment.isPaid) {
        await widget.onPaid(result);
        return;
      }
      setState(() {
        _submittedUtr = result.payment.utr ?? utr;
        if (result.payment.isSubmitted) _phase = UpiPhase.submitted;
      });
      final customer = result.customer;
      if (customer != null) {
        auth.setCustomer(customer);
      } else {
        await auth.refresh();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'utr_already_used':
          setState(() => _utrError = S.errUtrUsed);
        case 'validation_failed':
          setState(() => _utrError = e.fieldErrors?['utr'] ?? S.utrInvalid);
        case 'payment_under_review':
          setState(() => _phase = UpiPhase.submitted);
          await auth.refresh();
        case 'wrong_status':
          // Submitted / decided meanwhile — show where it stands now.
          await _load();
        case 'already_paid':
        case 'payment_provider_changed':
          await widget.onHandOff(e);
        default:
          setState(() => _error = friendlyMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = context.watch<AuthState>().customer?.myProfile(widget.profileId);
    return switch (_phase) {
      UpiPhase.loading => const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      UpiPhase.error => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ErrorBanner(message: _loadError ?? S.somethingWrong),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(S.tryAgain),
            ),
          ],
        ),
      UpiPhase.submitted => UpiUnderReviewCard(
          utr: _submittedUtr ?? _payment?.utr ?? row?.payment?.utr,
          action: OutlinedButton.icon(
            onPressed: _checking ? null : _checkStatus,
            icon: _checking ? const ButtonSpinner(color: AppColors.wine) : const Icon(Icons.refresh_rounded),
            label: const Text(S.checkStatus),
          ),
        ),
      UpiPhase.ready => _ready(context, _payment!),
    };
  }

  Widget _ready(BuildContext context, Payment payment) {
    final theme = Theme.of(context);
    final upi = payment.upi!;
    final amount = upi.amountInr ?? payment.amountInr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (payment.isFailed) ...[
          NoticeCard(
            icon: Icons.error_outline_rounded,
            title: S.upiNotVerified(payment.rejectReason),
            body: S.upiNotVerifiedBody,
            tint: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
        ],
        _StepTitle(number: 1, title: S.upiStep1),
        FilledButton.icon(
          onPressed: _busy ? null : () => _openUpiApp(upi),
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: Text(S.payWithUpiApp(amount)),
        ),
        if (_noApp) ...[
          const SizedBox(height: 12),
          const NoticeCard(
            icon: Icons.info_outline_rounded,
            title: S.upiNoAppTitle,
            body: S.upiNoAppBody,
            tint: AppColors.warning,
          ),
        ],
        const SizedBox(height: 16),
        UpiPayeeCard(upi: upi, amount: amount),
        const SizedBox(height: 24),
        _StepTitle(number: 2, title: S.upiStep2),
        Text(
          S.upiStep2Body,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _utr,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          onChanged: (_) {
            if (_utrError != null) setState(() => _utrError = null);
          },
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: S.utrLabel,
            helperText: S.utrHelper,
            helperMaxLines: 2,
            errorText: _utrError,
            errorMaxLines: 3,
            prefixIcon: const Icon(Icons.receipt_long_outlined),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(message: _error!),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy ? const ButtonSpinner() : const Icon(Icons.verified_outlined),
          label: const Text(S.submitForVerification),
        ),
      ],
    );
  }
}

/// "1  Pay by UPI" — a numbered step heading.
class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(color: AppColors.goldLight, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.wine)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.wine),
            ),
          ),
        ],
      ),
    );
  }
}

/// The QR code of the payment link (pay from another phone) and the payee's
/// UPI ID + name with *Copy* (pay by typing the ID).
class UpiPayeeCard extends StatelessWidget {
  const UpiPayeeCard({super.key, required this.upi, this.amount});

  final UpiDetails upi;
  final num? amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.rule),
              ),
              child: UpiQrCode(data: upi.uri),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            S.upiScanCaption,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.upiId,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SelectableText(
                      upi.vpa,
                      style: theme.textTheme.titleMedium?.copyWith(color: AppColors.wine, fontWeight: FontWeight.w700),
                    ),
                    if (upi.name != null)
                      Text(
                        S.upiPayTo(upi.name!),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
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
          if (amount != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                S.upiAmountNote(amount),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The QR code of a `upi://pay` link — any UPI app's scanner pays it.
class UpiQrCode extends StatelessWidget {
  const UpiQrCode({super.key, required this.data, this.size = 200});

  /// The `upi://pay?…` link.
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => QrImageView(
        data: data,
        size: size,
        backgroundColor: Colors.white,
        semanticsLabel: S.upiScanCaption,
        errorStateBuilder: (_, _) => SizedBox(
          width: size,
          height: size,
          child: const Center(child: Icon(Icons.qr_code_2_rounded, size: 64, color: AppColors.muted)),
        ),
      );
}

/// "Payment under verification" + the UTR being checked — the checkout's
/// submitted state, and the same card on My profile.
class UpiUnderReviewCard extends StatelessWidget {
  const UpiUnderReviewCard({super.key, this.utr, this.action});

  final String? utr;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NoticeCard(
      icon: Icons.hourglass_top_rounded,
      title: S.upiUnderReviewTitle,
      body: S.upiUnderReviewBody,
      tint: AppColors.warning,
      action: action,
      child: utr == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 50),
              child: Text(
                S.utrLine(utr!),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.4),
              ),
            ),
    );
  }
}
