import '../models/agent_change.dart';
import '../models/customer.dart';
import '../models/delete_request.dart';
import '../models/interest.dart';
import 'api_client.dart';

/// Which interests to list (SPEC §9.4): `received` = on my uploads (I decide
/// them), `clients` = my own clients' interests (read, with the other agent's
/// contact). Admins get everything either way.
enum InterestBox { received, clients }

/// Agent-change requests (SPEC §9.6): `outgoing` = my clients asking to leave
/// (I decide), `incoming` = customers moving to me (read-only).
enum TransferBox { outgoing, incoming }

/// The agent's permanent registration-form link (SPEC §9.3-B).
class RegistrationLink {
  const RegistrationLink({required this.url, required this.whatsappText});

  final String url;

  /// Ready-made WhatsApp message containing the link.
  final String whatsappText;

  factory RegistrationLink.fromJson(Map<String, dynamic> j) => RegistrationLink(
        url: '${j['url'] ?? ''}',
        whatsappText: '${j['whatsapp_text'] ?? j['url'] ?? ''}',
      );
}

/// Everything under /clients, /interests and /agent-change-requests
/// (SPEC §9.4 – §9.6) — the Clients tab and the client detail screen.
class ClientsService {
  ClientsService(this._api);

  final ApiClient _api;

  // ---- clients (SPEC §9.5)

  /// My customers, pending first. Admins get every agent's (rows add `agent`).
  Future<List<Customer>> list({String? status, String? q}) async {
    final json = await _api.get('/clients', query: {
      'status': ?status,
      if (q != null && q.isNotEmpty) 'q': q,
    });
    return (json['clients'] as List? ?? [])
        .map((e) => Customer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The client plus their interests and agent-change requests.
  Future<Customer> detail(int id) async {
    final json = await _api.get('/clients/$id');
    return Customer.fromJson(json['client'] as Map<String, dynamic>);
  }

  Future<Customer> approve(int id) => _clientAction(id, 'approve'); // pending → active
  Future<Customer> reject(int id) => _clientAction(id, 'reject'); // pending → rejected
  Future<Customer> suspend(int id) => _clientAction(id, 'suspend'); // active → suspended
  Future<Customer> activate(int id) => _clientAction(id, 'activate'); // suspended → active

  Future<Customer> _clientAction(int id, String action) async {
    final json = await _api.post('/clients/$id/$action');
    return Customer.fromJson(json['client'] as Map<String, dynamic>);
  }

  /// Records the registration fee as received in cash (SPEC §9.13) —
  /// `409 already_paid`. Returns the refreshed client row.
  Future<Customer> markPaid(int clientId, int profileId, {String? note}) async {
    final json = await _api.post(
      '/clients/$clientId/profiles/$profileId/mark-paid',
      body: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    );
    return Customer.fromJson(json['client'] as Map<String, dynamic>);
  }

  // ---- delete requests for paid profiles (SPEC §9.13)

  /// My clients' requests (admin: all), pending by default.
  Future<List<ProfileDeleteRequest>> deleteRequests({String status = 'pending'}) async {
    final json = await _api.get('/clients/delete-requests', query: {'status': status});
    return (json['delete_requests'] as List? ?? [])
        .map((e) => ProfileDeleteRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Deletes the profile and its photos for good.
  Future<ProfileDeleteRequest> approveDeleteRequest(int id) => _deleteAction(id, 'approve');
  Future<ProfileDeleteRequest> rejectDeleteRequest(int id) => _deleteAction(id, 'reject');

  Future<ProfileDeleteRequest> _deleteAction(int id, String action) async {
    final json = await _api.post('/clients/delete-requests/$id/$action');
    return ProfileDeleteRequest.fromJson(json['delete_request'] as Map<String, dynamic>);
  }

  // ---- registration link (SPEC §9.3-B)

  Future<RegistrationLink> registrationLink() async =>
      RegistrationLink.fromJson(await _api.get('/clients/registration-link'));

  /// Mints a new link; the old one stops working at once.
  Future<RegistrationLink> rotateRegistrationLink() async =>
      RegistrationLink.fromJson(await _api.post('/clients/registration-link/rotate'));

  // ---- interests (SPEC §9.4)

  Future<List<Interest>> interests({
    InterestBox box = InterestBox.received,
    String? status,
  }) async {
    final json = await _api.get('/interests', query: {
      'box': box.name,
      'status': ?status,
    });
    return (json['interests'] as List? ?? [])
        .map((e) => Interest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Uploader or admin only. Accepting shares the on-request details with the
  /// customer for 15 days and grants their agent contact access (SPEC §9.4).
  Future<Interest> acceptInterest(int id) => _interestAction(id, 'accept');
  Future<Interest> declineInterest(int id) => _interestAction(id, 'decline');
  Future<Interest> revokeInterest(int id) => _interestAction(id, 'revoke');

  Future<Interest> _interestAction(int id, String action) async {
    final json = await _api.post('/interests/$id/$action');
    return Interest.fromJson(json['interest'] as Map<String, dynamic>);
  }

  // ---- agent change (SPEC §9.6)

  Future<List<AgentChangeRequest>> agentChangeRequests({
    TransferBox box = TransferBox.outgoing,
    String? status,
  }) async {
    final json = await _api.get('/agent-change-requests', query: {
      'box': box.name,
      'status': ?status,
    });
    return (json['agent_change_requests'] as List? ?? [])
        .map((e) => AgentChangeRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Current agent or admin only. Approving moves the customer and their
  /// profile to the new agent in one transaction.
  Future<AgentChangeRequest> approveAgentChange(int id) => _changeAction(id, 'approve');
  Future<AgentChangeRequest> rejectAgentChange(int id) => _changeAction(id, 'reject');

  Future<AgentChangeRequest> _changeAction(int id, String action) async {
    final json = await _api.post('/agent-change-requests/$id/$action');
    return AgentChangeRequest.fromJson(json['agent_change_request'] as Map<String, dynamic>);
  }
}
