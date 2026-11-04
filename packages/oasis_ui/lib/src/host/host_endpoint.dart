import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../theme/oasis_colors.dart';
import '../theme/oasis_theme.dart';
import '../update/update_service.dart';
import 'host_protocol.dart';

/// Serves the host contract over [OasisHostLink] transports. The shell
/// owns one endpoint per session; every transport (in-process or dbus)
/// forwards to it, so there is exactly one implementation of the
/// contract's behaviour.
class OasisHostEndpoint {
  OasisHostEndpoint({
    required OasisAppearanceApi appearance,
    OasisUpdateApi? updates,
    required ValueListenable<Locale?> locale,
    required ValueChanged<Locale?> setLocale,
    ValueChanged<String>? openUrl,
  })  : _appearance = appearance,
        _updates = updates,
        _locale = locale,
        _setLocale = setLocale,
        _openUrl = openUrl {
    appearance.addListener(_emitAppearance);
    updates?.addListener(_emitUpdates);
    locale.addListener(_emitLocale);
  }

  final OasisAppearanceApi _appearance;
  final OasisUpdateApi? _updates;
  final ValueListenable<Locale?> _locale;
  final ValueChanged<Locale?> _setLocale;
  final ValueChanged<String>? _openUrl;

  final _events = StreamController<Map<String, Object?>>.broadcast();

  Stream<Map<String, Object?>> get events => _events.stream;

  Future<Map<String, Object?>> handleRequest(
    String method,
    Map<String, Object?> params,
  ) async {
    switch (method) {
      case 'getState':
        return {
          'themeMode': _appearance.themeMode.name,
          'accent': hostAccentToJson(_appearance.accent),
          'locale': hostLocaleToTag(_locale.value),
          'openUrl': _openUrl != null,
          'updates': _updates == null
              ? null
              : OasisUpdateSnapshot.of(_updates).toJson(),
        };
      case 'setThemeMode':
        _appearance.themeMode =
            OasisThemeMode.values.asNameMap()[params['mode']] ??
                _appearance.themeMode;
        return const {};
      case 'setAccent':
        _appearance.accent = hostAccentFromJson(params['accent']);
        return const {};
      case 'setLocale':
        _setLocale(hostLocaleFromTag(params['locale'] as String?));
        return const {};
      case 'openUrl':
        _openUrl?.call(params['url'] as String? ?? '');
        return const {};
      case 'checkUpdates':
        final update = await _updates?.check();
        return {'update': update == null ? null : hostAppUpdateToJson(update)};
      case 'installUpdate':
        return {'ok': await _updates?.install() ?? false};
      default:
        throw ArgumentError.value(method, 'method', 'unknown host method');
    }
  }

  void _emitAppearance() => _events.add({
        'event': 'appearance',
        'themeMode': _appearance.themeMode.name,
        'accent': hostAccentToJson(_appearance.accent),
      });

  void _emitLocale() => _events.add({
        'event': 'locale',
        'locale': hostLocaleToTag(_locale.value),
      });

  void _emitUpdates() {
    final updates = _updates;
    if (updates == null) return;
    _events.add({
      'event': 'updates',
      ...OasisUpdateSnapshot.of(updates).toJson(),
    });
  }

  void dispose() {
    _appearance.removeListener(_emitAppearance);
    _updates?.removeListener(_emitUpdates);
    _locale.removeListener(_emitLocale);
    unawaited(_events.close());
  }
}
