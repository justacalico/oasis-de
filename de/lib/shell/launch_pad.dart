import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'shell_controller.dart';

class ShellLaunchPad extends StatefulWidget {
  const ShellLaunchPad({super.key, required this.controller});

  final ShellController controller;

  @override
  State<ShellLaunchPad> createState() => _ShellLaunchPadState();
}

class _ShellLaunchPadState extends State<ShellLaunchPad> {
  static const _cellWidth = 148.0;
  static const _cellHeight = 118.0;

  final _field = TextEditingController();
  final _pages = PageController();
  var _page = 0;
  var _selected = -1;
  var _columns = 1;
  var _perPage = 1;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _field.dispose();
    _pages.dispose();
    super.dispose();
  }

  List<OasisApp> get _results =>
      widget.controller.filterApps(_field.text);

  void _open(OasisApp app) {
    widget.controller.openApp(app);
    _field.clear();
    setState(() => _selected = -1);
  }

  void _submit() {
    final results = _results;
    if (results.isEmpty) return;
    _open(results[_selected < 0 ? 0 : _selected]);
  }

  void _move(int delta) {
    final results = _results;
    if (results.isEmpty) return;
    setState(() {
      _selected = _selected < 0
          ? (delta < 0 ? results.length - 1 : 0)
          : (_selected + delta).clamp(0, results.length - 1);
      final target = _selected ~/ _perPage;
      if (target != _page && _pages.hasClients) {
        _pages.jumpToPage(target);
      }
    });
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.controller.closeOverlays();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _submit();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _move(_columns);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _move(-_columns);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_selected < 0) return false;
      _move(1);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_selected < 0) return false;
      _move(-1);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final size = MediaQuery.sizeOf(context);
    _columns = (size.width / _cellWidth).floor().clamp(3, 8);
    _perPage = _columns *
        ((size.height - 210) / _cellHeight).floor().clamp(2, 6);
    final results = _results;
    if (_selected >= results.length) _selected = -1;
    final pageCount = (results.length / _perPage).ceil();

    return GestureDetector(
      onTap: widget.controller.closeOverlays,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          color: const Color(0xFF000000)
              .withValues(alpha: p.isDark ? 0.5 : 0.32),
          child: Column(
            children: [
              const SizedBox(height: 52),
              SizedBox(
                width: 320,
                child: OasisSearchField(
                  hint: l10n.launcherHint,
                  controller: _field,
                  autofocus: true,
                  fontSize: 15,
                  onChanged: (_) =>
                      setState(() => _selected = -1),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          l10n.launcherNoResults,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color:
                                      const Color(0xFFFFFFFF)),
                        ),
                      )
                    : PageView.builder(
                        controller: _pages,
                        itemCount: pageCount,
                        onPageChanged: (i) =>
                            setState(() => _page = i),
                        itemBuilder: (context, page) {
                          final start = page * _perPage;
                          final end = (start + _perPage)
                              .clamp(0, results.length);
                          return Center(
                            child: SizedBox(
                              width: _columns * _cellWidth,
                              child: GridView.count(
                                crossAxisCount: _columns,
                                shrinkWrap: true,
                                physics:
                                    const NeverScrollableScrollPhysics(),
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio:
                                    _cellWidth / _cellHeight,
                                children: [
                                  for (var i = start; i < end; i++)
                                    _LaunchPadIcon(
                                      app: results[i],
                                      selected: i == _selected,
                                      onTap: () =>
                                          _open(results[i]),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (pageCount > 1)
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: 30, top: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < pageCount; i++)
                        GestureDetector(
                          onTap: () => _pages.animateToPage(
                            i,
                            duration: const Duration(
                                milliseconds: 240),
                            curve: Curves.easeOutCubic,
                          ),
                          child: Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFFFFF)
                                  .withValues(
                                      alpha: i == _page
                                          ? 0.95
                                          : 0.35),
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaunchPadIcon extends StatelessWidget {
  const _LaunchPadIcon({
    required this.app,
    required this.selected,
    required this.onTap,
  });

  final OasisApp app;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFFFFF).withValues(alpha: 0.2)
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OasisAppIcon(
              icon: app.icon,
              colors: app.iconColors,
              iconPath: app.iconPath,
              size: 60,
            ),
            const SizedBox(height: 8),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      fontSize: 12,
                      color: const Color(0xFFFFFFFF),
                      shadows: [
                        const Shadow(
                          color: Color(0x80000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
