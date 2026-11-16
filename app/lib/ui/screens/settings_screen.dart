import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/master_data.dart';
import '../../models/payment.dart';
import '../../services/admin_service.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../state/auth_state.dart';
import '../../state/masters_state.dart';
import '../../state/store_config.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/agent_code_card.dart';
import '../widgets/common.dart';
import '../widgets/delete_account.dart';
import '../widgets/searchable_lists.dart';
import 'blocked_profiles_screen.dart';
import 'clients/client_widgets.dart' show confirmAction;
import 'community_payment_screen.dart';

/// My communities, requests to join more (beyond the free ones with a
/// one-time UPI fee, SPEC §9.20 C), my agent code, change password
/// (SPEC §5 screen 10, §9.18 G).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<MasterItem> _mine = [];
  List<CommunityRequest> _requests = [];
  MyCommunities? _info;
  bool _loading = true;
  String? _error;

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
    try {
      final result = await context.read<MyAccountService>().communities();
      if (mounted) {
        setState(() {
          _info = result;
          _mine = result.communities;
          _requests = result.requests;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestCommunity() async {
    final masters = context.read<MastersState>().data;
    final mineIds = _mine.map((c) => c.id).toSet();
    final pendingIds =
        _requests.where((r) => r.isPending).map((r) => r.communityId).toSet();
    final options = masters.communities
        .where((c) => !mineIds.contains(c.id) && !pendingIds.contains(c.id))
        .toList();

    if (options.isEmpty) {
      showSnack(context, 'No other communities available to request');
      return;
    }

    // A long list gets a search field (SPEC §9.23 E).
    final result = await showSinglePickerSheet(
      context,
      title: S.requestCommunity,
      note: S.requestCommunityNote,
      options: masterOptions(options),
    );
    final picked = result?.id;
    if (picked == null || !mounted) return;

    // Beyond the free limit the request carries a one-time fee — say so
    // before sending (the server decides; admins never pay). A Play Store
    // build cannot take the payment (SPEC §9.20 G): the admin adds it.
    final info = _info;
    final playStore = StoreConfig.isPlayStore(context);
    String? feeHeadline;
    if (info != null && info.nextIsPaid && !context.read<AuthState>().isAdmin) {
      if (playStore) {
        await _showPlayNoPayment();
        return;
      }
      feeHeadline = S.extraCommunityFee(info.nextNumber, info.extraFeeInr);
      final ok = await confirmAction(
        context,
        title: feeHeadline,
        body: S.extraCommunityFeeBody(info.freeLimit),
        confirmLabel: S.continueToPay,
      );
      if (!ok || !mounted) return;
    }

    try {
      final request = await context.read<MyAccountService>().requestCommunity(picked);
      if (!mounted) return;
      if (request.hasFee && playStore) {
        // The server asked for a fee this build cannot take.
        await _showPlayNoPayment();
        _load();
      } else if (request.hasFee && request.payment != null) {
        await _openPayment(
          request,
          headline: feeHeadline ??
              S.extraCommunityFee(info?.nextNumber ?? _mine.length + 1, request.feeInr),
        );
      } else {
        showSnack(context, S.requestSent);
        _load();
      }
    } on ApiException catch (e) {
      // payment_provider_error: "UPI payments are not set up yet".
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  /// Play Store build: extra communities cannot be paid in the app.
  Future<void> _showPlayNoPayment() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: const Text(S.playNoExtraCommunityPayment),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.ok)),
          ],
        ),
      );

  /// The UPI pay + UTR step of a fee request; the list reloads afterwards.
  Future<void> _openPayment(CommunityRequest request, {String? headline}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CommunityPaymentScreen(request: request, headline: headline),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.changePassword),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: current,
                obscureText: true,
                decoration: const InputDecoration(labelText: S.currentPassword),
                validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: next,
                obscureText: true,
                decoration: const InputDecoration(labelText: S.newPassword),
                validator: (v) => (v ?? '').length < 6 ? 'Use at least 6 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: S.confirmPassword),
                validator: (v) => v != next.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text(S.save),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    try {
      await context.read<AuthService>().changePassword(
            current: current.text,
            next: next.text,
          );
      if (mounted) showSnack(context, 'Password changed');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  /// Edits one directory field (city or agency name) via PATCH /my/account
  /// (SPEC §9.6). An empty value clears it.
  Future<void> _editDirectoryField({required bool isCity}) async {
    final agent = context.read<AuthState>().agent;
    final ctl = TextEditingController(text: (isCity ? agent?.city : agent?.agencyName) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCity ? S.myCity : S.agencyName),
        content: TextFormField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => Navigator.pop(ctx, true),
          decoration: InputDecoration(
            labelText: isCity ? S.myCity : S.agencyName,
            hintText: isCity ? S.myCityHint : null,
            helperText: S.agentDirectoryNote,
            helperMaxLines: 3,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.save)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final value = ctl.text.trim();
    try {
      final updated = await context.read<MyAccountService>().updateAccount(
            city: isCity ? value : null,
            agencyName: isCity ? null : value,
          );
      if (!mounted) return;
      context.read<AuthState>().updateAgent(updated);
      showSnack(context, S.accountUpdated);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<AuthState>().agent;
    final theme = Theme.of(context);
    final playStore = StoreConfig.isPlayStore(context);
    final pending = _requests.where((r) => r.isPending).toList();
    final decided = _requests.where((r) => !r.isPending).toList();

    return Scaffold(
      appBar: AppBar(title: const Text(S.settings)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (_error != null) ...[
              ErrorState(message: _error!, onRetry: _load),
              const SizedBox(height: 24),
            ],
            const SectionHeader(S.myCommunities),
            if (_loading && _mine.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final c in _mine) Chip(label: Text(c.name))],
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _requestCommunity,
              icon: const Icon(Icons.add_rounded),
              label: const Text(S.requestCommunity),
            ),
            if (_info != null && !(agent?.isAdmin ?? false)) ...[
              const SizedBox(height: 8),
              Text(
                playStore
                    ? S.playFreeCommunitiesNote(_info!.freeLimit)
                    : S.freeCommunitiesNote(_info!.freeLimit, _info!.extraFeeInr),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 24),
              const SectionHeader(S.pendingRequests),
              for (final r in pending)
                _PendingRequestTile(
                  request: r,
                  // No UPI step in a Play Store build — the state only.
                  onPay: playStore ? null : () => _openPayment(r),
                ),
            ],
            if (decided.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionHeader(S.pastRequests),
              for (final r in decided)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    r.status == 'approved' ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: StatusColors.forRequestStatus(r.status, theme.colorScheme),
                  ),
                  title: Text(r.communityName),
                  subtitle: Text(
                    [
                      r.status,
                      if (r.hasFee) S.feeLabel(r.feeInr),
                      if (r.feePaymentStatus == PaymentStatus.refundDue) S.refundDue,
                    ].join(' · '),
                  ),
                ),
            ],
            const SizedBox(height: 32),
            // Directory details Wedbook Matrimony customers see when choosing an agent.
            const SectionHeader(S.agentDirectory),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.location_city_rounded),
              title: const Text(S.myCity),
              subtitle: Text(
                (agent?.city ?? '').isNotEmpty ? agent!.city! : S.notSet,
                style: (agent?.city ?? '').isEmpty
                    ? TextStyle(color: theme.colorScheme.outline, fontStyle: FontStyle.italic)
                    : null,
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editDirectoryField(isCity: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_rounded),
              title: const Text(S.agencyName),
              subtitle: Text(
                (agent?.agencyName ?? '').isNotEmpty ? agent!.agencyName! : S.notSet,
                style: (agent?.agencyName ?? '').isEmpty
                    ? TextStyle(color: theme.colorScheme.outline, fontStyle: FontStyle.italic)
                    : null,
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editDirectoryField(isCity: false),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
              child: Text(
                S.agentDirectoryNote,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
            const SizedBox(height: 32),
            const SectionHeader('Account'),
            // The permanent agent code (SPEC §9.18 B) — tap to copy.
            if (agent != null && agent.hasAgentCode) ...[
              AgentCodeCard(code: agent.agentCode!, stateName: agent.state?.name),
              const SizedBox(height: 8),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_rounded),
              title: Text(agent?.fullName ?? ''),
              subtitle: Text('+91 ${agent?.phone ?? ''}'),
            ),
            // SPEC §9.23 A / F: approved, or how many live clients so far.
            // Nothing against a server that does not send approvals.
            if (agent != null && agent.knowsApproval)
              ListTile(
                key: const ValueKey('approval-status'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  agent.isApproved ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                  color: agent.isApproved ? AppColors.success : AppColors.goldDark,
                ),
                title: Text(
                  agent.isApproved
                      ? S.approvedAgent
                      : S.clientsProgress(agent.liveClientCount, agent.approvalClients),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: agent.isApproved ? AppColors.success : null,
                  ),
                ),
                subtitle: Text(
                  agent.isApproved
                      ? S.approvedAgentHint
                      : S.approvalProgressHint(agent.approvalClients),
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_reset_rounded),
              title: const Text(S.changePassword),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _changePassword,
            ),
            // SPEC §9.22 B: profiles I hid from myself.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.block_rounded),
              title: const Text(S.blockedProfiles),
              subtitle: const Text(S.blockedProfilesSubtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BlockedProfilesScreen()),
              ),
            ),
            // SPEC §9.20 F (Google Play): the public deletion page.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.person_remove_outlined, color: theme.colorScheme.error),
              title: const Text(S.deleteMyAccount),
              subtitle: const Text(S.deleteMyAccountSubtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => confirmDeleteAccount(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pending community request: free ("waiting for admin approval"), or
/// with its fee payment's state — not paid yet / under verification / not
/// verified (with the reason) — and the button to pay or submit again.
class _PendingRequestTile extends StatelessWidget {
  const _PendingRequestTile({required this.request, this.onPay});

  final CommunityRequest request;

  /// Null in a Play Store build: no way to pay in the app.
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;
    final payment = r.payment;
    final status = r.feePaymentStatus;

    final (IconData icon, Color color, String subtitle) = !r.hasFee
        ? (Icons.hourglass_top_rounded, AppColors.warning, S.waitingAdminApproval)
        : switch (status) {
            PaymentStatus.submitted => (
                Icons.hourglass_top_rounded,
                AppColors.warning,
                S.paymentUnderVerification,
              ),
            PaymentStatus.failed => (
                Icons.error_outline_rounded,
                theme.colorScheme.error,
                S.paymentNotVerified(payment?.rejectReason),
              ),
            PaymentStatus.paid => (
                Icons.check_circle_outline_rounded,
                AppColors.success,
                S.paidWaitingApproval,
              ),
            _ => (
                Icons.currency_rupee_rounded,
                AppColors.navy,
                '${S.feeLabel(r.feeInr)} · ${onPay == null ? S.onlinePaymentUnavailable : S.notPaidYet}',
              ),
          };
    final canPay = onPay != null && r.needsPayment && payment?.upi != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 14),
            child: Icon(icon, color: color),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.communityName, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: status == PaymentStatus.failed ? color : null,
                  ),
                ),
                if (r.hasFee && r.feeUtr != null && status != PaymentStatus.created)
                  Text(
                    S.utrValue(r.feeUtr!),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                if (canPay) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: onPay,
                    icon: const Icon(Icons.currency_rupee_rounded, size: 18),
                    label: Text(
                      status == PaymentStatus.failed ? S.submitAgain : S.payAmount(r.feeInr),
                    ),
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
