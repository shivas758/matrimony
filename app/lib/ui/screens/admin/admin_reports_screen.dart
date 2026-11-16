import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/moderation.dart';
import '../../../services/admin_service.dart';
import '../../../services/api_client.dart';
import '../../../services/link_launcher.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/reason_dialog.dart';
import '../profiles/profile_detail_screen.dart';

/// The three things an admin can do with an open report (SPEC §9.22 A).
enum ReportAction { dismiss, hideProfile, suspendAccount }

/// Admin → Reports (SPEC §9.22 A): profiles reported by agents and families.
/// An open report is dismissed, or its profile hidden, or the account behind
/// it suspended — each after a confirm with an optional note.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key, this.initialStatus = 'open'});

  /// `open`, `actioned`, `dismissed` or `all`.
  final String initialStatus;

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  static const _filters = [
    ('open', S.filterOpen),
    ('actioned', S.filterActioned),
    ('dismissed', S.filterDismissed),
    ('all', S.filterAll),
  ];

  late String _status = widget.initialStatus;
  List<AdminReport> _items = [];
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
      final items = await context.read<AdminService>().reports(status: status);
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

  Future<void> _call(String phone) async {
    final ok = await context.read<LinkLauncher>().launch(Uri.parse('tel:+91$phone'));
    if (!ok && mounted) showSnack(context, S.cannotCall, error: true);
  }

  Future<void> _openProfile(int id) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ProfileDetailScreen(profileId: id)));
    if (mounted) _load();
  }

  Future<void> _act(AdminReport r, ReportAction action) async {
    final (title, body, label, done) = switch (action) {
      ReportAction.dismiss => (
        S.dismissReportTitle,
        S.dismissReportBody,
        S.dismiss,
        S.reportDismissed,
      ),
      ReportAction.hideProfile => (
        S.hideProfileTitle,
        S.hideProfileBody,
        S.hideProfile,
        S.profileHidden,
      ),
      ReportAction.suspendAccount => (
        S.suspendAccountTitle,
        S.suspendAccountBody,
        S.suspendAccount,
        S.accountSuspended,
      ),
    };
    final note = await showDialog<String>(
      context: context,
      builder: (_) => ReasonDialog(
        title: title,
        body: body,
        label: S.noteOptionalLabel,
        confirmLabel: label,
        optional: true,
        destructive: action != ReportAction.dismiss,
      ),
    );
    if (note == null || !mounted) return;
    final admin = context.read<AdminService>();
    final n = note.isEmpty ? null : note;
    setState(() => _busyId = r.id);
    try {
      await switch (action) {
        ReportAction.dismiss => admin.dismissReport(r.id, note: n),
        ReportAction.hideProfile => admin.hideReportedProfile(r.id, note: n),
        ReportAction.suspendAccount => admin.suspendReportedAccount(r.id, note: n),
      };
      if (!mounted) return;
      showSnack(context, done);
      context.read<AuthState>().refreshNotifications();
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.reports)),
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
              icon: Icons.flag_outlined,
              title: _status == 'open' ? S.noOpenReports : S.noReportsInList,
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
          final r = _items[i];
          return ReportTile(
            report: r,
            busy: _busyId == r.id,
            onCall: _call,
            onOpenProfile: r.profile == null ? null : () => _openProfile(r.profile!.id),
            onAction: (a) => _act(r, a),
          );
        },
      ),
    );
  }
}

/// One report: the reason and details, the profile (tap to open), who
/// reported it, the family and the uploading agent, how many reports the
/// profile has, when — and the actions while it is open.
class ReportTile extends StatelessWidget {
  const ReportTile({
    super.key,
    required this.report,
    required this.busy,
    required this.onCall,
    required this.onAction,
    this.onOpenProfile,
  });

  final AdminReport report;
  final bool busy;
  final ValueChanged<String> onCall;
  final ValueChanged<ReportAction> onAction;

  /// Null when the profile was deleted.
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = report;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    final (String statusText, Color statusColor) = switch (r.status) {
      'actioned' => (
        r.action == 'account_suspended'
            ? S.actionAccountSuspended
            : r.action == 'profile_hidden'
            ? S.actionProfileHidden
            : S.statusActioned,
        theme.colorScheme.error,
      ),
      'dismissed' => (S.statusDismissed, theme.colorScheme.outline),
      _ => (S.statusOpen, AppColors.warning),
    };
    final profile = r.profile;
    final reporter = r.reporter;

    Widget person(IconData icon, String label, ReportParty p, {String? extra}) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  [
                    '$label:',
                    p.agentCode == null ? p.fullName : '${p.fullName} (${p.agentCode})',
                    ?extra,
                    if (p.status != null && p.status != 'active') '· ${p.status}',
                  ].join(' '),
                  style: theme.textTheme.bodyMedium,
                ),
                if (p.phone != null)
                  InkWell(
                    onTap: () => onCall(p.phone!),
                    child: Text(
                      '+91 ${p.phone}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.navyLight,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 20, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.reasonLabel,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              StatusChip(label: statusText, color: statusColor),
            ],
          ),
          if (r.details != null) ...[
            const SizedBox(height: 6),
            Text('"${r.details}"', style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 8),
          // The reported profile — tap to open it.
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onOpenProfile,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              decoration: BoxDecoration(
                color: AppColors.navyTint.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.badge_outlined, size: 18, color: AppColors.navy),
                  const SizedBox(width: 8),
                  Expanded(
                    child: profile == null
                        ? Text(S.profileDeletedLabel, style: muted)
                        : Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                profile.fullName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (profile.profileCode != null)
                                IdChip(code: profile.profileCode!, color: AppColors.goldDark),
                              if (profile.status != null)
                                StatusChip(
                                  label: profile.status!,
                                  color: StatusColors.forProfileStatus(
                                    profile.status!,
                                    theme.colorScheme,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  if (onOpenProfile != null)
                    Icon(Icons.chevron_right_rounded, color: theme.colorScheme.outline),
                ],
              ),
            ),
          ),
          if (reporter != null)
            person(
              Icons.flag_outlined,
              S.reportedBy,
              reporter,
              extra: '(${reporter.isCustomer ? S.reporterFamily : S.reporterAgent})',
            ),
          if (r.customer != null) person(Icons.family_restroom_rounded, S.familyLabel, r.customer!),
          if (r.agent != null) person(Icons.support_agent_rounded, S.uploadedByLabel, r.agent!),
          const SizedBox(height: 6),
          Text(
            [
              S.reportsOnProfile(r.reportsOnProfile),
              formatDateTime(r.createdAt),
            ].where((s) => s.isNotEmpty).join(' · '),
            style: muted?.copyWith(
              fontWeight: r.reportsOnProfile > 1 ? FontWeight.w700 : null,
              color: r.reportsOnProfile > 1 ? theme.colorScheme.error : null,
            ),
          ),
          if (!r.isOpen && r.handledAt != null)
            Text('${S.handledOn} ${formatDateTime(r.handledAt)}', style: muted),
          if (r.note != null) ...[
            const SizedBox(height: 4),
            Text('${S.noteLabel}: ${r.note}', style: theme.textTheme.bodySmall),
          ],
          if (r.isOpen) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Compact: the theme's buttons are full width.
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                  onPressed: busy ? null : () => onAction(ReportAction.dismiss),
                  child: const Text(S.dismiss),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: busy || profile == null
                      ? null
                      : () => onAction(ReportAction.hideProfile),
                  child: const Text(S.hideProfile),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    backgroundColor: theme.colorScheme.error,
                  ),
                  onPressed: busy || profile == null
                      ? null
                      : () => onAction(ReportAction.suspendAccount),
                  child: const Text(S.suspendAccount),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
