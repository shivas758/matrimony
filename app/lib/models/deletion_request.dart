// Account deletion requests from the public /delete-account page (SPEC §9.20 F).

/// One request as an admin sees it. It is unauthenticated — anyone can type
/// a number — so the admin confirms with the person before completing it.
class DeletionRequest {
  const DeletionRequest({
    required this.id,
    required this.app,
    required this.phone,
    required this.status,
    this.fullName,
    this.reason,
    this.note,
    this.createdAt,
    this.handledAt,
    this.accountExists = false,
  });

  final int id;

  /// `customer` (Wedbook Matrimony) or `agent` (Wedbook Agent).
  final String app;
  final String phone;

  /// `pending`, `done` or `rejected`.
  final String status;
  final String? fullName;
  final String? reason;

  /// The admin's note: what was deleted, or why it was rejected.
  final String? note;
  final DateTime? createdAt;
  final DateTime? handledAt;

  /// An account with this number exists in that app.
  final bool accountExists;

  bool get isPending => status == 'pending';
  bool get isDone => status == 'done';
  bool get isRejected => status == 'rejected';
  bool get isAgentApp => app == 'agent';

  factory DeletionRequest.fromJson(Map<String, dynamic> j) => DeletionRequest(
    id: (j['id'] as num).toInt(),
    app: '${j['app'] ?? 'customer'}',
    phone: '${j['phone'] ?? ''}',
    status: '${j['status'] ?? 'pending'}',
    fullName: _str(j['full_name']),
    reason: _str(j['reason']),
    note: _str(j['note']),
    createdAt: _date(j['created_at']),
    handledAt: _date(j['handled_at']),
    accountExists: j['account_exists'] == true,
  );
}

/// What `POST …/:id/complete` and `…/reject` answer: `{id, status, note, handled_at}`.
class DeletionDecision {
  const DeletionDecision({required this.id, required this.status, this.note, this.handledAt});

  final int id;
  final String status;
  final String? note;
  final DateTime? handledAt;

  factory DeletionDecision.fromJson(Map<String, dynamic> j) => DeletionDecision(
    id: (j['id'] as num?)?.toInt() ?? 0,
    status: '${j['status'] ?? ''}',
    note: _str(j['note']),
    handledAt: _date(j['handled_at']),
  );
}

String? _str(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
