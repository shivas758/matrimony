import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/publish.dart';
import '../../../services/api_client.dart';
import '../../../services/payment_service.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// The gift-code field + *Apply* (SPEC §9.23 B): an agent's free code
/// instead of the ₹150 fee. Applying it links me to that agent (if I have
/// none), approves me and publishes [profileId] at once. The code goes as
/// typed (trimmed) — the server ignores case, spaces, dashes and the `WB`
/// prefix. A refused code shows the server's own sentence under the field.
/// Works in the Play build too (no money involved). Used on the publish
/// screen and in Get started.
class GiftCodeForm extends StatefulWidget {
  const GiftCodeForm({super.key, required this.profileId, this.onRedeemed, this.primary = false});

  final int profileId;

  /// After a successful redeem (the account is already updated).
  final ValueChanged<GiftCodeResult>? onRedeemed;

  /// A filled *Apply* button (the main action) instead of an outlined one.
  final bool primary;

  @override
  State<GiftCodeForm> createState() => _GiftCodeFormState();
}

class _GiftCodeFormState extends State<GiftCodeForm> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_busy) return;
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = S.giftCodeEmpty);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthState>();
    // The step this form sits in is replaced once the account says "paid".
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await context.read<PaymentService>().redeemGiftCode(widget.profileId, code);
      auth.setCustomer(result.customer);
      // The account as the server sees it now (profiles[], unlock, agent).
      await auth.refresh();
      widget.onRedeemed?.call(result);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(S.giftCodeApplied)));
      if (mounted) _code.clear();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = giftCodeMessage(e));
      // Paid meanwhile / a UPI fee being verified: the screen should follow.
      if (e.code == 'already_paid' || e.code == 'payment_under_review') await auth.refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The theme's buttons are full width; this one sits beside the field.
    const size = Size(96, 50);
    final button = widget.primary
        ? FilledButton(
            style: FilledButton.styleFrom(minimumSize: size, padding: const EdgeInsets.symmetric(horizontal: 16)),
            onPressed: _busy ? null : _apply,
            child: _busy ? const ButtonSpinner() : const Text(S.giftCodeApply),
          )
        : OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: size, padding: const EdgeInsets.symmetric(horizontal: 16)),
            onPressed: _busy ? null : _apply,
            child: _busy ? const ButtonSpinner(color: AppColors.wine) : const Text(S.giftCodeApply),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('gift-code-field'),
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z \-]')),
              LengthLimitingTextInputFormatter(16),
            ],
            onSubmitted: (_) => _apply(),
            decoration: InputDecoration(
              labelText: S.giftCodeLabel,
              hintText: S.giftCodeHint,
              prefixIcon: const Icon(Icons.card_giftcard_rounded),
              errorText: _error,
              errorMaxLines: 4,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: button,
        ),
      ],
    );
  }
}
