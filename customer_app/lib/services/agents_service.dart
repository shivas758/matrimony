import '../models/agent_change.dart';
import '../models/customer.dart';
import 'api_client.dart';

/// What a customer typed into "Agent's mobile number or agent code" (SPEC
/// §9.18 B / G), decided by its shape: ten digits are a mobile number,
/// letters with digits (`KA1A`) an agent code.
class AgentLookup {
  const AgentLookup.phone(String this.phone) : code = null;
  const AgentLookup.code(String this.code) : phone = null;

  /// The 10-digit mobile number, or null when it is a code.
  final String? phone;

  /// The agent code, upper-cased, or null when it is a number.
  final String? code;

  bool get isPhone => phone != null;

  /// Spaces, dashes, dots and brackets people type inside a number or code.
  static final _separators = RegExp(r'[\s\-.()]');
  static final _tenDigits = RegExp(r'^[0-9]{10}$');

  /// A code: letters and digits, at least one of each, starting with a
  /// letter (state code + number + letters — the server knows the exact rule).
  static final _code = RegExp(r'^[A-Z](?=[A-Z0-9]*[0-9])[A-Z0-9]{2,11}$');

  /// Null when [input] is neither: empty, the wrong number of digits, or
  /// something that cannot be a code. `+91` / `91` / a leading `0` in front
  /// of ten digits is dropped.
  static AgentLookup? parse(String input) {
    final compact = input.replaceAll(_separators, '');
    if (compact.isEmpty) return null;

    var digits = compact;
    if (digits.startsWith('+91')) {
      digits = digits.substring(3);
    } else if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (_tenDigits.hasMatch(digits)) return AgentLookup.phone(digits);

    final code = compact.toUpperCase();
    return _code.hasMatch(code) ? AgentLookup.code(code) : null;
  }

  /// The body of `POST /customer/agent`.
  Map<String, dynamic> toJson() => isPhone ? {'agent_phone': phone} : {'agent_code': code};

  @override
  String toString() => isPhone ? 'phone:$phone' : 'code:$code';
}

/// The agent directory, linking an agent (guest / pending / rejected) and
/// "change agent" requests (active only) — SPEC §9.6 / §9.12. The directory
/// is open to every customer who is not suspended.
class AgentsService {
  AgentsService(this._api);

  final ApiClient _api;

  /// GET /customer/agents?q=&community_id=&city= → {agents: [...]}; the
  /// current agent comes first with `is_current: true`. `q` matches the
  /// name, the agency and the agent code (SPEC §9.18 B).
  Future<List<AgentCard>> directory({String? q, int? communityId, String? city}) async {
    final json = await _api.get('/customer/agents', query: {
      'q': ?_clean(q),
      'community_id': ?communityId,
      'city': ?_clean(city),
    });
    return (json['agents'] as List? ?? [])
        .map((e) => AgentCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /customer/agent {agent_phone | agent_code | agent_id} → {customer}
  /// (SPEC §9.12, agent code: §9.18 B). Allowed while guest / pending /
  /// rejected; the account becomes pending with that agent and my profile
  /// moves to them. 404 `agent_not_found`, 400 `agent_not_active`, 400
  /// `agent_has_no_communities`, 400 `same_agent`, 409 `wrong_status`.
  Future<Customer> linkAgent({String? agentPhone, String? agentCode, int? agentId}) async {
    final json = await _api.post('/customer/agent', body: {
      'agent_phone': ?_clean(agentPhone),
      'agent_code': ?_clean(agentCode)?.toUpperCase(),
      'agent_id': ?agentId,
    });
    return Customer.fromJson(json['customer'] as Map<String, dynamic>);
  }

  /// [linkAgent] with what the customer typed — a number or a code.
  Future<Customer> linkAgentBy(AgentLookup lookup) =>
      linkAgent(agentPhone: lookup.phone, agentCode: lookup.code);

  /// POST /customer/agent-change {to_agent_id, note?} → 201 {agent_change_request}.
  /// 409 `already_pending`, 400 `same_agent`, 404 `agent_not_found`.
  Future<AgentChangeRequest> requestChange(int toAgentId, {String? note}) async {
    final json = await _api.post('/customer/agent-change', body: {
      'to_agent_id': toAgentId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return AgentChangeRequest.fromJson(json['agent_change_request'] as Map<String, dynamic>);
  }

  /// POST /customer/agent-change/:id/cancel (while pending) → {agent_change_request}.
  Future<AgentChangeRequest> cancelChange(int id) async {
    final json = await _api.post('/customer/agent-change/$id/cancel');
    return AgentChangeRequest.fromJson(json['agent_change_request'] as Map<String, dynamic>);
  }

  /// Trimmed text, or null when blank — blank filters are not sent.
  static String? _clean(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  /// GET /customer/agent-change → {agent_change_requests: [...]}, newest first.
  Future<List<AgentChangeRequest>> myChangeRequests() async {
    final json = await _api.get('/customer/agent-change');
    return (json['agent_change_requests'] as List? ?? [])
        .map((e) => AgentChangeRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
