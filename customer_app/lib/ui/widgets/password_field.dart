import 'package:flutter/material.dart';

import '../strings.dart';

/// Passwords are 6–100 characters (SPEC §9.24 C), taken exactly as typed.
const int kPasswordMin = 6;
const int kPasswordMax = 100;

/// A new password: 6–100 characters.
String? validateNewPassword(String? v) {
  final length = (v ?? '').length;
  if (length < kPasswordMin) return S.passwordTooShort;
  if (length > kPasswordMax) return S.passwordTooLong;
  return null;
}

/// The confirmation must equal what [password] holds.
FormFieldValidator<String> confirmPasswordValidator(TextEditingController password) =>
    (v) => (v ?? '') == password.text ? null : S.passwordsDoNotMatch;

/// A password [TextFormField] with a show / hide eye — the login, Create
/// account, Forgot password and Change password screens.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.helperText,
    this.icon = Icons.lock_rounded,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.newPassword = false,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final String? helperText;
  final IconData icon;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  /// A password being chosen (autofill offers to save it) rather than one
  /// being typed in to log in.
  final bool newPassword;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enabled: widget.enabled,
        obscureText: _obscure,
        enableSuggestions: false,
        autocorrect: false,
        maxLength: kPasswordMax,
        textInputAction: widget.textInputAction,
        autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
        onFieldSubmitted: widget.onSubmitted,
        validator: widget.validator,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          counterText: '',
          errorMaxLines: 2,
          prefixIcon: Icon(widget.icon),
          suffixIcon: IconButton(
            tooltip: _obscure ? S.showPassword : S.hidePassword,
            icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      );
}
