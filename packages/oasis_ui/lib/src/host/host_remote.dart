import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/oasis_colors.dart';
import '../theme/oasis_theme.dart';
import '../update/app_update.dart';
import '../update/update_service.dart';
import '../widgets/oasis_host.dart';
import 'host_link.dart';
import 'host_protocol.dart';

void sendHostRequest(
  OasisHostLink link,
  String method,
  Map<String, Object?> params,
) =>
    unawaited(_sendHostRequest(link, method, params));

Future<void> _sendHostRequest(
  OasisHostLink link,
  String method,
  Map<String, Object?> params,
) async {
  try {
    await link.request(method, params);
  } catch (e) {
    debugPrint('Oasis host: $method failed: $e');
  }
}

class RemoteOasisAppearance extends OasisAppearanceApi {
  RemoteOasisAppearance(this._link, {
    OasisThemeMode themeMode = OasisThemeMode.light,
    Color? accent,
  })  : _themeMode = themeMode,
        _accent = accent;

  final OasisHostLink _link;
  OasisThemeMode _themeMode;
  Color? _accent;

  @override
  OasisThemeMode get themeMode => _themeMode;
  @override
  Color? get accent => _accent;

  @override
  set themeMode(OasisThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    _send('setThemeMode', {'mode': mode.name});
  }

  @override
  set accent(Color? color) {
    if (color == _accent) return;
    _accent = color;
    notifyListeners();
    _send('setAccent', {'accent': hostAccentToJson(color)});
  }

  void _apply(OasisThemeMode mode, Color? accent) {
    if (mode == _themeMode && accent == _accent) return;
    _themeMode = mode;
    _accent = accent;
    notifyListeners();
  }

  void _send(String method, Map<String, Object?> params) =>
      sendHostRequest(_link, method, params);
}

class RemoteOasisUpdateService extends OasisUpdateApi {
  RemoteOasisUpdateService(this._link, this._snapshot);

  final OasisHostLink _link;
  OasisUpdateSnapshot _snapshot;

  @override
  AppUpdate? get update => _snapshot.update;
  @override
  bool get checking => _snapshot.checking;
  @override
  bool get failed => _snapshot.failed;
  @override
  bool get installing => _snapshot.installing;
  @override
  bool get installDone => _snapshot.installDone;
  @override
  bool get installFailed => _snapshot.installFailed;
  @override
  String get releasesPageUrl => _snapshot.releasesPageUrl;

  void _apply(OasisUpdateSnapshot snapshot) {
    if (snapshot == _snapshot) return;
    _snapshot = snapshot;
    notifyListeners();
  }

  @override
  Future<AppUpdate?> check() async =>
      hostAppUpdateFromJson((await _link.request('checkUpdates'))['update']);

  @override
  Future<bool> install() async =>
      (await _link.request('installUpdate'))['ok'] as bool? ?? false;
}

/// Client side of the host contract. Connects over any [OasisHostLink]
/// and exposes the same objects the shell hands to in-process apps.
class OasisHostConnection {
  OasisHostConnection._({
    required this.link,
    required this.appearance,
    required this.updates,
    required this.locale,
    required this.openUrl,
  });

  final OasisHostLink link;
  final RemoteOasisAppearance appearance;
  RemoteOasisUpdateService? updates;
  final ValueNotifier<Locale?> locale;
  ValueChanged<String>? openUrl;
  StreamSubscription<Map<String, Object?>>? _sub;

  static Future<OasisHostConnection> connect(OasisHostLink link) async {
    final connection = OasisHostConnection._(
      link: link,
      appearance: RemoteOasisAppearance(link),
      updates: null,
      locale: ValueNotifier(null),
      openUrl: null,
    );
    connection._sub = link.events.listen(connection._onEvent);
    final state = await link.request('getState');
    connection.appearance._apply(
      OasisThemeMode.values.asNameMap()[state['themeMode']] ??
          OasisThemeMode.light,
      hostAccentFromJson(state['accent']),
    );
    final updatesJson = state['updates'];
    connection.updates = updatesJson == null
        ? null
        : RemoteOasisUpdateService(
            link,
            OasisUpdateSnapshot.fromJson(updatesJson as Map),
          );
    connection.locale.value =
        hostLocaleFromTag(state['locale'] as String?);
    connection.openUrl = state['openUrl'] == true
        ? (String url) => sendHostRequest(link, 'openUrl', {'url': url})
        : null;
    return connection;
  }

  void setLocale(Locale? newLocale) {
    locale.value = newLocale;
    sendHostRequest(link, 'setLocale', {'locale': hostLocaleToTag(newLocale)});
  }



  void _onEvent(Map<String, Object?> event) {
    switch (event['event']) {
      case 'appearance':
        appearance._apply(
          OasisThemeMode.values.asNameMap()[event['themeMode']] ??
              appearance.themeMode,
          hostAccentFromJson(event['accent']),
        );
      case 'locale':
        locale.value = hostLocaleFromTag(event['locale'] as String?);
      case 'updates':
        updates?._apply(OasisUpdateSnapshot.fromJson(event));
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    appearance.dispose();
    updates?.dispose();
    locale.dispose();
    await link.close();
  }
}

/// Drop-in [OasisHost] for apps running outside the shell process.
/// Rebuilds when the connection's locale changes, like the shell does.
class RemoteOasisHost extends StatefulWidget {
  const RemoteOasisHost({
    super.key,
    required this.connection,
    required this.child,
  });

  final OasisHostConnection connection;
  final Widget child;

  @override
  State<RemoteOasisHost> createState() => _RemoteOasisHostState();
}

class _RemoteOasisHostState extends State<RemoteOasisHost> {
  @override
  Widget build(BuildContext context) {
    final connection = widget.connection;
    return AnimatedBuilder(
      animation: connection.locale,
      builder: (context, _) => OasisHost(
        appearance: connection.appearance,
        updates: connection.updates,
        setLocale: connection.setLocale,
        locale: connection.locale.value,
        openUrl: connection.openUrl,
        child: widget.child,
      ),
    );
  }
}
