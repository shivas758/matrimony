import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/profile.dart';
import '../services/api_client.dart';
import '../services/profile_service.dart';
import 'profile_filters.dart';

/// Paginated profile list + filters + locally saved presets.
class ProfilesState extends ChangeNotifier {
  ProfilesState(this._service);

  static const _presetsKey = 'filter_presets_v1';

  final ProfileService _service;

  ProfileFilters _filters = ProfileFilters.empty;
  final List<Profile> _profiles = [];
  List<FilterPreset> _presets = [];

  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  int _total = 0;
  Timer? _searchDebounce;

  ProfileFilters get filters => _filters;
  List<Profile> get profiles => List.unmodifiable(_profiles);
  List<FilterPreset> get presets => List.unmodifiable(_presets);
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  int get total => _total;
  bool get hasMore => _profiles.length < _total;
  bool get isEmpty => !_loading && _error == null && _profiles.isEmpty;

  Future<void> refresh() => _load(reset: true);

  Future<void> setFilters(ProfileFilters next) async {
    _filters = next;
    await _load(reset: true);
  }

  /// Debounced so typing in the search box doesn't hammer the API.
  void setSearch(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _filters = _filters.copyWith(query: text, clearQuery: text.isEmpty);
      _load(reset: true);
    });
  }

  Future<void> setSort(String sort) => setFilters(_filters.copyWith(sort: sort));

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !hasMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final page = await _service.list(_filters.toQuery(page: _page + 1, limit: AppConfig.pageSize));
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

  /// Replaces one row in place after an edit, avoiding a full reload.
  void replaceProfile(Profile updated) {
    final i = _profiles.indexWhere((p) => p.id == updated.id);
    if (i >= 0) {
      _profiles[i] = updated;
      notifyListeners();
    }
  }

  void removeProfile(int id) {
    _profiles.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _profiles.clear();
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _service.list(_filters.toQuery(page: _page, limit: AppConfig.pageSize));
      _total = page.total;
      _profiles
        ..clear()
        ..addAll(page.profiles);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ presets

  Future<void> loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_presetsKey) ?? [];
    _presets = raw
        .map((s) {
          try {
            return FilterPreset.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<FilterPreset>()
        .toList();
    notifyListeners();
  }

  Future<void> savePreset(String name) async {
    final next = [..._presets.where((p) => p.name != name), FilterPreset(name: name, filters: _filters)];
    await _writePresets(next);
  }

  Future<void> deletePreset(String name) =>
      _writePresets(_presets.where((p) => p.name != name).toList());

  Future<void> applyPreset(FilterPreset preset) => setFilters(preset.filters);

  Future<void> _writePresets(List<FilterPreset> next) async {
    _presets = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_presetsKey, next.map((p) => jsonEncode(p.toJson())).toList());
    notifyListeners();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
