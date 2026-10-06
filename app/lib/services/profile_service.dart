import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../models/master_data.dart';
import '../models/notifications.dart';
import '../models/parsed_profile.dart';
import '../models/profile.dart';
import 'api_client.dart';

/// Everything the profile list/detail/edit screens need.
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

  /// Multipart create. Empty values are not sent (the server treats absent
  /// as "not recorded"). `education_levels` — a list of `{level, details,
  /// country_id}` maps — travels as a JSON string, which is what the
  /// multipart route parses (SPEC §9.7); any other list or map goes the same
  /// way. An empty list is skipped like any other empty value.
  Future<Profile> create(Map<String, dynamic> fields, List<String> photoPaths) async {
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
      form.files.add(MapEntry(
        'photos',
        await MultipartFile.fromFile(path, contentType: MediaType('image', 'jpeg')),
      ));
    }
    final json = await _api.postForm('/profiles', form);
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

  /// Whether the server has AI import switched on (ANTHROPIC_API_KEY set).
  Future<bool> aiEnabled() async {
    try {
      final json = await _api.get('/profiles/parse/status');
      return json['enabled'] == true;
    } on ApiException {
      return false;
    }
  }

  /// AI import: a PDF / photo / pasted text bio-data → draft fields for the
  /// form to pre-fill. Nothing is saved server-side.
  Future<ParsedProfile> parseBioData({String? filePath, String? text}) async {
    final form = FormData();
    if (text != null && text.trim().isNotEmpty) form.fields.add(MapEntry('text', text.trim()));
    if (filePath != null) {
      final ext = filePath.split('.').last.toLowerCase();
      final type = switch (ext) {
        'pdf' => MediaType('application', 'pdf'),
        'png' => MediaType('image', 'png'),
        'webp' => MediaType('image', 'webp'),
        'txt' => MediaType('text', 'plain'),
        _ => MediaType('image', 'jpeg'),
      };
      form.files.add(MapEntry('file', await MultipartFile.fromFile(filePath, contentType: type)));
    }
    final json = await _api.postForm(
      '/profiles/parse',
      form,
      receiveTimeout: const Duration(seconds: 120),
    );
    return ParsedProfile.fromJson(json);
  }

  /// Uploader or admin only (SPEC §4). Hard delete, photos and links included.
  Future<void> delete(int id) => _api.delete('/profiles/$id');

  Future<void> deletePhoto(int photoId) => _api.delete('/photos/$photoId');

  Future<void> makePhotoPrimary(int photoId) => _api.post('/photos/$photoId/primary');

  Future<NotificationFeed> notifications() async =>
      NotificationFeed.fromJson(await _api.get('/notifications'));
}
