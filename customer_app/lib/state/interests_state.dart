import 'package:flutter/foundation.dart';

import '../models/profile.dart';
import '../services/api_client.dart';
import '../services/profile_service.dart';

/// My interests (GET /customer/interests), newest first. The detail screen
/// asks for a reload after marking or withdrawing so the Interested tab is
/// never stale.
class InterestsState extends ChangeNotifier {
  InterestsState(this._service);

  final ProfileService _service;

  List<Interest> _interests = [];
  bool _loading = false;
  bool _loaded = false;
  int? _customerId;
  String? _error;
  String? _blockedCode;
  bool _locked = false;

  List<Interest> get interests => List.unmodifiable(_interests);
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  /// `account_*` (403) — the account is no longer active.
  String? get blockedCode => _blockedCode;

  /// 403 `unlock_required` — no full access yet (SPEC §9.12).
  bool get locked => _locked;
  bool get isEmpty =>
      _loaded && _error == null && _blockedCode == null && !_locked && _interests.isEmpty;

  /// Loads once per signed-in customer; `force` reloads.
  Future<void> load(int customerId, {bool force = false}) async {
    final sameCustomer = _customerId == customerId;
    if (_loading || (sameCustomer && _loaded && !force)) return;
    if (!sameCustomer) {
      _interests = [];
      _loaded = false;
      _customerId = customerId;
    }
    _loading = true;
    _error = null;
    _blockedCode = null;
    _locked = false;
    notifyListeners();
    try {
      _interests = await _service.myInterests();
      _loaded = true;
    } on ApiException catch (e) {
      if (e.isUnlockRequired) {
        _interests = [];
        _locked = true;
        _loaded = true;
      } else if (e.isAccountBlocked) {
        _blockedCode = e.code;
      } else {
        _error = e.message;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Withdraws a pending interest and replaces the row in place. Throws
  /// [ApiException] so the screen can show the message.
  Future<Interest> withdraw(int interestId) async {
    final updated = await _service.withdraw(interestId);
    final i = _interests.indexWhere((x) => x.id == interestId);
    if (i >= 0) {
      // The withdraw response carries no profile summary; keep the one we have.
      _interests[i] = Interest(
        id: updated.id,
        status: updated.status,
        note: updated.note,
        createdAt: updated.createdAt ?? _interests[i].createdAt,
        decidedAt: updated.decidedAt,
        accessExpiresAt: updated.accessExpiresAt,
        daysLeft: updated.daysLeft,
        profile: updated.profile ?? _interests[i].profile,
        fromProfile: updated.fromProfile ?? _interests[i].fromProfile,
      );
      notifyListeners();
    }
    return updated;
  }
}
