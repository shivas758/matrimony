// Gift codes (SPEC §9.23 B): every agent gets ten free codes once (an admin
// can add more). A family enters one when they publish their profile in
// Wedbook Matrimony — no registration fee, and they become the agent's
// approved client at once. The agent can also apply one for a client.

/// `{unused, used, total}` — on `/auth/me` (`gift_codes`), after an admin adds
/// codes, and as the header of `GET /my/gift-codes`.
class GiftCodeCounts {
  const GiftCodeCounts({this.unused = 0, this.used = 0, int? total}) : total = total ?? unused + used;

  final int unused;
  final int used;
  final int total;

  static const empty = GiftCodeCounts();

  static int _i(Object? v) => (v as num?)?.toInt() ?? 0;

  /// Null when the server sent no counts (a server older than v2.13).
  static GiftCodeCounts? fromJsonOrNull(Object? j) {
    if (j is! Map) return null;
    final unused = _i(j['unused']);
    final used = _i(j['used']);
    return GiftCodeCounts(
      unused: unused,
      used: used,
      total: j['total'] == null ? null : _i(j['total']),
    );
  }
}

/// The customer or profile a used code went to: `{id, full_name}`.
class GiftCodeRef {
  const GiftCodeRef({required this.id, required this.fullName});

  final int id;
  final String fullName;

  static GiftCodeRef? fromJsonOrNull(Object? j) {
    if (j is! Map) return null;
    final name = j['full_name'];
    return GiftCodeRef(
      id: (j['id'] as num?)?.toInt() ?? 0,
      fullName: name is String ? name.trim() : '',
    );
  }
}

/// One row of `GET /my/gift-codes`.
class GiftCode {
  const GiftCode({
    required this.id,
    required this.code,
    required this.status,
    this.createdAt,
    this.usedAt,
    this.customer,
    this.profile,
    this.shareText = '',
  });

  final int id;

  /// "WB-K7M2QX".
  final String code;

  /// `unused` | `used`.
  final String status;
  final DateTime? createdAt;
  final DateTime? usedAt;
  final GiftCodeRef? customer;
  final GiftCodeRef? profile;

  /// The ready-made WhatsApp message with the code and how to use it.
  final String shareText;

  bool get isUsed => status == 'used';
  bool get isUnused => !isUsed;

  /// Who used it: the customer's name, else the profile's, else null.
  String? get usedByName {
    for (final n in [customer?.fullName, profile?.fullName]) {
      if (n != null && n.isNotEmpty) return n;
    }
    return null;
  }

  factory GiftCode.fromJson(Map<String, dynamic> j) {
    final code = '${j['code'] ?? ''}'.trim();
    final share = j['share_text'];
    return GiftCode(
      id: (j['id'] as num?)?.toInt() ?? 0,
      code: code,
      status: '${j['status'] ?? 'unused'}',
      createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal(),
      usedAt: DateTime.tryParse('${j['used_at']}')?.toLocal(),
      customer: GiftCodeRef.fromJsonOrNull(j['customer']),
      profile: GiftCodeRef.fromJsonOrNull(j['profile']),
      shareText: share is String && share.trim().isNotEmpty ? share : code,
    );
  }
}

/// `GET /my/gift-codes` — unused first (oldest first), then used (newest
/// first), as the server orders them.
class GiftCodeList {
  const GiftCodeList({required this.codes, required this.counts});

  final List<GiftCode> codes;
  final GiftCodeCounts counts;

  List<GiftCode> get unusedCodes => codes.where((c) => c.isUnused).toList();
  List<GiftCode> get usedCodes => codes.where((c) => c.isUsed).toList();

  factory GiftCodeList.fromJson(Map<String, dynamic> j) {
    final codes = (j['gift_codes'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(GiftCode.fromJson)
        .where((c) => c.code.isNotEmpty)
        .toList();
    final unused = j['unused'];
    final used = j['used'];
    return GiftCodeList(
      codes: codes,
      counts: GiftCodeCounts(
        unused: unused is num ? unused.toInt() : codes.where((c) => c.isUnused).length,
        used: used is num ? used.toInt() : codes.where((c) => c.isUsed).length,
        total: (j['total'] as num?)?.toInt(),
      ),
    );
  }
}
