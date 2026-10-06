import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../services/auth_service.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../widgets/common.dart';

/// Shown instead of Home after a login with a temporary password (issued by
/// an admin through the forgot-password flow). The server refuses every data
/// route until the agent sets their own password, so there is nothing else to
/// do here except log out.
class ForcePasswordScreen extends StatefulWidget {
  const ForcePasswordScreen({super.key});

  @override
  State<ForcePasswordScreen> createState() => _ForcePasswordScreenState();
}

class _ForcePasswordScreenState extends State<ForcePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().changePassword(current: _current.text, next: _next.text);
      if (!mounted) return;
      showSnack(context, S.passwordUpdated);
      // /auth/me now reports must_change_password = false; the root swaps to Home.
      await context.read<AuthState>().refreshAgent();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agent = context.watch<AuthState>().agent;

    return Scaffold(
      appBar: AppBar(
        title: Text(agent?.fullName ?? ''),
        actions: [
          IconButton(
            tooltip: S.logout,
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.lock_reset_rounded, size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      S.setNewPasswordTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.setNewPasswordBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _current,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: S.temporaryPassword,
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v ?? '').isEmpty ? 'Enter the temporary password' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _next,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: S.newPassword,
                        prefixIcon: Icon(Icons.lock_rounded),
                      ),
                      validator: (v) {
                        if ((v ?? '').length < 6) return 'Use at least 6 characters';
                        if (v == _current.text) return 'Choose a different password';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: S.confirmPassword,
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                      validator: (v) => v != _next.text ? 'Passwords do not match' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Text(S.save),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
