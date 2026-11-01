class OasisDisplayMode {
  const OasisDisplayMode({
    required this.width,
    required this.height,
    required this.refreshMhz,
    this.preferred = false,
  });

  final int width;
  final int height;
  final int refreshMhz;
  final bool preferred;

  String get label {
    final hz = refreshMhz / 1000;
    final rate = hz == hz.roundToDouble() ? hz.toStringAsFixed(0)
        : hz.toStringAsFixed(2);
    return '${width}x$height @ ${rate}Hz';
  }

  Map<String, Object?> toJson() => {
        'w': width,
        'h': height,
        'refresh': refreshMhz,
        'preferred': preferred,
      };

  static OasisDisplayMode? fromJson(Object? json) {
    if (json is! Map) return null;
    return OasisDisplayMode(
      width: (json['w'] as num?)?.toInt() ?? 0,
      height: (json['h'] as num?)?.toInt() ?? 0,
      refreshMhz: (json['refresh'] as num?)?.toInt() ?? 0,
      preferred: json['preferred'] == true,
    );
  }
}

class OasisDisplay {
  const OasisDisplay({
    required this.name,
    this.description = '',
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.scale = 1,
    this.refreshMhz = 60000,
    this.transform = 0,
    this.enabled = true,
    this.primary = false,
    this.powered = true,
    this.physWidthMm = 0,
    this.physHeightMm = 0,
    this.modes = const [],
  });

  final String name;
  final String description;
  final int x;
  final int y;
  final int width;
  final int height;
  final double scale;
  final int refreshMhz;
  final int transform;
  final bool enabled;
  final bool primary;
  final bool powered;
  final int physWidthMm;
  final int physHeightMm;
  final List<OasisDisplayMode> modes;

  /// Mode size divided by [scale], matching output-layout coordinates.
  double get logicalWidth => scale > 0 ? width / scale : width.toDouble();
  double get logicalHeight =>
      scale > 0 ? height / scale : height.toDouble();

  OasisDisplay copyWith({
    int? x,
    int? y,
    int? width,
    int? height,
    double? scale,
    int? refreshMhz,
    int? transform,
    bool? enabled,
  }) =>
      OasisDisplay(
        name: name,
        description: description,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        scale: scale ?? this.scale,
        refreshMhz: refreshMhz ?? this.refreshMhz,
        transform: transform ?? this.transform,
        enabled: enabled ?? this.enabled,
        primary: primary,
        powered: powered,
        physWidthMm: physWidthMm,
        physHeightMm: physHeightMm,
        modes: modes,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'desc': description,
        'x': x,
        'y': y,
        'w': width,
        'h': height,
        'scale': scale,
        'refresh': refreshMhz,
        'transform': transform,
        'enabled': enabled,
        'primary': primary,
        'powered': powered,
        'physW': physWidthMm,
        'physH': physHeightMm,
        'modes': [for (final m in modes) m.toJson()],
      };

  static OasisDisplay? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'] as String?;
    if (name == null || name.isEmpty) return null;
    return OasisDisplay(
      name: name,
      description: json['desc'] as String? ?? '',
      x: (json['x'] as num?)?.toInt() ?? 0,
      y: (json['y'] as num?)?.toInt() ?? 0,
      width: (json['w'] as num?)?.toInt() ?? 0,
      height: (json['h'] as num?)?.toInt() ?? 0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1,
      refreshMhz: (json['refresh'] as num?)?.toInt() ?? 0,
      transform: (json['transform'] as num?)?.toInt() ?? 0,
      enabled: json['enabled'] != false,
      primary: json['primary'] == true,
      powered: json['powered'] != false,
      physWidthMm: (json['physW'] as num?)?.toInt() ?? 0,
      physHeightMm: (json['physH'] as num?)?.toInt() ?? 0,
      modes: [
        for (final m in (json['modes'] as List<Object?>? ?? const []))
          ?OasisDisplayMode.fromJson(m),
      ],
    );
  }
}

abstract class OasisDisplayBackend {
  Future<List<OasisDisplay>> displays();
  Future<void> setDisplay(OasisDisplay display);
  Future<void> identifyDisplays();
}

class NoopDisplayBackend implements OasisDisplayBackend {
  const NoopDisplayBackend();

  @override
  Future<List<OasisDisplay>> displays() async => const [];

  @override
  Future<void> setDisplay(OasisDisplay display) async {}

  @override
  Future<void> identifyDisplays() async {}
}
