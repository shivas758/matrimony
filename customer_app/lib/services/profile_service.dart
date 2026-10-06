import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../models/master_data.dart';
import '../models/profile.dart';
import 'api_client.dart';

/// Everything the Browse / Interested / My profile screens need from the
/// customer routes (SPEC §9.9). All paths are under `/customer`; photo urls
/// in the JSON already point at `/api/customer/photos/:id`.
class ProfileService {
  ProfileService(this._api);

  final ApiClient _api;

  /// Public — needed before any token exists.
  Future<MasterData> masters() async => MasterData.fromJson(await _api.get('/masters'));

  /// Exposed so other services can share the one client.
  ApiClient get api => _api;

  // ------------------------------------------------------------ browse

  /// GET /customer/profiles — with full access: active profiles in my agent's
  /// communities, never mine, opposite gender of my first paid profile by
  /// default. With guest access: every active profile as a locked teaser row
  /// (SPEC §9.12); the page says which (`access`).
  Future<ProfilePage> list(Map<String, dynamic> query) async =>
      ProfilePage.fromJson(await _api.get('/customer/profiles', query: query));

  /// GET /customer/profiles/:id → {profile} with my `interest` and, while an
  /// accepted interest is live, the on-request fields. 403 `unlock_required`
  /// without full access.
  Future<Profile> detail(int id) async {
    final json = await _api.get('/customer/profiles/$id');
    return Profile.fromJson(json['profile'] as Map<String, dynamic>);
  }

  // ------------------------------------------------------------ interests

  /// POST /customer/profiles/:id/interest {note?, from_profile_id?} → 201
  /// {interest}. [fromProfileId] = which of my live profiles is interested;
  /// the server picks it when there is only one (SPEC §9.12).
  Future<Interest> markInterested(int profileId, {String? note, int? fromProfileId}) async {
    final json = await _api.post(
      '/customer/profiles/$profileId/interest',
      body: {
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'from_profile_id': ?fromProfileId,
      },
    );
    return Interest.fromJson(json['interest'] as Map<String, dynamic>);
  }

  /// POST /customer/interests/:id/withdraw (pending only) → {interest}.
  Future<Interest> withdraw(int interestId) async {
    final json = await _api.post('/customer/interests/$interestId/withdraw');
    return Interest.fromJson(json['interest'] as Map<String, dynamic>);
  }

  /// GET /customer/interests → {interests: [...]}, newest first.
  Future<List<Interest>> myInterests() async {
    final json = await _api.get('/customer/interests');
    return (json['interests'] as List? ?? [])
        .map((e) => Interest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ------------------------------------------------------------ my profiles (up to 5)

  /// GET /customer/my-profiles/:id — one of my profiles with every field and
  /// its fee state (`paid`, `visibility`).
  Future<Profile> myProfile(int id) async {
    final json = await _api.get('/customer/my-profiles/$id');
    return Profile.fromJson(json['profile'] as Map<String, dynamic>);
  }

  /// POST /customer/my-profiles — multipart create (SPEC §9.12). Empty values
  /// are not sent (the server treats absent as "not recorded"); lists and
  /// maps travel as JSON strings (`education_levels`), which is what the
  /// multipart route parses (SPEC §9.7). Photos go as `photos[]`.
  /// 409 `profile_limit`, 409/403 `agent_required`.
  Future<Profile> createProfile(Map<String, dynamic> fields, List<String> photoPaths) async {
    final form = FormData();
    fields.forEach((k, v) {
      if (v == null) return;
      if (v is List || v is Map) {
        if (v is List && v.isEmpty) return;
        if (v is Map && v.isEmpty) return;
        form.fields.add(MapEntry(k, jsonEncode(v)));
        return;
      }
      if ('$v'.isNotEmpty) form.fields.add(MapEntry(k, '$v'));
    });
    for (final path in photoPaths) {
      form.files.add(MapEntry('photos', await _photoFile(path)));
    }
    final json = await _api.postForm(
      '/customer/my-profiles',
      form,
      receiveTimeout: const Duration(seconds: 90),
    );
    return Profile.fromJson(json['profile'] as Map<String, dynamic>);
  }

  /// PATCH /customer/my-profiles/:id — JSON. Nulls / empty strings clear a
  /// field, `education_levels: []` clears the education table.
  Future<Profile> updateProfile(int id, Map<String, dynamic> fields) async {
    final json = await _api.patch('/customer/my-profiles/$id', body: fields);
    return Profile.fromJson(json['profile'] as Map<String, dynamic>);
  }

  /// GET /customer/my-profiles → {profiles: [own view…]} — each with its
  /// pending `delete_request` (SPEC §9.13).
  Future<List<Profile>> myProfiles() async {
    final json = await _api.get('/customer/my-profiles');
    return (json['profiles'] as List? ?? [])
        .map((e) => Profile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// DELETE /customer/my-profiles/:id — only while unpaid; a paid one answers
  /// 409 `approval_required` (ask the agent with [requestDeletion]).
  Future<void> deleteProfile(int id) => _api.delete('/customer/my-profiles/$id');

  /// POST /customer/my-profiles/:id/delete-request {reason?} → 201
  /// {delete_request}. 409 `already_pending`, 400 `not_paid` (SPEC §9.13).
  Future<DeleteRequest> requestDeletion(int id, {String? reason}) async {
    final json = await _api.post('/customer/my-profiles/$id/delete-request', body: {
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    return DeleteRequest.fromJson(json['delete_request'] as Map<String, dynamic>);
  }

  /// POST /customer/delete-requests/:id/cancel (while pending) → {delete_request}.
  Future<DeleteRequest> cancelDeleteRequest(int requestId) async {
    final json = await _api.post('/customer/delete-requests/$requestId/cancel');
    return DeleteRequest.fromJson(json['delete_request'] as Map<String, dynamic>);
  }

  /// POST /customer/my-profiles/:id/photos → 201 {photos}.
  Future<List<ProfilePhoto>> addPhotos(int profileId, List<String> photoPaths) async {
    if (photoPaths.isEmpty) return const [];
    final form = FormData();
    for (final path in photoPaths) {
      form.files.add(MapEntry('photos', await _photoFile(path)));
    }
    final json = await _api.postForm(
      '/customer/my-profiles/$profileId/photos',
      form,
      receiveTimeout: const Duration(seconds: 90),
    );
    return _photos(json['photos']);
  }

  /// DELETE /customer/photos/:id (own photos only).
  Future<void> deletePhoto(int photoId) => _api.delete('/customer/photos/$photoId');

  /// POST /customer/photos/:id/primary → {photos} (primary first).
  Future<List<ProfilePhoto>> makePrimary(int photoId) async {
    final json = await _api.post('/customer/photos/$photoId/primary');
    return _photos(json['photos']);
  }

  static List<ProfilePhoto> _photos(dynamic list) => (list as List? ?? [])
      .map((e) => ProfilePhoto.fromJson(e as Map<String, dynamic>))
      .toList();

  static Future<MultipartFile> _photoFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    final type = switch (ext) {
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      'heic' => MediaType('image', 'heic'),
      _ => MediaType('image', 'jpeg'),
    };
    return MultipartFile.fromFile(path, contentType: type);
  }
}
