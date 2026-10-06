import '../models/agent_change.dart';
import '../models/customer.dart';
import 'api_client.dart';

/// The agent directory, linking an agent (guest / pending / rejected) and
/// "change agent" requests (active only) — SPEC §9.6 / §9.12. The directory
/// is open to every customer who is not suspended.
class AgentsService {
  AgentsService(this._api);

  final ApiClient _api;

  /// GET /customer/agents?q=&community_id=&city= → {agents: [...]}; the
  /// current agent comes first with `is_current: true`.
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

  /// POST /customer/agent {agent_phone | agent_id} → {customer} (SPEC §9.12).
  /// Allowed while guest / pending / rejected; the account becomes pending
  /// with that agent and my profiles move to them. 404 `agent_not_found`,
  /// 400 `agent_not_active`, 400 `same_agent`, 409 `wrong_status`.
  Future<Customer> linkAgent({String? agentPhone, int? agentId}) async {
    final json = await _api.post('/customer/agent', body: {
      'agent_phone': ?_clean(agentPhone),
      'agent_id': ?agentId,
    });
    return Customer.fromJson(json['customer'] as Map<String, dynamic>);
  }

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
