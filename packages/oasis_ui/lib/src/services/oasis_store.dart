import 'package:shared_preferences/shared_preferences.dart';

abstract class OasisStore {
  String? read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class MemoryOasisStore extends OasisStore {
  final _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async =>
      _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}

class PrefsOasisStore extends OasisStore {
  PrefsOasisStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  String? read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}
