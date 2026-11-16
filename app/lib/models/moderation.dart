// Reports and blocks (SPEC §9.22 — Google Play's user-generated-content policy).

/// Why a profile is reported; `apiValue` is the wire value.
enum ReportReason {
  fakeProfile('fake_profile', 'Fake profile'),
  inappropriatePhoto('inappropriate_photo', 'Inappropriate photo'),
  offensiveContent('offensive_content', 'Offensive content'),
  scamOrFraud('scam_or_fraud', 'Scam or fraud'),
  harassment('harassment', 'Harassment'),
  other('other', 'Other');

  const ReportReason(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// The human label for a wire value; the value itself when unknown.
  static String labelOf(String value) {
    for (final r in values) {
      if (r.apiValue == value) return r.label;
    }
    return value;
  }
}

/// A profile I blocked: `GET /my/blocks` rows.
class BlockedProfile {
  const BlockedProfile({required this.profileId, required this.label, this.createdAt});

  final int profileId;

  /// The name as I saw it when blocking (the profile itself is hidden from me).
  final String label;
  final DateTime? createdAt;

  factory BlockedProfile.fromJson(Map<String, dynamic> j) {
    final id = (j['profile_id'] as num).toInt();
    final label = _str(j['profile_label']);
    return BlockedProfile(
      profileId: id,
      label: label ?? 'Profile $id',
      createdAt: _date(j['created_at']),
    );
  }
}

/// One row of the admin's Reports screen (`GET /admin/reports`).
class AdminReport {
  const AdminReport({
    required this.id,
    required this.reason,
    required this.status,
    this.details,
    this.action,
    this.note,
    this.createdAt,
    this.handledAt,
    this.reportsOnProfile = 1,
    this.reporter,
    this.profile,
    this.customer,
    this.agent,
  });

  final int id;
  final String reason;

  /// `open`, `actioned` or `dismissed`.
  final String status;
  final String? details;

  /// `profile_hidden`, `account_suspended` or null.
  final String? action;
  final String? note;
  final DateTime? createdAt;
  final DateTime? handledAt;

  /// Every report on the same profile, this one included.
  final int reportsOnProfile;
  final ReportParty? reporter;
  final ReportedProfile? profile;

  /// The family (customer) the profile belongs to, if any.
  final ReportParty? customer;

  /// The profile's uploading agent.
  final ReportParty? agent;

  bool get isOpen => status == 'open';
  String get reasonLabel => ReportReason.labelOf(reason);

  factory AdminReport.fromJson(Map<String, dynamic> j) => AdminReport(
    id: (j['id'] as num).toInt(),
    reason: '${j['reason'] ?? 'other'}',
    status: '${j['status'] ?? 'open'}',
    details: _str(j['details']),
    action: _str(j['action']),
    note: _str(j['note']),
    createdAt: _date(j['created_at']),
    handledAt: _date(j['handled_at']),
    reportsOnProfile: (j['reports_on_profile'] as num?)?.toInt() ?? 1,
    reporter: _party(j['reporter']),
    profile: j['profile'] is Map<String, dynamic>
        ? ReportedProfile.fromJson(j['profile'] as Map<String, dynamic>)
        : null,
    customer: _party(j['customer']),
    agent: _party(j['agent']),
  );
}

/// A reporter, the family or the uploading agent.
class ReportParty {
  const ReportParty({
    required this.id,
    required this.fullName,
    this.type,
    this.phone,
    this.agentCode,
    this.status,
  });

  final int id;
  final String fullName;

  /// Reporters only: `customer` or `agent`.
  final String? type;
  final String? phone;
  final String? agentCode;
  final String? status;

  bool get isCustomer => type == 'customer';

  factory ReportParty.fromJson(Map<String, dynamic> j) => ReportParty(
    id: (j['id'] as num?)?.toInt() ?? 0,
    fullName: '${j['full_name'] ?? ''}',
    type: _str(j['type']),
    phone: _str(j['phone']),
    agentCode: _str(j['agent_code']),
    status: _str(j['status']),
  );
}

class ReportedProfile {
  const ReportedProfile({required this.id, required this.fullName, this.profileCode, this.status});

  final int id;
  final String fullName;
  final String? profileCode;
  final String? status;

  factory ReportedProfile.fromJson(Map<String, dynamic> j) => ReportedProfile(
    id: (j['id'] as num).toInt(),
    fullName: '${j['full_name'] ?? ''}',
    profileCode: _str(j['profile_code']),
    status: _str(j['status']),
  );
}

ReportParty? _party(Object? v) => v is Map<String, dynamic> ? ReportParty.fromJson(v) : null;

String? _str(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
