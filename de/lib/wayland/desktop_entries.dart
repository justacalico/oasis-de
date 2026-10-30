import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

class DesktopEntryAction {
  const DesktopEntryAction({
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

class DesktopAppEntry {
  const DesktopAppEntry({
    required this.id,
    required this.name,
    required this.argv,
    this.genericName,
    this.keywords = const [],
    this.categories = const [],
    this.iconPath,
    this.terminal = false,
    this.startupNotify = false,
    this.startupWmClass,
    this.actions = const [],
  });

  final String id;
  final String name;
  final List<String> argv;
  final String? genericName;
  final List<String> keywords;
  final List<String> categories;
  final String? iconPath;
  final bool terminal;
  final bool startupNotify;
  final String? startupWmClass;
  final List<DesktopEntryAction> actions;
}

List<String> desktopSearchDirs() {
  final home = Platform.environment['HOME'] ?? '';
  final dataHome =
      Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
  final dirs = <String>['$dataHome/applications'];
  final dataDirs =
      Platform.environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share';
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
  final dataDirs =
      Platform.environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share';
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

const _iconExts = ['png', 'svg'];

String? _systemIconTheme() {
  final home = Platform.environment['HOME'];
  if (home == null) return null;
  for (final p in [
    '$home/.config/gtk-3.0/settings.ini',
    '$home/.config/gtk-4.0/settings.ini',
  ]) {
    try {
      final contents = File(p).readAsStringSync();
      final m = RegExp(
        r'^gtk-icon-theme-name\s*=\s*(.+)$',
        multiLine: true,
      ).firstMatch(contents);
      if (m != null && m.group(1)!.trim().isNotEmpty) {
        return m.group(1)!.trim();
      }
    } catch (_) {}
  }
  return null;
}

class _IconThemeDir {
  const _IconThemeDir({
    required this.name,
    required this.size,
    required this.scale,
    required this.type,
    required this.minSize,
    required this.maxSize,
    required this.threshold,
  });

  final String name;
  final int size;
  final int scale;
  final String type;
  final int minSize;
  final int maxSize;
  final int threshold;
}

class _IconThemeIndex {
  const _IconThemeIndex(this.dirs, this.inherits);

  final List<_IconThemeDir> dirs;
  final List<String> inherits;
}

final _iconIndexCache = <String, _IconThemeIndex?>{};

_IconThemeIndex? _loadIconIndex(String root, String theme) {
  final key = '$root/$theme';
  if (_iconIndexCache.containsKey(key)) return _iconIndexCache[key];
  final file = File('$key/index.theme');
  _IconThemeIndex? index;
  if (file.existsSync()) {
    final sections = <String, Map<String, String>>{};
    var current = '';
    for (final raw in file.readAsStringSync().split('\n')) {
      final line = raw.trim();
      if (line.startsWith('[') && line.endsWith(']')) {
        current = line.substring(1, line.length - 1);
        sections.putIfAbsent(current, () => {});
      } else if (line.contains('=')) {
        final eq = line.indexOf('=');
        sections.putIfAbsent(current, () => {});
        sections[current]!.putIfAbsent(
          line.substring(0, eq).trim(),
          () => line.substring(eq + 1).trim(),
        );
      }
    }
    final meta = sections['Icon Theme'];
    if (meta != null) {
      index = _IconThemeIndex([
        for (final name in [
          ..._splitCsv(meta['Directories']),
          ..._splitCsv(meta['ScaledDirectories']),
        ])
          _parseThemeDir(name, sections[name] ?? const {}),
      ], _splitCsv(meta['Inherits']));
    }
  }
  return _iconIndexCache[key] = index;
}

_IconThemeDir _parseThemeDir(String name, Map<String, String> keys) {
  final size = int.tryParse(keys['Size'] ?? '') ?? 48;
  return _IconThemeDir(
    name: name,
    size: size,
    scale: int.tryParse(keys['Scale'] ?? '') ?? 1,
    type: keys['Type'] ?? 'Fixed',
    minSize: int.tryParse(keys['MinSize'] ?? '') ?? size,
    maxSize: int.tryParse(keys['MaxSize'] ?? '') ?? size,
    threshold: int.tryParse(keys['Threshold'] ?? '') ?? 2,
  );
}

bool _themeDirMatches(_IconThemeDir dir, int size) =>
    _themeDirDistance(dir, size) == 0;

int _themeDirDistance(_IconThemeDir dir, int size) {
  final scaled = dir.size * dir.scale;
  switch (dir.type) {
    case 'Scalable':
      if (size < dir.minSize * dir.scale) {
        return dir.minSize * dir.scale - size;
      }
      if (size > dir.maxSize * dir.scale) {
        return size - dir.maxSize * dir.scale;
      }
      return 0;
    case 'Threshold':
      final diff = (scaled - size).abs();
      return diff <= dir.threshold ? 0 : diff - dir.threshold;
    default:
      return (scaled - size).abs();
  }
}

String? findIconPath(
  String icon, {
  List<String>? roots,
  String? theme,
  int size = 48,
}) {
  if (icon.isEmpty) return null;
  if (icon.startsWith('/')) {
    return File(icon).existsSync() ? icon : null;
  }
  theme ??= _systemIconTheme() ?? 'hicolor';
  final searchRoots = roots ?? _iconSearchRoots();
  final visited = <String>{};
  String? result;
  String? loose;

  String? probe(String path) {
    if (_iconExts.any(path.endsWith) && File(path).existsSync()) {
      return path;
    }
    for (final ext in _iconExts) {
      final p = '$path.$ext';
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  void visit(String themeName) {
    if (result != null || !visited.add(themeName)) return;
    for (final root in searchRoots) {
      if (result != null) return;
      final index = _loadIconIndex(root, themeName);
      if (index == null) {
        for (final s in _iconSizes) {
          loose ??= probe('$root/$themeName/$s/apps/$icon');
        }
        loose ??= probe('$root/$themeName/$icon');
        continue;
      }
      var bestDiff = 1 << 30;
      String? bestHit;
      for (final dir in index.dirs) {
        final hit = probe('$root/$themeName/${dir.name}/$icon');
        if (hit == null) continue;
        if (_themeDirMatches(dir, size)) {
          result = hit;
          return;
        }
        final diff = _themeDirDistance(dir, size);
        if (diff < bestDiff) {
          bestDiff = diff;
          bestHit = hit;
        }
      }
      loose ??= bestHit;
      for (final parent in index.inherits) {
        visit(parent);
      }
    }
  }

  visit(theme);
  visit('hicolor');
  if (result != null) return result;
  if (loose != null) return loose;
  for (final root in searchRoots) {
    final flat = probe('$root/$icon');
    if (flat != null) return flat;
  }
  return null;
}

bool _executableExists(String executable) {
  if (executable.contains('/')) {
    return File(executable).existsSync();
  }
  final path = Platform.environment['PATH'] ?? '';
  for (final dir in path.split(':')) {
    if (dir.isEmpty) continue;
    if (File('$dir/$executable').existsSync()) return true;
  }
  return false;
}

List<String> parseExecLine(String exec, String name, String? icon) {
  final tokens = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < exec.length; i++) {
    final ch = exec[i];
    if (ch == '%' && i + 1 < exec.length && exec[i + 1] == '%') {
      buf.write('\u0001');
      i++;
      continue;
    }
    if (ch == '\\' && i + 1 < exec.length) {
      final n = exec[++i];
      buf.write(switch (n) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        's' => ' ',
        _ => n,
      });
      continue;
    }
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
      out.add(token.replaceAll('\u0001', '%'));
    }
  }
  return out;
}

List<String> _splitList(String? value) => [
  for (final part in (value ?? '').split(';'))
    if (part.trim().isNotEmpty) part.trim(),
];

List<String> _splitCsv(String? value) => [
  for (final part in (value ?? '').split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

String? _localized(Map<String, String> keys, String base, String? locale) {
  final tag = (locale ?? Platform.localeName)
      .split('.')
      .first
      .split('@')
      .first
      .replaceAll('-', '_');
  for (final candidate in [tag, tag.split('_').first]) {
    final v = keys['$base[$candidate]'];
    if (v != null) return v;
  }
  return keys[base];
}

DesktopAppEntry? parseDesktopEntry(
  String id,
  String contents, {
  String? Function(String icon) resolveIcon = findIconPath,
  String? locale,
  String? desktop,
  bool Function(String executable) executableExists = _executableExists,
}) {
  final sections = <String, Map<String, String>>{};
  var current = '';
  for (final raw in contents.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      current = line;
      sections.putIfAbsent(current, () => {});
      continue;
    }
    if (!line.contains('=')) continue;
    final eq = line.indexOf('=');
    sections.putIfAbsent(current, () => {});
    sections[current]!.putIfAbsent(
      line.substring(0, eq).trim(),
      () => line.substring(eq + 1).trim(),
    );
  }

  final entry = sections['[Desktop Entry]'];
  if (entry == null || entry['Type'] != 'Application') return null;
  if (entry['Hidden'] == 'true' || entry['NoDisplay'] == 'true') {
    return null;
  }

  final desktopName =
      desktop ?? Platform.environment['XDG_CURRENT_DESKTOP'] ?? 'Oasis';
  final onlyShowIn = _splitList(entry['OnlyShowIn']);
  if (onlyShowIn.isNotEmpty && !onlyShowIn.contains(desktopName)) {
    return null;
  }
  final notShowIn = _splitList(entry['NotShowIn']);
  if (notShowIn.contains(desktopName)) return null;

  final tryExec = entry['TryExec'];
  if (tryExec != null && tryExec.isNotEmpty && !executableExists(tryExec)) {
    return null;
  }

  final name = _localized(entry, 'Name', locale);
  final exec = entry['Exec'];
  if (name == null || name.isEmpty || exec == null || exec.isEmpty) {
    return null;
  }
  final icon = entry['Icon'];
  final argv = parseExecLine(exec, name, icon);
  if (argv.isEmpty) return null;

  final actions = <DesktopEntryAction>[];
  for (final actionId in _splitList(entry['Actions'])) {
    final section = sections['[Desktop Action $actionId]'];
    if (section == null) continue;
    final actionName = _localized(section, 'Name', locale);
    final actionExec = section['Exec'];
    if (actionName == null ||
        actionName.isEmpty ||
        actionExec == null ||
        actionExec.isEmpty) {
      continue;
    }
    final actionArgv = parseExecLine(actionExec, actionName, section['Icon']);
    if (actionArgv.isEmpty) continue;
    actions.add(
      DesktopEntryAction(
        id: actionId,
        name: actionName,
        argv: actionArgv,
        iconPath: section['Icon'] == null
            ? null
            : resolveIcon(section['Icon']!),
      ),
    );
  }

  return DesktopAppEntry(
    id: id,
    name: name,
    argv: argv,
    genericName: _localized(entry, 'GenericName', locale),
    keywords: _splitList(entry['Keywords']),
    categories: _splitList(entry['Categories']),
    iconPath: resolveIcon(icon ?? ''),
    terminal: entry['Terminal'] == 'true',
    startupNotify: entry['StartupNotify'] == 'true',
    startupWmClass: entry['StartupWMClass'],
    actions: actions,
  );
}

Future<List<DesktopAppEntry>> loadDesktopEntries({List<String>? dirs}) =>
    Isolate.run(() => loadDesktopEntriesSync(dirs: dirs));

List<DesktopAppEntry> loadDesktopEntriesSync({List<String>? dirs}) {
  final found = <String, DesktopAppEntry>{};
  for (final dirPath in dirs ?? desktopSearchDirs()) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync()) {
      if (!FileSystemEntity.isFileSync(entity.path) ||
          !entity.path.endsWith('.desktop')) {
        continue;
      }
      final id = entity.path.split('/').last.replaceAll('.desktop', '');
      try {
        final contents = File(entity.path).readAsStringSync();
        final entry = parseDesktopEntry(id, contents);
        if (entry != null) found.putIfAbsent(id, () => entry);
      } catch (_) {}
    }
  }
  return found.values.toList();
}

String? _which(String name) {
  for (final p in (Platform.environment['PATH'] ?? '').split(':')) {
    if (p.isNotEmpty && File('$p/$name').existsSync()) return name;
  }
  return null;
}

const _terminalProbes = {
  'xdg-terminal-exec': <String>[],
  'kgx': ['-e'],
  'gnome-console': ['-e'],
  'alacritty': ['-e'],
  'foot': <String>[],
  'kitty': <String>[],
  'wezterm': ['start', '--'],
  'konsole': ['-e'],
  'gnome-terminal': ['--'],
  'weston-terminal': <String>[],
  'xterm': ['-e'],
};

List<String>? _terminalArgv;

List<String> _terminalPrefix({
  Map<String, String>? environment,
  String? Function(String)? which,
}) {
  if (environment == null && which == null) {
    return _terminalArgv ??= _findTerminal(
      Platform.environment,
      _which,
    );
  }
  return _findTerminal(
    environment ?? Platform.environment,
    which ?? _which,
  );
}

List<String> _findTerminal(
  Map<String, String> environment,
  String? Function(String) which,
) {
  final envTerm = environment['TERMINAL'];
  if (envTerm != null && envTerm.isNotEmpty) return [envTerm, '-e'];
  for (final probe in _terminalProbes.entries) {
    if (which(probe.key) != null) return [probe.key, ...probe.value];
  }
  return const ['x-terminal-emulator', '-e'];
}

OasisApp desktopAppToOasis(
  DesktopAppEntry entry, {
  Map<String, String>? environment,
  String? Function(String)? which,
}) => OasisApp(
  id: 'desktop:${entry.id}',
  name: entry.name,
  icon: Icons.apps,
  iconColors: const [Color(0xFF8E8E93), Color(0xFF48484A)],
  iconPath: entry.iconPath,
  exec: entry.terminal
      ? [
          ..._terminalPrefix(environment: environment, which: which),
          ...entry.argv,
        ]
      : entry.argv,
  builder: (_) => const SizedBox.shrink(),
  actions: [
    for (final a in entry.actions)
      OasisAppAction(name: a.name, exec: a.argv),
  ],
);

Stream<void> watchDesktopDirs({
  List<String>? dirs,
  Duration debounce = const Duration(milliseconds: 300),
}) {
  final controller = StreamController<void>();
  final subs = <StreamSubscription<FileSystemEvent>>[];
  Timer? pending;
  void emit() {
    pending?.cancel();
    pending = Timer(debounce, () {
      if (!controller.isClosed) controller.add(null);
    });
  }

  void watchDir(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      final parent = Directory(File(path).parent.path);
      if (!parent.existsSync()) return;
      late StreamSubscription<FileSystemEvent> parentSub;
      parentSub = parent.watch().listen((_) {
        emit();
        if (dir.existsSync()) {
          subs.remove(parentSub);
          parentSub.cancel();
          watchDir(path);
        }
      });
      subs.add(parentSub);
      return;
    }
    subs.add(dir.watch().listen((_) => emit()));
  }

  for (final dirPath in dirs ?? desktopSearchDirs()) {
    watchDir(dirPath);
  }
  controller.onCancel = () {
    pending?.cancel();
    for (final sub in subs) {
      sub.cancel();
    }
  };
  return controller.stream;
}
