import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'display_backend.dart';

class CliDisplayBackend implements OasisDisplayBackend {
  const CliDisplayBackend({this.run});

  final Future<ProcessResult> Function(String, List<String>)? run;

  static const _bus = 'org.oasis.Displays';
  static const _path = '/org/oasis/Displays';

  Future<String?> _call(String method,
      [List<String> sig = const [], List<String> args = const []]) async {
    if (kIsWeb) return null;
    try {
      final r = await (run ?? Process.run)('busctl', [
        '--json=short',
        '--user',
        'call',
        _bus,
        _path,
        _bus,
        method,
        ...sig,
        ...args,
      ]);
      if (r.exitCode != 0) return null;
      return r.stdout.toString();
    } on ProcessException {
      return null;
    }
  }

  static String? _decodeString(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List &&
          decoded.isNotEmpty &&
          decoded.first is Map &&
          (decoded.first as Map)['data'] is List) {
        final data = (decoded.first as Map)['data'] as List;
        if (data.isNotEmpty && data.first is String) {
          return data.first as String;
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  @override
  Future<List<OasisDisplay>> displays() async {
    final out = _decodeString(await _call('GetOutputs'));
    if (out == null) return const [];
    try {
      final list = jsonDecode(out);
      if (list is! List) return const [];
      return [for (final e in list) ?OasisDisplay.fromJson(e)];
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> setDisplay(OasisDisplay display) =>
      _call('SetOutputs', const ['s'], [jsonEncode([display.toJson()])])
          .then((_) {});

  @override
  Future<void> identifyDisplays() => _call('Identify').then((_) {});
}
