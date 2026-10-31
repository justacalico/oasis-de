import 'dart:async';
import 'dart:convert';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../wayland/wayland_service.dart';

class WaylandDisplayBackend implements OasisDisplayBackend {
  WaylandDisplayBackend(this._wayland, {this.onIdentify, this.store});

  final WaylandService _wayland;
  final VoidCallback? onIdentify;
  final OasisStore? store;

  static const _storeKey = 'display.config';

  @override
  Future<List<OasisDisplay>> displays() async => [
        for (final o in _wayland.outputs)
          OasisDisplay(
            name: o.name,
            description: o.description,
            x: o.x,
            y: o.y,
            width: o.width,
            height: o.height,
            scale: o.scale,
            refreshMhz: o.refreshMhz,
            transform: o.transform,
            enabled: o.enabled,
            primary: o.primary,
            powered: o.powered,
            physWidthMm: o.physWidthMm,
            physHeightMm: o.physHeightMm,
            modes: [
              for (final m in o.modes)
                OasisDisplayMode(
                  width: m.width,
                  height: m.height,
                  refreshMhz: m.refreshMhz,
                  preferred: m.preferred,
                ),
            ],
          ),
      ];

  @override
  Future<void> setDisplay(OasisDisplay d) async {
    await _wayland.configureOutput(
      d.name,
      x: d.x,
      y: d.y,
      width: d.width,
      height: d.height,
      refreshMhz: d.refreshMhz,
      scale: d.scale,
      transform: d.transform,
      enabled: d.enabled,
    );
    _persist(d);
  }

  @override
  Future<void> identifyDisplays() async => onIdentify?.call();

  List<OasisDisplay> _saved() {
    final raw = store?.read(_storeKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [for (final e in list) ?OasisDisplay.fromJson(e)];
    } on FormatException {
      return const [];
    }
  }

  void _persist(OasisDisplay d) {
    final saved = _saved();
    saved.removeWhere((e) => e.name == d.name);
    saved.add(d);
    store?.write(_storeKey, jsonEncode([for (final e in saved) e.toJson()]));
  }

  void restore() {
    final saved = _saved();
    if (saved.isEmpty) return;
    void apply() {
      if (_wayland.outputs.isEmpty) return;
      _wayland.removeListener(apply);
      for (final d in saved) {
        setDisplay(d);
      }
    }

    _wayland.addListener(apply);
    apply();
  }
}

class OasisDisplaysObject extends DBusObject {
  OasisDisplaysObject(this._backend)
    : super(DBusObjectPath('/org/oasis/Displays'));

  final OasisDisplayBackend _backend;
  void Function()? onIdentify;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    switch (methodCall.name) {
      case 'GetOutputs':
        final list = await _backend.displays();
        return DBusMethodSuccessResponse([
          DBusString(jsonEncode([for (final d in list) d.toJson()])),
        ]);
      case 'SetOutputs':
        final raw = (methodCall.values[0] as DBusString).value;
        final list = jsonDecode(raw);
        if (list is List) {
          for (final e in list) {
            final d = OasisDisplay.fromJson(e);
            if (d != null) await _backend.setDisplay(d);
          }
        }
        return DBusMethodSuccessResponse();
      case 'Identify':
        onIdentify?.call();
        await _backend.identifyDisplays();
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

class DisplaysDaemon {
  DisplaysDaemon(
    this._backend, {
    DBusClient Function()? connect,
    this.onIdentify,
  }) : _connect = connect ?? DBusClient.session;

  final OasisDisplayBackend _backend;
  final DBusClient Function() _connect;
  void Function()? onIdentify;
  DBusClient? _bus;
  OasisDisplaysObject? _obj;
  var started = false;

  Future<void> start() async {
    if (started) return;
    try {
      final bus = _bus ?? _connect();
      _bus = bus;
      final obj = _obj ?? OasisDisplaysObject(_backend)
        ..onIdentify = onIdentify;
      _obj = obj;
      await bus.registerObject(obj);
      final reply = await bus.requestName(
        'org.oasis.Displays',
        flags: {DBusRequestNameFlag.doNotQueue},
      );
      started = reply == DBusRequestNameReply.primaryOwner;
      if (!started) {
        await bus.unregisterObject(obj);
      }
    } on Object catch (e) {
      debugPrint('Oasis: displays daemon failed to start: $e');
    }
  }

  Future<void> stop() async {
    final obj = _obj;
    if (obj != null) await _bus?.unregisterObject(obj);
    if (started) await _bus?.releaseName('org.oasis.Displays');
    _obj = null;
    started = false;
  }
}
