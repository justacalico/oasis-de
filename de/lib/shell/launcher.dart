import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'shell_controller.dart';

class ShellLauncher extends StatefulWidget {
  const ShellLauncher({super.key, required this.controller});

  final ShellController controller;

  @override
  State<ShellLauncher> createState() => _ShellLauncherState();
}

class _ShellLauncherState extends State<ShellLauncher> {
  final _field = TextEditingController();
  var _selected = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _field.dispose();
    super.dispose();
  }

  List<OasisApp> get _results => widget.controller.filterApps(_field.text);

  void _open(OasisApp app) {
    widget.controller.openApp(app);
    _field.clear();
    setState(() => _selected = 0);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final results = _results;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(
        () =>
            _selected = results.isEmpty ? 0 : (_selected + 1) % results.length,
      );
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selected = results.isEmpty
            ? 0
            : (_selected - 1 + results.length) % results.length,
      );
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (results.isNotEmpty) {
        _open(results[_selected.clamp(0, results.length - 1)]);
      }
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.controller.closeOverlays();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final style = OasisStyle.of(context);
    final p = style.palette;
    final results = _results;
    _selected = results.isEmpty ? 0 : _selected.clamp(0, results.length - 1);

    return GestureDetector(
      onTap: widget.controller.closeOverlays,
      child: Container(
        color: const Color(0x00000000),
        child: Align(
          alignment: const Alignment(0, -0.55),
          child: GestureDetector(
            onTap: () {},
            child: SizedBox(
              width: (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 560.0),
              child: OasisGlass(
                borderRadius: 18,
                blur: 40,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OasisTextField(
                      controller: _field,
                      autofocus: true,
                      onChanged: (_) => setState(() => _selected = 0),
                      onSubmitted: (_) {
                        if (results.isNotEmpty) {
                          _open(
                            results[_selected.clamp(0, results.length - 1)],
                          );
                        }
                      },
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                      hintText: l10n.launcherHint,
                      hintStyle: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: p.textTertiary),
                      icon: Icon(
                        Icons.search,
                        size: 22,
                        color: p.textTertiary,
                      ),
                    ),
                    if (results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 4),
                        child: Text(
                          l10n.launcherNoResults,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: results.length,
                            itemBuilder: (context, i) {
                              final app = results[i];
                              final selected = i == _selected;
                              return GestureDetector(
                                onTap: () => _open(app),
                                child: Semantics(
                                  button: true,
                                  label: app.name,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? p.selection
                                          : const Color(0x00000000),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        OasisAppIcon(
                                          icon: app.icon,
                                          colors: app.iconColors,
                                          size: 30,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          app.name,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
