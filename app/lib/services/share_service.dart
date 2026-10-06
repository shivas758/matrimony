import '../models/shortlist.dart';
import 'api_client.dart';

class ShareLink {
  const ShareLink({required this.shareUrl, required this.whatsappText, required this.tokenId});

  final String shareUrl;
  final String whatsappText;
  final int tokenId;
}

class ShareService {
  ShareService(this._api);

  final ApiClient _api;

  /// Creates (or reuses) the public masked link and logs the share.
  Future<ShareLink> shareLink(int profileId, {String method = 'whatsapp'}) async {
    final json = await _api.post('/profiles/$profileId/share', body: {'method': method});
    return ShareLink(
      shareUrl: '${json['share_url']}',
      whatsappText: '${json['whatsapp_text']}',
      tokenId: (json['share_token_id'] as num).toInt(),
    );
  }

  /// The masked, watermarked profile card as JPEG bytes.
  Future<List<int>> downloadCard(int profileId) =>
      _api.postBytes('/profiles/$profileId/share', body: {'method': 'download'});

  /// The masked A4 bio-data as PDF bytes (watermarked photos, public fields only).
  Future<List<int>> downloadPdf(int profileId) =>
      _api.postBytes('/profiles/$profileId/share', body: {'method': 'pdf'});

  Future<void> deactivateLink(int tokenId) => _api.post('/share-tokens/$tokenId/deactivate');
}

class ShortlistService {
  ShortlistService(this._api);

  final ApiClient _api;

  Future<List<ShortlistGroup>> groups() async {
    final json = await _api.get('/shortlists');
    return (json['groups'] as List? ?? [])
        .map((e) => ShortlistGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> labels() async {
    final json = await _api.get('/shortlists/labels');
    return (json['labels'] as List? ?? []).map((e) => '${e['client_label']}').toList();
  }

  Future<void> add(int profileId, String clientLabel) =>
      _api.post('/profiles/$profileId/shortlist', body: {'client_label': clientLabel});

  Future<void> remove(int shortlistId) => _api.delete('/shortlists/$shortlistId');
}
