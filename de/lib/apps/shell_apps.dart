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
        builder: (context) => const NotesWindow(),
      ),
    ];

class NotesWindow extends StatefulWidget {
  const NotesWindow({super.key});

  @override
  State<NotesWindow> createState() => _NotesWindowState();
}

class _NotesWindowState extends State<NotesWindow> {
  final _controller = TextEditingController();

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
