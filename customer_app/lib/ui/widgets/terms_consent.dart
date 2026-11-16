import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../services/link_launcher.dart';
import '../strings.dart';
import '../theme.dart';
import 'common.dart';

/// "I agree to the Terms & Conditions and Privacy Policy" (SPEC §9.22 C):
/// a checkbox the signup needs; both phrases open the page in the browser
/// ([AppConfig.termsUrl], [AppConfig.privacyUrl]). Tapping the rest of the
/// sentence ticks the box.
class TermsConsent extends StatefulWidget {
  const TermsConsent({super.key, required this.value, required this.onChanged, this.enabled = true});

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  State<TermsConsent> createState() => _TermsConsentState();
}

class _TermsConsentState extends State<TermsConsent> {
  late final _terms = TapGestureRecognizer()..onTap = () => _open(AppConfig.termsUrl);
  late final _privacy = TapGestureRecognizer()..onTap = () => _open(AppConfig.privacyUrl);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final opened = await context.read<LinkLauncher>().openExternal(Uri.parse(url));
    if (!opened && mounted) showSnack(context, S.linkOpenFailed, error: true);
  }

  void _toggle() {
    if (widget.enabled) widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const link = TextStyle(
      color: AppColors.wine,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.wine,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: widget.value,
          onChanged: widget.enabled ? (v) => widget.onChanged(v ?? false) : null,
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text.rich(
                TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  children: [
                    const TextSpan(text: S.termsAgreePrefix),
                    TextSpan(text: S.termsLink, style: link, recognizer: _terms),
                    const TextSpan(text: S.termsAnd),
                    TextSpan(text: S.privacyLink, style: link, recognizer: _privacy),
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
