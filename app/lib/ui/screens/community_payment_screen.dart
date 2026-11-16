import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/payment.dart';
import '../../services/admin_service.dart';
import '../../state/store_config.dart';
import '../strings.dart';
import '../widgets/common.dart';
import '../widgets/upi_payment.dart';

/// The UPI step of a paid community request (SPEC §9.20 C / E): pay with a
/// UPI app or the QR code, then enter the 12-digit UTR for an admin to
/// verify. A rejected payment shows the reason and takes a corrected UTR on
/// the same payment. Pops `true` when a UTR was submitted here.
class CommunityPaymentScreen extends StatefulWidget {
  const CommunityPaymentScreen({super.key, required this.request, this.headline});

  final CommunityRequest request;

  /// "This is your 4th community: one-time fee ₹1000" right after sending.
  final String? headline;

  @override
  State<CommunityPaymentScreen> createState() => _CommunityPaymentScreenState();
}

class _CommunityPaymentScreenState extends State<CommunityPaymentScreen> {
  late UpiPayment? _payment = widget.request.payment;
  bool _submitted = false;

  Future<void> _submit(String utr) async {
    final payment = _payment!;
    final updated = await context.read<MyAccountService>().submitPayment(payment.id, utr);
    if (!mounted) return;
    setState(() {
      _submitted = true;
      _payment =
          updated ??
          UpiPayment(
            id: payment.id,
            status: PaymentStatus.submitted,
            utr: utr,
            submittedAt: DateTime.now(),
            upi: payment.upi,
          );
    });
    showSnack(context, S.paymentSubmitted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.request;
    final payment = _payment;
    final upi = payment?.upi;
    // Never a UPI step in a Play Store build (SPEC §9.20 G).
    final playStore = StoreConfig.isPlayStore(context);

    return Scaffold(
      appBar: AppBar(title: const Text(S.payCommunityFee)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (widget.headline != null) ...[
              Text(
                widget.headline!,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
            ],
            if (playStore)
              const LockNote(text: S.playNoExtraCommunityPayment, title: S.onlinePaymentUnavailable)
            else if (payment == null)
              const ErrorState(message: S.somethingWrong)
            else if (payment.isSubmitted || payment.isPaid) ...[
              PaymentStateNote(status: payment.status, utr: payment.utr),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_submitted),
                child: const Text(S.done),
              ),
            ] else ...[
              if (payment.isFailed) ...[
                PaymentStateNote(
                  status: payment.status,
                  utr: payment.utr,
                  rejectReason: payment.rejectReason,
                ),
                const SizedBox(height: 14),
              ],
              if (upi != null)
                UpiPayCard(upi: upi, title: S.communityFeeFor(r.communityName))
              else
                const ErrorState(message: S.somethingWrong),
              const SizedBox(height: 20),
              UtrForm(onSubmit: _submit),
            ],
          ],
        ),
      ),
    );
  }
}
