import 'package:flutter/material.dart';
import 'package:oasis_settings/oasis_settings.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'about_window.dart';

List<OasisApp> buildShellApps(
  OasisLocalizations l10n, {
  required String version,
  required OasisAppearance appearance,
  required OasisWallpaperService wallpaper,
  required UpdateService updates,
  required ValueChanged<Locale?> setLocale,
  Locale? locale,
  ValueChanged<String>? openUrl,
  OasisStore? store,
}) =>
    [
      OasisApp(
        id: 'settings',
        name: l10n.settingsTitle,
        icon: Icons.settings,
        iconColors: const [Color(0xFF8E8E93), Color(0xFF48484A)],
        builder: (context) => OasisHost(
          appearance: appearance,
          updates: updates,
          setLocale: setLocale,
          locale: locale,
          openUrl: openUrl,
          child: SettingsHome(wallpaper: wallpaper),
        ),
      ),
      OasisApp(
        id: 'about',
        name: l10n.menuAbout,
        icon: Icons.water_drop,
        iconColors: const [Color(0xFF4FC3F7), Color(0xFF0078C8)],
        builder: (context) => AboutWindow(version: version),
      ),
      OasisApp(
        id: 'notes',
        name: l10n.appNotes,
        icon: Icons.edit_note,
        iconColors: const [Color(0xFFFFD66E), Color(0xFFE6A817)],
        builder: (context) => NotesWindow(store: store),
      ),
      OasisApp(
        id: 'calculator',
        name: l10n.appCalculator,
        icon: Icons.calculate,
        iconColors: const [Color(0xFF34C759), Color(0xFF1E7D3E)],
        builder: (context) => const CalculatorWindow(),
      ),
    ];

class NotesWindow extends StatefulWidget {
  const NotesWindow({super.key, this.store});

  final OasisStore? store;

  @override
  State<NotesWindow> createState() => _NotesWindowState();
}

class _NotesWindowState extends State<NotesWindow> {
  static const _key = 'notes.content';
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.store?.read(_key) ?? '';
    _controller.addListener(() {
      widget.store?.write(_key, _controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        style: Theme.of(context).textTheme.bodyMedium,
        cursorColor: p.accent,
        decoration: const InputDecoration(border: InputBorder.none),
      ),
    );
  }
}

class CalculatorWindow extends StatefulWidget {
  const CalculatorWindow({super.key});

  @override
  State<CalculatorWindow> createState() => _CalculatorWindowState();
}

class _CalculatorWindowState extends State<CalculatorWindow> {
  String _display = '0';
  double? _acc;
  String? _op;
  bool _fresh = true;

  void _press(String key) {
    setState(() {
      switch (key) {
        case 'C':
          _display = '0';
          _acc = null;
          _op = null;
          _fresh = true;
        case '+':
        case '−':
        case '×':
        case '÷':
          _acc = double.tryParse(_display);
          _op = key;
          _fresh = true;
        case '=':
          final b = double.tryParse(_display) ?? 0;
          final a = _acc ?? 0;
          final r = switch (_op) {
            '+' => a + b,
            '−' => a - b,
            '×' => a * b,
            '÷' => b == 0 ? double.nan : a / b,
            _ => b,
          };
          _display =
              r == r.truncateToDouble() ? '${r.toInt()}' : '$r';
          _acc = null;
          _op = null;
          _fresh = true;
        case '.':
          if (_fresh) {
            _display = '0.';
            _fresh = false;
          } else if (!_display.contains('.')) {
            _display += '.';
          }
        default:
          _display = _fresh ? key : _display + key;
          _fresh = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    const keys = [
      'C', '÷', '×', '−',
      '7', '8', '9', '+',
      '4', '5', '6', '=',
      '1', '2', '3', '.',
      '0',
    ];
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.cardBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _display,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              childAspectRatio: 2.4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final k in keys)
                  OasisButton(
                    label: k,
                    dense: true,
                    onPressed: () => _press(k),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
