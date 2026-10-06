import '../models/contact_request.dart';
import 'api_client.dart';

class ContactService {
  ContactService(this._api);

  final ApiClient _api;

  Future<ContactRequest> request(int profileId, {String? note}) async {
    final json = await _api.post('/profiles/$profileId/contact-request', body: {'note': note});
    return ContactRequest.fromJson(json['contact_request'] as Map<String, dynamic>);
  }

  Future<List<ContactRequest>> list(RequestBox box) async {
    final json = await _api.get('/contact-requests', query: {'box': box.name});
    return (json['contact_requests'] as List? ?? [])
        .map((e) => ContactRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ContactRequest> approve(int id) => _decide(id, 'approve');
  Future<ContactRequest> reject(int id) => _decide(id, 'reject');
  Future<ContactRequest> revoke(int id) => _decide(id, 'revoke');

  Future<ContactRequest> _decide(int id, String action) async {
    final json = await _api.post('/contact-requests/$id/$action');
    return ContactRequest.fromJson(json['contact_request'] as Map<String, dynamic>);
  }
}
