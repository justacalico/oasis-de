import 'package:flutter/foundation.dart';

import 'app_update.dart';
import 'update_checker.dart';

class UpdateService extends ChangeNotifier {
  UpdateService({
    UpdateChecker? checker,
    Future<String> Function()? currentVersion,
  })  : _checker = checker ?? UpdateChecker(),
        _currentVersion = currentVersion ?? (() async => '0.0.0');

  final UpdateChecker _checker;
  final Future<String> Function() _currentVersion;

  AppUpdate? _update;
  bool _checking = false;
  bool _failed = false;
  Future<AppUpdate?>? _inFlight;

  AppUpdate? get update => _update;
  bool get checking => _checking;
  bool get failed => _failed;
  String get releasesPageUrl => _checker.releasesUrl;

  Future<AppUpdate?> check() {
    final existing = _inFlight;
    if (existing != null) return existing;
    return _inFlight = _run().whenComplete(() => _inFlight = null);
  }

  Future<AppUpdate?> _run() async {
    _checking = true;
    _failed = false;
    notifyListeners();
    try {
      final version = await _currentVersion();
      final update = await _checker.check(version);
      _update = update;
      return update;
    } catch (_) {
      _failed = true;
      return null;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }
}
