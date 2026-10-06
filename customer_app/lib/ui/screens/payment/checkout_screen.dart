import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/payment.dart';
import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../services/payment_service.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// The registration-fee checkout for one profile (SPEC §9.12). This app
/// version completes only the server's `mock` provider: amount, what it is
/// for, "Test mode — no money is charged", *Pay* and *Simulate failure*.
/// Any other provider shows "Online payment is coming soon" and never starts
/// an order. Pops `true` once the profile is paid.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.profileId, required this.profileName});

  final int profileId;
  final String profileName;

  /// Opens the checkout; resolves to true when the profile got paid.
  static Future<bool> open(BuildContext context, {required int profileId, required String profileName}) async {
    final paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CheckoutScreen(profileId: profileId, profileName: profileName)),
    );
    return paid == true;
  }

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _busy = false;
  PaymentResult? _result;
  String? _error;

  /// The amount from the last order, once one exists (else the account's fee).
  num? _amount;

  Future<void> _pay({bool simulateFailure = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context
          .read<PaymentService>()
          .payMock(widget.profileId, simulateFailure: simulateFailure);
      if (!mounted) return;
      setState(() {
        _result = result;
        _amount = result.payment.amountInr;
      });
      final customer = result.customer;
      if (customer != null) {
        context.read<AuthState>().setCustomer(customer);
      } else {
        await context.read<AuthState>().refresh();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'already_paid') {
        // Paid meanwhile (another device, a retry) — treat it as done.
        await context.read<AuthState>().refresh();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = context.watch<AuthState>().customer;
    final provider = customer?.paymentProvider ?? 'mock';
    final fee = _amount ?? customer?.profileFeeInr;
    final result = _result;
    final paid = result?.payment.isPaid ?? false;

    // System back returns whether it got paid, and waits for a call in flight.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        Navigator.of(context).pop(paid);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(S.checkoutTitle),
          leading: BackButton(onPressed: _busy ? null : () => Navigator.of(context).pop(paid)),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              if (paid)
                _SuccessView(
                  visibility: result!.profile?.visibility,
                  onDone: () => Navigator.of(context).pop(true),
                )
              else ...[
                _AmountCard(fee: fee, profileName: widget.profileName),
                const SizedBox(height: 16),
                if (!PaymentService.supportsInApp(provider))
                  const NoticeCard(
                    icon: Icons.schedule_rounded,
                    title: S.paymentComingSoon,
                    tint: AppColors.warning,
                  )
                else ...[
                  const NoticeCard(
                    icon: Icons.science_outlined,
                    title: S.testModeNoCharge,
                    tint: AppColors.success,
                  ),
                  if (result != null && result.payment.isFailed) ...[
                    const SizedBox(height: 16),
                    NoticeCard(
                      icon: Icons.error_outline_rounded,
                      title: S.paymentFailedTitle,
                      body: S.paymentFailedBody,
                      tint: Theme.of(context).colorScheme.error,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _pay(),
                    icon: _busy ? const ButtonSpinner() : const Icon(Icons.lock_rounded),
                    label: Text(result != null && result.payment.isFailed ? S.tryAgain : S.payFee(fee)),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _pay(simulateFailure: true),
                    child: const Text(S.simulateFailure),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Amount, what it is for, and the one-line explanation.
class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.fee, required this.profileName});

  final num? fee;
  final String profileName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.amount.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.roseLight,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            S.feeLabel(fee),
            style: const TextStyle(
              fontFamily: AppTheme.displayFont,
              fontSize: 40,
              fontWeight: FontWeight.w600,
              fontVariations: [FontVariation('wght', 600)],
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            profileName.isEmpty ? S.checkoutTitle : S.checkoutFor(profileName),
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            S.checkoutWhat,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8), height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// "Payment successful" + the profile's new state.
class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.visibility, required this.onDone});

  final ProfileVisibility? visibility;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = visibility == ProfileVisibility.live;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.check_circle_rounded, size: 52, color: AppColors.success),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          S.paymentSuccessTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        NoticeCard(
          icon: live ? Icons.visibility_rounded : Icons.hourglass_top_rounded,
          title: live ? S.chipLive : S.chipWaitingForAgent,
          body: live ? S.paymentLiveNow : S.paymentAwaitingApproval,
          tint: live ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(height: 28),
        FilledButton(onPressed: onDone, child: const Text(S.done)),
      ],
    );
  }
}
