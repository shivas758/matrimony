import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/gift_code.dart';
import '../../services/admin_service.dart';
import '../../services/api_client.dart';
import '../../services/link_launcher.dart';
import '../../state/auth_state.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// My gift codes (SPEC §9.23 B / F): how many are unused and used; each
/// unused code with Copy and Share (WhatsApp, the server's `share_text`);
/// each used one with the family's name and the date. Opened from More →
/// Gift codes, the "Not approved yet" banner and a `gift_code_used`
/// notification.
class GiftCodesScreen extends StatefulWidget {
  const GiftCodesScreen({super.key});

  @override
  State<GiftCodesScreen> createState() => _GiftCodesScreenState();
}

class _GiftCodesScreenState extends State<GiftCodesScreen> {
  GiftCodeList? _data;
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
      final data = await context.read<MyAccountService>().giftCodes();
      if (!mounted) return;
      setState(() => _data = data);
      // The counts on /auth/me (More, client detail) follow the list.
      final auth = context.read<AuthState>();
      final known = auth.agent?.giftCodes;
      if (known != null &&
          (known.unused != data.counts.unused || known.used != data.counts.used)) {
        auth.refreshAgent();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The code and how to use it, ready to send on WhatsApp.
  Future<void> _share(GiftCode code) async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(code.shareText)}');
    final ok = await context.read<LinkLauncher>().launch(uri);
    if (!ok && mounted) showSnack(context, S.cannotOpenWhatsApp, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(S.giftCodes)),
      body: _loading && data == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && data == null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: data == null
                        ? const []
                        : [
                            _CountsCard(counts: data.counts),
                            const SizedBox(height: 16),
                            if (data.codes.isEmpty)
                              const EmptyState(
                                icon: Icons.card_giftcard_rounded,
                                title: S.noGiftCodes,
                                message: S.noGiftCodesHint,
                              )
                            else ...[
                              SectionHeader(
                                S.unusedCodes,
                                trailing: StatusChip(
                                  label: '${data.unusedCodes.length}',
                                  color: AppColors.success,
                                ),
                              ),
                              if (data.unusedCodes.isEmpty)
                                SurfaceCard(
                                  child: Text(
                                    S.allCodesUsed,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(color: theme.colorScheme.outline),
                                  ),
                                )
                              else
                                SurfaceCard(
                                  padding: EdgeInsets.zero,
                                  child: Column(
                                    children: [
                                      for (final (i, c) in data.unusedCodes.indexed) ...[
                                        if (i > 0) const Divider(height: 1),
                                        _UnusedCodeRow(
                                          code: c,
                                          onCopy: () => copyText(context, c.code, S.giftCodeCopied),
                                          onShare: () => _share(c),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              if (data.usedCodes.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                SectionHeader(
                                  S.usedCodes,
                                  trailing: StatusChip(
                                    label: '${data.usedCodes.length}',
                                    color: AppColors.navyLight,
                                  ),
                                ),
                                SurfaceCard(
                                  padding: EdgeInsets.zero,
                                  child: Column(
                                    children: [
                                      for (final (i, c) in data.usedCodes.indexed) ...[
                                        if (i > 0) const Divider(height: 1),
                                        _UsedCodeRow(code: c),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(height: 16),
                            Text(
                              S.giftCodesMoreHint,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.outline),
                            ),
                          ],
                  ),
                ),
    );
  }
}

/// Unused / used counts on the brand gradient, with how codes work.
class _CountsCard extends StatelessWidget {
  const _CountsCard({required this.counts});

  final GiftCodeCounts counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String value, String label, Key key) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                key: key,
                style: const TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  fontVariations: [FontVariation('wght', 600)],
                  color: AppColors.goldLight,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard_rounded, color: AppColors.goldLight),
              const SizedBox(width: 10),
              stat('${counts.unused}', S.unusedCodes, const ValueKey('gift-unused')),
              stat('${counts.used}', S.usedCodes, const ValueKey('gift-used')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            S.giftCodesIntro,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}

/// The code in monospace, when it was given, then Copy and Share.
class _UnusedCodeRow extends StatelessWidget {
  const _UnusedCodeRow({required this.code, required this.onCopy, required this.onShare});

  final GiftCode code;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _CodeText(code.code)),
              if (code.createdAt != null)
                Text(
                  S.createdOn(formatDate(code.createdAt)),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text(S.copy),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    backgroundColor: AppColors.success.withValues(alpha: 0.14),
                    foregroundColor: AppColors.success,
                  ),
                  onPressed: onShare,
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text(S.share),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A spent code: who used it and when.
class _UsedCodeRow extends StatelessWidget {
  const _UsedCodeRow({required this.code});

  final GiftCode code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = code.usedByName;
    final line = [
      who == null ? S.usedByUnknown : S.usedBy(who),
      if (code.usedAt != null) S.usedOn(formatDate(code.usedAt)),
    ].join(' ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CodeText(code.code, muted: true),
                const SizedBox(height: 2),
                Text(line, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "WB-K7M2QX" in a monospace face, easy to read out over the phone.
class _CodeText extends StatelessWidget {
  const _CodeText(this.code, {this.muted = false});

  final String code;
  final bool muted;

  @override
  Widget build(BuildContext context) => Text(
        code,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['RobotoMono', 'Courier'],
          fontSize: muted ? 15 : 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: muted ? AppColors.muted : AppColors.navy,
        ),
      );
}
