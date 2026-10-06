import 'package:flutter/foundation.dart';

import '../models/master_data.dart';
import '../services/api_client.dart';
import '../services/profile_service.dart';

/// Caches GET /api/masters for the whole session. The registration form
/// needs it while the customer is still pending, and /masters is public, so
/// it never assumes an active account.
class MastersState extends ChangeNotifier {
  MastersState(this._service);

  final ProfileService _service;

  MasterData _data = MasterData.empty;
  bool _loading = false;
  String? _error;

  MasterData get data => _data;
  bool get loading => _loading;
  String? get error => _error;
  bool get isLoaded => _data.communities.isNotEmpty;

  Future<void> load({bool force = false}) async {
    if (_loading || (isLoaded && !force)) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _data = await _service.masters();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
