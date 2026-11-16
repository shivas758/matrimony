import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/payment.dart';
import '../../../services/admin_service.dart';
import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/reason_dialog.dart';
import '../clients/client_widgets.dart' show confirmAction;

/// Payments to verify (SPEC §9.20 D): UPI payments whose payer entered a
/// UTR. The admin compares the UTR and amount with their bank / UPI app,
/// then approves (profile fee settled / community added) or rejects with a
/// reason the payer sees.
class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key, this.initialStatus = PaymentStatus.submitted});

  /// `submitted` (to verify), `paid`, `failed` or `all`.
  final String initialStatus;

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  static const _filters = [
    (PaymentStatus.submitted, S.filterToVerify),
    (PaymentStatus.paid, S.filterPaid),
    (PaymentStatus.failed, S.filterRejected),
    ('all', S.filterAll),
  ];

  late String _status = widget.initialStatus;
  List<AdminPayment> _items = [];
  bool _loading = true;
  String? _error;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final status = _status;
    try {
      final items = await context.read<AdminService>().payments(status: status);
      if (mounted && status == _status) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setFilter(String status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _items = [];
    });
    _load();
  }

  Future<void> _run(AdminPayment p, Future<void> Function() action, String done) async {
    setState(() => _busyId = p.id);
    try {
      await action();
      if (!mounted) return;
      showSnack(context, done);
      context.read<AuthState>().refreshNotifications();
      await _load();
    } on ApiException catch (e) {
      // wrong_status: decided meanwhile (another admin) — show and refresh.
      if (!mounted) return;
      showSnack(context, e.message, error: true);
      if (e.code == 'wrong_status') _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _approve(AdminPayment p) async {
    final ok = await confirmAction(
      context,
      title: S.approvePaymentTitle,
      body: S.approvePaymentBody(p.amountInr, p.utr),
      confirmLabel: S.approve,
    );
    if (!ok || !mounted) return;
    final admin = context.read<AdminService>();
    await _run(p, () => admin.approvePayment(p.id), S.paymentApproved);
  }

  Future<void> _reject(AdminPayment p) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const ReasonDialog(
        title: S.rejectPaymentTitle,
        body: S.rejectPaymentBody,
        hint: S.rejectReasonHint,
      ),
    );
    if (reason == null || !mounted) return;
    final admin = context.read<AdminService>();
    await _run(p, () => admin.rejectPayment(p.id, reason), S.paymentRejected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.paymentsToVerify)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                for (final (value, label) in _filters) ...[
                  ChoiceChip(
                    label: Text(label),
                    selected: _status == value,
                    onSelected: (_) => _setFilter(value),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) return ErrorState(message: _error!, onRetry: _load);
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.14),
            EmptyState(
              icon: Icons.currency_rupee_rounded,
              title: _status == PaymentStatus.submitted ? S.noPaymentsToVerify : S.noPayments,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final p = _items[i];
          return AdminPaymentTile(
            payment: p,
            busy: _busyId == p.id,
            onApprove: () => _approve(p),
            onReject: () => _reject(p),
          );
        },
      ),
    );
  }
}

/// One payment: amount, the UTR (large, tap to copy), reference, who paid
/// and for what, when; Approve / Reject while it waits for verification.
class AdminPaymentTile extends StatelessWidget {
  const AdminPaymentTile({
    super.key,
    required this.payment,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final AdminPayment payment;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  static (String, Color) statusLabel(String status, ColorScheme scheme) => switch (status) {
    PaymentStatus.submitted => (S.statusToVerify, AppColors.warning),
    PaymentStatus.paid => (S.statusPaid, AppColors.success),
    PaymentStatus.failed => (S.statusRejected, scheme.error),
    PaymentStatus.refundDue => (S.statusRefundDue, scheme.error),
    PaymentStatus.created => (S.statusAwaitingPayment, scheme.outline),
    _ => (status, scheme.outline),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = payment;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    final (statusText, statusColor) = statusLabel(p.status, theme.colorScheme);

    final who = <String>[
      if (p.customer != null)
        [
          p.customer!.fullName,
          if (p.customer!.phone != null) '+91 ${p.customer!.phone}',
        ].join(' · '),
      if (p.agent != null)
        [
          p.agent!.agentCode == null
              ? p.agent!.fullName
              : '${p.agent!.fullName} (${p.agent!.agentCode})',
          if (p.agent!.phone != null) '+91 ${p.agent!.phone}',
        ].join(' · '),
    ];
    final what = <String>[
      if (p.profile != null)
        [
          '${S.profilePrefix}${p.profile!.fullName}',
          if (p.profile!.profileCode != null) S.idLabel(p.profile!.profileCode!),
        ].join(' · '),
      if (p.community != null) '${S.forCommunity}: ${p.community!.name}',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.rupees(p.amountInr),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      p.isExtraCommunity ? S.purposeExtraCommunity : S.purposeRegistration,
                      style: muted,
                    ),
                  ],
                ),
              ),
              StatusChip(label: statusText, color: statusColor),
            ],
          ),
          if (p.utr != null) ...[
            const SizedBox(height: 10),
            Material(
              color: AppColors.goldPale,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => copyText(context, p.utr!, S.utrCopied),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: [
                      Text(S.utr, style: muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SelectableText(
                          p.utr!,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: AppColors.navyDeep,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: S.copy,
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        onPressed: () => copyText(context, p.utr!, S.utrCopied),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (p.reference != null) Text('${S.upiReference}: ${p.reference}', style: muted),
          if (who.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.person_outline_rounded, size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${S.paidBy}: ${who.join(' · ')}', style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ],
          for (final line in what) ...[
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  p.isExtraCommunity ? Icons.groups_rounded : Icons.badge_outlined,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(line, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ],
          if (p.submittedAt != null) ...[
            const SizedBox(height: 4),
            Text('${S.submittedOn} ${formatDateTime(p.submittedAt)}', style: muted),
          ],
          if (p.isPaid && p.verifiedAt != null)
            Text('${S.verifiedOn} ${formatDateTime(p.verifiedAt)}', style: muted),
          if (p.rejectReason != null && !p.isPaid) ...[
            const SizedBox(height: 4),
            Text(
              '${S.rejectReason}: ${p.rejectReason}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          if (p.isSubmitted) ...[
            const SizedBox(height: 10),
            LockNote(text: S.paymentsCheckHint, icon: Icons.info_outline_rounded),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: busy ? null : onReject,
                    child: const Text(S.reject),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: busy ? null : onApprove,
                    child: const Text(S.approve),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
