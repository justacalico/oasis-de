import 'dart:io';

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

class DesktopAppEntry {
  const DesktopAppEntry({
    required this.id,
    required this.name,
    required this.argv,
    this.iconPath,
  });

  final String id;
  final String name;
  final List<String> argv;
  final String? iconPath;
}

List<String> desktopSearchDirs() {
  final home = Platform.environment['HOME'] ?? '';
  final dataHome =
      Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
  final dirs = <String>['$dataHome/applications'];
  final dataDirs = Platform.environment['XDG_DATA_DIRS'] ??
      '/usr/local/share:/usr/share';
  for (final d in dataDirs.split(':')) {
    dirs.add('$d/applications');
  }
  return dirs;
}

List<String> _iconSearchRoots() {
  final home = Platform.environment['HOME'] ?? '';
  final dataHome =
      Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
  final roots = <String>['$dataHome/icons'];
  final dataDirs = Platform.environment['XDG_DATA_DIRS'] ??
      '/usr/local/share:/usr/share';
  for (final d in dataDirs.split(':')) {
    roots.add('$d/icons');
    roots.add('$d/pixmaps');
  }
  return roots;
}

const _iconSizes = [
  '256x256',
  '128x128',
  '96x96',
  '64x64',
  '48x48',
  '32x32',
  '24x24',
  '16x16',
];

String? findIconPath(String icon, {List<String>? roots}) {
  if (icon.isEmpty) return null;
  if (icon.startsWith('/')) {
    return File(icon).existsSync() ? icon : null;
  }
  for (final root in roots ?? _iconSearchRoots()) {
    for (final size in _iconSizes) {
      final p = '$root/hicolor/$size/apps/$icon.png';
      if (File(p).existsSync()) return p;
    }
    final direct = '$root/$icon.png';
    if (File(direct).existsSync()) return direct;
  }
  return null;
}

List<String> parseExecLine(String exec, String name, String? icon) {
  final tokens = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < exec.length; i++) {
    final ch = exec[i];
    if (ch == '"') {
      quoted = !quoted;
    } else if (ch == ' ' && !quoted) {
      if (buf.isNotEmpty) {
        tokens.add(buf.toString());
        buf.clear();
      }
    } else {
      buf.write(ch);
    }
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());
  final out = <String>[];
  for (final token in tokens) {
    if (token == '%c') {
      out.add(name);
    } else if (token == '%i') {
      if (icon != null && icon.isNotEmpty) {
        out.add('--icon');
        out.add(icon);
      }
    } else if (!token.startsWith('%')) {
      out.add(token);
    }
  }
  return out;
}

DesktopAppEntry? parseDesktopEntry(String id, String contents,
    {String? Function(String icon) resolveIcon = findIconPath}) {
  var inEntry = false;
  String? name;
  String? exec;
  String? icon;
  var hidden = false;
  var noDisplay = false;
  var terminal = false;
  var isApp = false;
  for (final raw in contents.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      inEntry = line == '[Desktop Entry]';
      continue;
    }
    if (!inEntry || !line.contains('=')) continue;
    final eq = line.indexOf('=');
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim();
    switch (key) {
      case 'Type':
        isApp = value == 'Application';
      case 'Name':
        name ??= value;
      case 'Exec':
        exec ??= value;
      case 'Icon':
        icon ??= value;
      case 'NoDisplay':
        noDisplay = value == 'true';
      case 'Hidden':
        hidden = value == 'true';
      case 'Terminal':
        terminal = value == 'true';
    }
  }
  if (!isApp || hidden || noDisplay || terminal) return null;
  if (name == null || name.isEmpty || exec == null || exec.isEmpty) {
    return null;
  }
  final argv = parseExecLine(exec, name, icon);
  if (argv.isEmpty) return null;
  return DesktopAppEntry(
      id: id, name: name, argv: argv, iconPath: resolveIcon(icon ?? ''));
}

Future<List<DesktopAppEntry>> loadDesktopEntries(
    {List<String>? dirs}) async {
  final found = <String, DesktopAppEntry>{};
  for (final dirPath in dirs ?? desktopSearchDirs()) {
    final dir = Directory(dirPath);
    if (!await dir.exists()) continue;
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.desktop')) {
        continue;
      }
      final id = entity.path
          .split('/')
          .last
          .replaceAll('.desktop', '');
      final contents = await entity.readAsString();
      final entry = parseDesktopEntry(id, contents);
      if (entry != null) found[id] = entry;
    }
  }
  return found.values.toList();
}

OasisApp desktopAppToOasis(DesktopAppEntry entry) => OasisApp(
      id: 'desktop:${entry.id}',
      name: entry.name,
      icon: Icons.apps,
      iconColors: const [Color(0xFF8E8E93), Color(0xFF48484A)],
      iconPath: entry.iconPath,
      exec: entry.argv,
      builder: (_) => const SizedBox.shrink(),
    );
