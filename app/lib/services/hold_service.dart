import '../models/contact_request.dart' show RequestBox;
import '../models/hold_request.dart';
import 'api_client.dart';

/// The hold workflow (SPEC §4 Hold requests).
class HoldService {
  HoldService(this._api);

  final ApiClient _api;

  /// Asks to put [profileId] on hold. For the uploader or an admin the hold is
  /// approved immediately; for anyone else it waits for the uploader.
  Future<HoldRequest> request(int profileId, {String? note}) async {
    final json = await _api.post('/profiles/$profileId/hold-request', body: {'note': note});
    return HoldRequest.fromJson(json['hold_request'] as Map<String, dynamic>);
  }

  Future<List<HoldRequest>> list(RequestBox box) async {
    final json = await _api.get('/hold-requests', query: {'box': box.name});
    return (json['hold_requests'] as List? ?? [])
        .map((e) => HoldRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<HoldRequest> approve(int id) => _act(id, 'approve');
  Future<HoldRequest> reject(int id) => _act(id, 'reject');
  Future<HoldRequest> release(int id) => _act(id, 'release');
  Future<HoldRequest> cancel(int id) => _act(id, 'cancel');

  Future<HoldRequest> _act(int id, String action) async {
    final json = await _api.post('/hold-requests/$id/$action');
    return HoldRequest.fromJson(json['hold_request'] as Map<String, dynamic>);
  }
}
