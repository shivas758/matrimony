import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../services/link_launcher.dart';
import '../strings.dart';
import '../theme.dart';
import 'common.dart';

/// "I agree to the Terms & Conditions and Privacy Policy" (SPEC §9.22 C):
/// a checkbox the signup needs ticked; the two links open the pages in the
/// browser through the [LinkLauncher].
class TermsConsent extends StatelessWidget {
  const TermsConsent({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: value, onChanged: enabled ? (v) => onChanged(v ?? false) : null),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => onChanged(!value) : null,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text.rich(
                TextSpan(
                  style: style,
                  children: [
                    const TextSpan(text: S.termsAgreePrefix),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _Link(label: S.termsLink, url: AppConfig.termsUrl, style: style),
                    ),
                    const TextSpan(text: S.termsAnd),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _Link(label: S.privacyLink, url: AppConfig.privacyUrl, style: style),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.url, this.style});

  final String label;
  final String url;
  final TextStyle? style;

  Future<void> _open(BuildContext context) async {
    final ok = await context.read<LinkLauncher>().launch(Uri.parse(url));
    if (!ok && context.mounted) showSnack(context, S.cannotOpenBrowser, error: true);
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _open(context),
    child: Text(
      label,
      style: style?.copyWith(
        color: AppColors.navyLight,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline,
      ),
    ),
  );
}
