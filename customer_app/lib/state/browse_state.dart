import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/profile.dart';
import '../services/api_client.dart';
import '../services/profile_service.dart';
import 'browse_filters.dart';

/// Paginated Browse list + filters + debounced search (SPEC §9.11 Gandharva 3).
///
/// The server answers with `access` (SPEC §9.12): 'guest' → locked teaser
/// cards (no name; no name search), 'full' → normal cards.
/// A 403 `account_*` (suspended) is a state of its own rather than an error.
class BrowseState extends ChangeNotifier {
  BrowseState(this._service);

  final ProfileService _service;

  BrowseFilters _filters = BrowseFilters.empty;
  final List<Profile> _profiles = [];

  /// Interest changes made on the detail screen, so list cards update
  /// without reloading the whole list. Cleared on every reload.
  final Map<int, ({String? status, bool interested})> _interestOverrides = {};

  bool _loading = false;
  bool _loadingMore = false;
  bool _started = false;
  int? _customerId;
  String? _error;
  String? _blockedCode;
  int _page = 1;
  int _total = 0;
  String? _access;
  Timer? _searchDebounce;

  BrowseFilters get filters => _filters;
  List<Profile> get profiles => List.unmodifiable(_profiles);
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;

  /// `account_suspended` etc. (403).
  String? get blockedCode => _blockedCode;
  int get total => _total;
  bool get hasMore => _profiles.length < _total;

  /// The access level of the last answer; null before the first one.
  String? get access => _access;
  bool get isGuest => _access != 'full';
  bool get isEmpty => !_loading && _error == null && _blockedCode == null && _profiles.isEmpty;

  /// Loads once per signed-in customer; a different customer starts clean.
  Future<void> ensureLoaded(int customerId) async {
    if (_started && _customerId == customerId) return;
    _customerId = customerId;
    _started = true;
    _filters = BrowseFilters.empty;
    _access = null;
    await _load(reset: true);
  }

  /// The account's access changed (e.g. approval + payment unlocked it):
  /// reload so the cards switch between guest and full. Search and the
  /// gender default start fresh.
  Future<void> syncAccess(String accountAccess) async {
    if (!_started || _loading || _access == null || _access == accountAccess) return;
    _filters = _filters.copyWith(clearGender: true, clearQuery: true);
    await _load(reset: true);
  }

  Future<void> refresh() => _load(reset: true);

  Future<void> setFilters(BrowseFilters next) async {
    _filters = next;
    await _load(reset: true);
  }

  /// Bride / Groom toggle; tapping the selected one again clears it.
  Future<void> setGender(String? gender) =>
      setFilters(gender == null ? _filters.copyWith(clearGender: true) : _filters.copyWith(gender: gender));

  /// Debounced so typing in the search box doesn't hammer the API.
  void setSearch(String text) {
    _searchDebounce?.cancel();
    final trimmed = text.trim();
    if ((_filters.query ?? '') == trimmed) return;
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _filters = _filters.copyWith(query: trimmed, clearQuery: trimmed.isEmpty);
      _load(reset: true);
    });
  }

  Future<void> setSort(String sort) => setFilters(_filters.copyWith(sort: sort));

  Map<String, dynamic> _query(int page) {
    final f = isGuest ? _filters.forGuest() : _filters;
    return f.toQuery(page: page, limit: AppConfig.pageSize);
  }

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !hasMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final page = await _service.list(_query(_page + 1));
      _page += 1;
      _total = page.total;
      _profiles.addAll(page.profiles);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Records an interest change made on the detail screen.
  void noteInterest(int profileId, {String? status, required bool interested}) {
    _interestOverrides[profileId] = (status: status, interested: interested);
    notifyListeners();
  }

  /// Whether the card should show the "Interested" chip.
  bool isInterested(Profile p) => _interestOverrides[p.id]?.interested ?? p.isInterested;

  String? interestStatusOf(Profile p) {
    final o = _interestOverrides[p.id];
    return o == null ? p.interestStatus : o.status;
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _profiles.clear();
      _interestOverrides.clear();
    }
    _loading = true;
    _error = null;
    _blockedCode = null;
    notifyListeners();
    try {
      final page = await _service.list(_query(_page));
      _access = page.access;
      _total = page.total;
      // With full access the server picks the opposite gender of my first
      // paid profile — show it on the toggle.
      if (_filters.gender == null && page.gender != null) {
        _filters = _filters.copyWith(gender: page.gender);
      }
      _profiles
        ..clear()
        ..addAll(page.profiles);
    } on ApiException catch (e) {
      if (e.isAccountBlocked) {
        _blockedCode = e.code;
      } else {
        _error = e.message;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
