import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../state/settings_state.dart';
import 'settings_row.dart';

class DisplaysPane extends StatefulWidget {
  const DisplaysPane({super.key, required this.state});

  final SettingsState state;

  @override
  State<DisplaysPane> createState() => _DisplaysPaneState();
}

class _DisplaysPaneState extends State<DisplaysPane> {
  final Map<String, OasisDisplay> _draft = {};
  var _dirty = false;
  var _applying = false;
  var _selected = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  List<OasisDisplay> get _current =>
      _dirty ? _draftList : widget.state.displays;

  List<OasisDisplay> get _draftList => [
        for (final d in widget.state.displays) _draft[d.name] ?? d,
      ];

  Future<void> _refresh() async {
    await widget.state.refreshDisplays();
    if (mounted) setState(() => _dirty = false);
  }

  void _setDraft(OasisDisplay d) {
    setState(() {
      _draft[d.name] = d;
      _dirty = true;
    });
  }

  void _revert() {
    setState(() {
      _draft.clear();
      _dirty = false;
    });
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    for (final d in _draftList) {
      await widget.state.applyDisplay(d);
    }
    if (!mounted) return;
    setState(() {
      _applying = false;
      _draft.clear();
      _dirty = false;
    });
  }

  void _move(OasisDisplay d, Offset delta, double pxScale) {
    final dx = (delta.dx / pxScale).round();
    final dy = (delta.dy / pxScale).round();
    var nx = d.x + dx;
    var ny = d.y + dy;
    for (final o in _current) {
      if (o.name == d.name) continue;
      final edges = <double>[
        o.x - d.logicalWidth,
        o.x.toDouble(),
        o.x + o.logicalWidth - d.logicalWidth,
        o.x + o.logicalWidth,
      ];
      for (final e in edges) {
        if ((nx - e).abs() < 24) nx = e.round();
      }
      final vedges = <double>[
        o.y - d.logicalHeight,
        o.y.toDouble(),
        o.y + o.logicalHeight - d.logicalHeight,
        o.y + o.logicalHeight,
      ];
      for (final e in vedges) {
        if ((ny - e).abs() < 24) ny = e.round();
      }
    }
    _setDraft(d.copyWith(x: nx, y: ny));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final displays = _current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l10n.settingsDisplays, style: text.titleLarge),
            const Spacer(),
            if (displays.isNotEmpty)
              OasisButton(
                onPressed: () =>
                    unawaited(widget.state.identifyDisplays()),
                label: l10n.displaysIdentify,
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (displays.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: widget.state.displaysBusy
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    l10n.displaysNone,
                    style: text.bodyMedium,
                  ),
            ),
          )
        else ...[
          DisplayArranger(
            displays: displays,
            selected: _selected,
            onSelect: (i) => setState(() => _selected = i),
            onMove: (d, delta, s) => _move(d, delta, s),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.displaysArrangeHint,
            style: text.bodySmall,
          ),
          const SizedBox(height: 16),
          _displayCard(l10n, text, displays[_selected.clamp(0, displays.length - 1)]),
          const SizedBox(height: 16),
          Row(
            children: [
              const Spacer(),
              if (_dirty) ...[
                OasisButton(
                  onPressed: _revert,
                  label: l10n.displaysRevert,
                ),
                const SizedBox(width: 8),
              ],
              OasisButton(
                onPressed:
                    _dirty && !_applying ? () => unawaited(_apply()) : null,
                variant: OasisButtonVariant.primary,
                label: l10n.displaysApply,
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _brightnessCard(l10n),
      ],
    );
  }

  Widget _displayCard(
      OasisLocalizations l10n, TextTheme text, OasisDisplay d) {
    final resolutions = <String, int>{
      for (final m in d.modes) '${m.width}x${m.height}': 0,
    }.keys.toList();
    if (!resolutions.contains('${d.width}x${d.height}')) {
      resolutions.insert(0, '${d.width}x${d.height}');
    }
    final resKey = '${d.width}x${d.height}';
    final rates = <int>{
      for (final m in d.modes)
        if ('${m.width}x${m.height}' == resKey) m.refreshMhz,
    }.toList()
      ..sort();
    if (!rates.contains(d.refreshMhz)) rates.add(d.refreshMhz);
    final rotation = switch (d.transform) {
      1 => 90,
      2 => 180,
      3 => 270,
      _ => 0,
    };
    final scales = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];
    if (!scales.contains(d.scale)) scales.add(d.scale);
    scales.sort();

    return OasisSection(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.description.isNotEmpty ? d.description : d.name,
                      style: text.titleSmall,
                    ),
                    Text(
                      '${d.name}${d.primary ? ' · ${l10n.displaysPrimary}' : ''}',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              OasisToggle(
                value: d.enabled,
                onChanged: (v) => _setDraft(d.copyWith(enabled: v)),
              ),
            ],
          ),
        ),
        SettingsDropdownRow(
          title: l10n.displaysResolution,
          value: resKey,
          items: resolutions,
          onChanged: (v) {
            final parts = v.split('x');
            _setDraft(d.copyWith(
              width: int.tryParse(parts[0]) ?? d.width,
              height: int.tryParse(parts[1]) ?? d.height,
            ));
          },
        ),
        SettingsDropdownRow(
          title: l10n.displaysRefresh,
          value: d.refreshMhz.toString(),
          items: [for (final r in rates) r.toString()],
          onChanged: (v) =>
              _setDraft(d.copyWith(refreshMhz: int.tryParse(v))),
          labels: {
            for (final r in rates)
              r.toString():
                  _rateLabel((r / 1000 * 100).round() / 100),
          },
        ),
        SettingsDropdownRow(
          title: l10n.displaysScale,
          value: d.scale.toString(),
          items: [for (final s in scales) s.toString()],
          onChanged: (v) =>
              _setDraft(d.copyWith(scale: double.tryParse(v))),
          labels: {for (final s in scales) s.toString(): '${s}x'},
        ),
        SettingsDropdownRow(
          title: l10n.displaysRotation,
          value: rotation.toString(),
          items: const ['0', '90', '180', '270'],
          onChanged: (v) {
            final deg = int.tryParse(v) ?? 0;
            _setDraft(d.copyWith(
              transform: switch (deg) {
                90 => 1,
                180 => 2,
                270 => 3,
                _ => 0,
              },
            ));
          },
          labels: {
            '0': l10n.displaysRotationNone,
            '90': '90°',
            '180': '180°',
            '270': '270°',
          },
        ),
      ],
    );
  }

  Widget _brightnessCard(OasisLocalizations l10n) {
    final b = widget.state.backend;
    return OasisSection(
      children: [
        OasisRow(
          leading: const Icon(Icons.brightness_6, size: 20),
          title: l10n.settingsBrightness,
          trailing: SizedBox(
            width: 180,
            child: OasisSlider(
              value: widget.state.brightness,
              onChanged: b == null
                  ? null
                  : (v) => widget.state.brightnessLevel = v,
            ),
          ),
        ),
        OasisRow(
          leading: const Icon(Icons.nightlight, size: 20),
          title: l10n.settingsNightLight,
          trailing: OasisToggle(
            value: widget.state.nightLightOn,
            onChanged: b == null
                ? null
                : (v) => widget.state.nightLightEnabled = v,
          ),
        ),
      ],
    );
  }

  static String _rateLabel(double hz) =>
      '${hz % 1 == 0 ? hz.toStringAsFixed(0) : hz}Hz';
}

class DisplayArranger extends StatelessWidget {
  const DisplayArranger({
    super.key,
    required this.displays,
    required this.selected,
    required this.onSelect,
    required this.onMove,
  });

  final List<OasisDisplay> displays;
  final int selected;
  final ValueChanged<int> onSelect;
  final void Function(OasisDisplay, Offset, double) onMove;

  @override
  Widget build(BuildContext context) {
    var minX = 0.0, minY = 0.0, maxX = 1.0, maxY = 1.0;
    for (final d in displays) {
      minX = math.min(minX, d.x.toDouble());
      minY = math.min(minY, d.y.toDouble());
      maxX = math.max(maxX, d.x + d.logicalWidth);
      maxY = math.max(maxY, d.y + d.logicalHeight);
    }
    final span = Size(maxX - minX, maxY - minY);

    return AspectRatio(
      aspectRatio: 21 / 9,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pxScale = math.min(
            constraints.maxWidth / span.width,
            constraints.maxHeight / span.height,
          );
          final canvasW = span.width * pxScale;
          final canvasH = span.height * pxScale;
          return Center(
            child: SizedBox(
              width: canvasW,
              height: canvasH,
              child: Stack(
                children: [
                  for (var i = 0; i < displays.length; i++)
                    Positioned(
                      left: (displays[i].x - minX) * pxScale,
                      top: (displays[i].y - minY) * pxScale,
                      child: GestureDetector(
                        onTap: () => onSelect(i),
                        onPanUpdate: (e) =>
                            onMove(displays[i], e.delta, pxScale),
                        child: _ArrangerBox(
                          display: displays[i],
                          selected: i == selected,
                          index: i,
                          width: displays[i].logicalWidth * pxScale,
                          height: displays[i].logicalHeight * pxScale,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ArrangerBox extends StatelessWidget {
  const _ArrangerBox({
    required this.display,
    required this.selected,
    required this.index,
    required this.width,
    required this.height,
  });

  final OasisDisplay display;
  final bool selected;
  final int index;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = display.enabled
        ? theme.colorScheme.primary.withValues(alpha: 0.25)
        : theme.colorScheme.surfaceContainerHighest;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: math.max(16, width),
      height: math.max(16, height),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
          width: selected ? 2 : 1,
        ),
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: theme.textTheme.titleSmall,
        ),
      ),
    );
  }
}
