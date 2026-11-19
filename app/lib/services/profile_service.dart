import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../models/master_data.dart';
import '../models/notifications.dart';
import '../models/profile.dart';
import 'api_client.dart';

/// Everything the profile list/detail/edit screens need. There is no create:
/// families add profiles, agents only edit them (SPEC §9.24 A).
class ProfileService {
  ProfileService(this._api);

  final ApiClient _api;

  Future<MasterData> masters() async =>
      MasterData.fromJson(await _api.get('/masters'));

  Future<ProfilePage> list(Map<String, dynamic> query) async =>
      ProfilePage.fromJson(await _api.get('/profiles', query: query));

  Future<Profile> detail(int id) async {
    final json = await _api.get('/profiles/$id');
    return Profile.fromJson(json['profile'] as Map<String, dynamic>);
  }

  /// JSON PATCH: nulls clear a field, `education_levels: []` clears the
  /// education table, so the body goes through untouched.
  Future<Profile> update(int id, Map<String, dynamic> fields) async {
    final json = await _api.patch('/profiles/$id', body: fields);
    return Profile.fromJson(json['profile'] as Map<String, dynamic>);
  }

  Future<void> addPhotos(int profileId, List<String> photoPaths) async {
    if (photoPaths.isEmpty) return;
    final form = FormData();
    for (final path in photoPaths) {
      form.files.add(MapEntry(
        'photos',
        await MultipartFile.fromFile(path, contentType: MediaType('image', 'jpeg')),
      ));
    }
    await _api.postForm('/profiles/$profileId/photos', form);
  }

  /// Uploader or admin only (SPEC §4). Hard delete, photos and links included.
  Future<void> delete(int id) => _api.delete('/profiles/$id');

  /// Reports a profile to the admins (SPEC §9.22 A): [reason] is a
  /// `ReportReason` wire value, [details] up to 500 characters.
  /// `400 own_profile` for my own uploads, `404` when it is not visible.
  Future<void> report(int id, {required String reason, String? details}) => _api.post(
    '/profiles/$id/report',
    body: {'reason': reason, if (details != null && details.isNotEmpty) 'details': details},
  );

  /// Hides the profile from me everywhere (SPEC §9.22 B); undone from
  /// Settings → Blocked profiles.
  Future<void> block(int id) => _api.post('/profiles/$id/block');

  Future<void> deletePhoto(int photoId) => _api.delete('/photos/$photoId');

  Future<void> makePhotoPrimary(int photoId) => _api.post('/photos/$photoId/primary');

  Future<NotificationFeed> notifications() async =>
      NotificationFeed.fromJson(await _api.get('/notifications'));
}
