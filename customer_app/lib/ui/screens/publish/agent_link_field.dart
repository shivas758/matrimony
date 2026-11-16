import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/agents_service.dart';
import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// "Agent's mobile number or agent code" + *Link agent* (SPEC §9.18 B / G):
/// ten digits link by number, anything shaped like `KA1A` by code
/// ([AgentLookup.parse] decides); the server's own sentence when it finds
/// nobody. Used in Get started and on the publish screen.
class AgentLinkField extends StatefulWidget {
  const AgentLinkField({super.key, this.primary = true, this.onLinked, this.label = S.agentPhoneOrCode});

  /// A filled *Link agent* button (the step's main action).
  final bool primary;

  /// After the account was linked (it is already updated).
  final VoidCallback? onLinked;

  /// The line above the field.
  final String label;

  @override
  State<AgentLinkField> createState() => _AgentLinkFieldState();
}

class _AgentLinkFieldState extends State<AgentLinkField> {
  final _ref = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final lookup = AgentLookup.parse(_ref.text);
    if (lookup == null) {
      setState(() => _error = S.agentPhoneOrCodeInvalid);
      return;
    }
    FocusScope.of(context).unfocus();
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthState>();
    // The step this field sits in is replaced once the account has an agent.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final customer = await context.read<AgentsService>().linkAgentBy(lookup);
      auth.setCustomer(customer);
      await auth.refresh();
      widget.onLinked?.call();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(S.agentLinkedSnack)));
      if (mounted) _ref.clear();
    } on ApiException catch (e) {
      // Not found / not active / cannot take customers / already my agent:
      // the server's own sentence (it knows whether a number or a code failed).
      if (mounted) setState(() => _error = linkAgentMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = widget.primary
        ? FilledButton.icon(
            onPressed: _busy ? null : _link,
            icon: _busy ? const ButtonSpinner() : const Icon(Icons.link_rounded),
            label: const Text(S.agentPhoneLink),
          )
        : OutlinedButton.icon(
            onPressed: _busy ? null : _link,
            icon: _busy ? const ButtonSpinner(color: AppColors.wine) : const Icon(Icons.link_rounded),
            label: const Text(S.agentPhoneLink),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Above the field, not inside it: the label is too long for the
        // field's own (single-line) label on a phone.
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.wine),
          ),
        ),
        TextField(
          controller: _ref,
          // A number or a code like KA1A: letters must be typeable.
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z+ \-]')),
            LengthLimitingTextInputFormatter(16),
          ],
          onSubmitted: (_) => _link(),
          decoration: InputDecoration(
            hintText: S.agentPhoneOrCodeHint,
            helperText: S.agentPhoneOrCodeHelper,
            helperMaxLines: 3,
            prefixIcon: const Icon(Icons.support_agent_rounded),
            errorText: _error,
            errorMaxLines: 4,
          ),
        ),
        const SizedBox(height: 12),
        button,
      ],
    );
  }
}
