import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _scan(String path, RegExp re) {
  final text = File(path).readAsStringSync();
  return {
    for (final m in re.allMatches(text))
      if (m.group(1) != null) m.group(1)!,
  };
}

void main() {
  const compositor = 'de/linux/runner/oasis_compositor.cc';
  const host = 'de/lib/wayland/wayland_host.dart';
  const service = 'de/lib/wayland/wayland_service.dart';
  const controller = 'de/lib/shell/shell_controller.dart';

  test('Dart channel calls are handled natively', () {
    final cc = File(compositor).readAsStringSync();
    final dartCalls = {
      ..._scan(host, RegExp("invokeMethod\\(\\s*'([a-zA-Z]+)'")),
      ..._scan(host, RegExp("invokeMapMethod<[^>]*>\\('([a-zA-Z]+)'")),
    };
    final nativeHandlers = {
      for (final n in _scan(
        compositor,
        RegExp('g_strcmp0\\(name, "([a-zA-Z]+)"\\)'),
      ))
        if (n.startsWith(RegExp('[a-z]'))) n,
    };
    expect(
      dartCalls.difference(nativeHandlers),
      isEmpty,
      reason: 'Dart invokes methods the compositor does not handle',
    );
    expect(
      nativeHandlers.difference(dartCalls),
      isEmpty,
      reason: 'native handles methods Dart never invokes: $cc',
    );
  });

  test('native events are consumed and Dart cases are real events', () {
    final emitted = <String>{};
    for (final path in [
      compositor,
      ...Directory('de/compositor')
          .listSync()
          .whereType<File>()
          .map((f) => f.path),
    ]) {
      for (final line in File(path).readAsLinesSync()) {
        if (line.contains('emit(') || line.contains('emit_id(')) {
          emitted.addAll({
            for (final m in RegExp('"([a-zA-Z]+)"').allMatches(line))
              if (m.group(1) != null) m.group(1)!,
          });
        }
      }
      emitted.addAll(
        _scan(
          path,
          RegExp('"(toplevelClosed|popupClosed|subsurfaceClosed)"'),
        ),
      );
    }
    final cases = _scan(service, RegExp("case '([a-zA-Z]+)':"));
    expect(
      emitted.difference(cases),
      isEmpty,
      reason: 'native emits events Dart never consumes',
    );
    expect(
      cases.difference(emitted),
      isEmpty,
      reason: 'Dart consumes events that are never emitted',
    );
  });

  test('resize edge map matches the xdg enum', () {
    final text = File(controller).readAsStringSync();
    final start = text.indexOf('_waylandResizeEdges');
    final block = text.substring(start, text.indexOf('};', start));
    final keys = [
      for (final m in RegExp(r'(\d+):').allMatches(block)) int.parse(m.group(1)!),
    ];
    expect(keys, [1, 2, 4, 5, 6, 8, 9, 10]);
  });
}
