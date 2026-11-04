import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../wayland/wayland_service.dart';

const kScreenshotAppId = 'screenshot';

/// What a capture request covers: a region picked by dragging on the
/// snip overlay, or the whole output layout.
enum ScreenshotMode { region, fullscreen }

/// Grabs compositor frames through [WaylandService.capture], encodes
/// them as PNG and files them under `~/Pictures/Screenshots`. The most
/// recent frame is kept around so the Screenshot app can show a
/// preview. Everything external is injectable so tests can run fully
/// in-memory.
class ScreenshotService extends ChangeNotifier {
  ScreenshotService({WaylandService? wayland, Directory? directory})
    : _wayland = wayland,
      _directory = directory;

  final WaylandService? _wayland;
  final Directory? _directory;

  ui.Image? lastCapture;
  String? lastPath;

  /// PNG encoder, swappable so tests can exercise the failure path.
  Future<ByteData?> Function(ui.Image image) encodePng = (image) =>
      image.toByteData(format: ui.ImageByteFormat.png);

  /// Folder captures are written to, resolved lazily so tests and web
  /// builds never touch the real filesystem by accident.
  Directory get screenshotsDir =>
      _directory ??
      Directory('${Platform.environment['HOME'] ?? ''}/Pictures/Screenshots');

  /// Captures [rect] in logical layout coordinates, stores it as a PNG
  /// and updates [lastCapture]. Returns the saved path, or null when
  /// the compositor gave no frame back.
  Future<String?> captureRegion(Rect rect) async {
    final frame = await _wayland?.capture(rect);
    if (frame == null ||
        frame.width <= 0 ||
        frame.height <= 0 ||
        frame.rgba.length < frame.width * frame.height * 4 ||
        kIsWeb) {
      return null;
    }
    final image = await _decode(frame);
    if (image == null) return null;
    final png = await encodePng(image);
    if (png == null) {
      image.dispose();
      return null;
    }
    try {
      final dir = screenshotsDir..createSync(recursive: true);
      final path = _freePath(dir);
      File(path).writeAsBytesSync(png.buffer.asUint8List());
      lastCapture?.dispose();
      lastCapture = image;
      lastPath = path;
      notifyListeners();
      return path;
    } on FileSystemException {
      image.dispose();
      return null;
    }
  }

  static Future<ui.Image?> _decode(OasisCapture frame) {
    final done = Completer<ui.Image?>();
    ui.decodeImageFromPixels(
      frame.rgba,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      done.complete,
      rowBytes: frame.width * 4,
    );
    return done.future;
  }

  String _freePath(Directory dir) {
    var path = '${dir.path}/${_fileName(clock.now())}';
    for (var i = 2; File(path).existsSync(); i++) {
      path = '${dir.path}/${_fileName(clock.now(), suffix: ' ($i)')}';
    }
    return path;
  }

  static String _fileName(DateTime t, {String suffix = ''}) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Screenshot ${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}.${two(t.minute)}.${two(t.second)}$suffix.png';
  }

  @override
  void dispose() {
    lastCapture?.dispose();
    super.dispose();
  }
}
