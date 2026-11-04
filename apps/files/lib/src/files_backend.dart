import 'dart:async';
import 'dart:io';

import 'file_item.dart';

typedef FilesProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

abstract class FilesBackend {
  Future<List<FileItem>> list(String dir, {bool showHidden = false});
  Future<List<FileItem>> search(
    String root,
    String query, {
    int limit = 200,
  });
  Future<List<FileBookmark>> bookmarks();
  Future<void> mkdir(String parent, String name);
  Future<void> rename(String path, String newName);
  Future<void> paste(
    List<String> paths,
    String destDir, {
    required bool move,
  });
  Future<void> trash(List<String> paths);
  Future<void> open(String path);
}

class IoFilesBackend implements FilesBackend {
  IoFilesBackend({
    String? home,
    FilesProcessRunner? runProcess,
    List<String>? mountRoots,
    Future<void> Function(FileSystemEntity, String)? renameEntity,
    String Function(String)? resolveLinks,
  })  : _home = home ?? Platform.environment['HOME'] ?? '/',
        _runProcess = runProcess ?? Process.run,
        _mountRoots = mountRoots,
        _renameEntity = renameEntity,
        _resolveLinks = resolveLinks;

  final String _home;
  final FilesProcessRunner _runProcess;
  final List<String>? _mountRoots;
  final Future<void> Function(FileSystemEntity, String)? _renameEntity;
  final String Function(String)? _resolveLinks;

  String _realPath(String path) =>
      (_resolveLinks ??
              (p) => Directory(p).resolveSymbolicLinksSync())(
        path,
      );

  @override
  Future<List<FileItem>> list(String dir, {bool showHidden = false}) async {
    final entities = <FileSystemEntity>[];
    await for (final entity in Directory(dir).list(followLinks: false)) {
      final name = entity.path.split('/').last;
      if (!showHidden && name.startsWith('.')) continue;
      entities.add(entity);
    }
    final stats = await Future.wait([for (final e in entities) e.stat()]);
    return [
      for (var i = 0; i < entities.length; i++)
        FileItem(
          path: entities[i].path,
          name: entities[i].path.split('/').last,
          isDir: stats[i].type == FileSystemEntityType.directory,
          size: stats[i].size,
          modified: stats[i].modified,
        ),
    ];
  }

  @override
  Future<List<FileItem>> search(
    String root,
    String query, {
    int limit = 200,
  }) async {
    final needle = query.toLowerCase();
    final found = <FileItem>[];
    final seen = <String>{};
    try {
      seen.add(_realPath(root));
    } on FileSystemException {
      return found;
    }
    final pending = <String>[root];
    while (pending.isNotEmpty && found.length < limit) {
      final dir = pending.removeAt(0);
      List<FileItem> items;
      try {
        items = await list(dir, showHidden: true);
      } catch (_) {
        continue;
      }
      for (final item in items) {
        if (found.length >= limit) break;
        if (item.name.toLowerCase().contains(needle)) found.add(item);
        if (item.isDir) {
          try {
            if (seen.add(_realPath(item.path))) {
              pending.add(item.path);
            }
          } on FileSystemException {
            continue;
          }
        }
      }
    }
    return found;
  }

  @override
  Future<List<FileBookmark>> bookmarks() async {
    final marks = <FileBookmark>[];
    void add(BookmarkKind kind, String path, [String label = '']) {
      if (Directory(path).existsSync()) {
        marks.add(FileBookmark(kind: kind, path: path, label: label));
      }
    }

    add(BookmarkKind.home, _home);
    add(BookmarkKind.documents, '$_home/Documents');
    add(BookmarkKind.downloads, '$_home/Downloads');
    add(BookmarkKind.pictures, '$_home/Pictures');
    add(BookmarkKind.music, '$_home/Music');
    add(BookmarkKind.videos, '$_home/Videos');
    add(BookmarkKind.trash, '$_home/.local/share/Trash/files');
    for (final base
        in _mountRoots ?? ['/media', '/run/media/$_user', '/mnt']) {
      final dir = Directory(base);
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync()) {
        if (e is Directory) {
          add(BookmarkKind.mount, e.path, e.path.split('/').last);
        }
      }
    }
    add(BookmarkKind.root, '/', '/');
    return marks;
  }

  String get _user => Platform.environment['USER'] ?? '';

  static void _checkName(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/')) {
      throw ArgumentError.value(name, 'name', 'invalid file name');
    }
  }

  static String _uniquePath(String target) {
    var candidate = target;
    for (var i = 2;
        FileSystemEntity.typeSync(candidate) !=
            FileSystemEntityType.notFound;
        i++) {
      final slash = target.lastIndexOf('/');
      final dot = target.lastIndexOf('.');
      final at = dot > slash ? dot : target.length;
      candidate = '${target.substring(0, at)} ($i)${target.substring(at)}';
    }
    return candidate;
  }

  @override
  Future<void> mkdir(String parent, String name) {
    _checkName(name);
    return Directory('$parent/$name').create(recursive: true);
  }

  @override
  Future<void> rename(String path, String newName) {
    _checkName(newName);
    final parent = path.substring(0, path.lastIndexOf('/'));
    final target = '$parent/$newName';
    if (FileSystemEntity.typeSync(path) ==
        FileSystemEntityType.directory) {
      return Directory(path).rename(target);
    }
    return File(path).rename(target);
  }

  @override
  Future<void> paste(
    List<String> paths,
    String destDir, {
    required bool move,
  }) async {
    for (final path in paths) {
      final name = path.split('/').last;
      final target = _uniquePath('$destDir/$name');
      if (move) {
        final isDir = FileSystemEntity.typeSync(path) ==
            FileSystemEntityType.directory;
        final rename = _renameEntity ??
            (FileSystemEntity e, String t) async => e.rename(t);
        try {
          await rename(isDir ? Directory(path) : File(path), target);
        } on FileSystemException {
          // rename fails across filesystems; copy then remove the source.
          await _copy(path, target);
          if (isDir) {
            await Directory(path).delete(recursive: true);
          } else {
            await File(path).delete();
          }
        }
      } else {
        await _copy(path, target);
      }
    }
  }

  Future<void> _copy(String from, String to) async {
    if (FileSystemEntity.isLinkSync(from)) {
      await Link(to).create(await Link(from).target());
      return;
    }
    if (FileSystemEntity.typeSync(from) ==
        FileSystemEntityType.directory) {
      await Directory(to).create(recursive: true);
      await for (final e in Directory(from).list(followLinks: false)) {
        await _copy(e.path, '$to/${e.path.split('/').last}');
      }
    } else {
      await File(from).copy(to);
    }
  }

  @override
  Future<void> trash(List<String> paths) async {
    final r = await _runProcess('gio', ['trash', ...paths]);
    if (r.exitCode != 0) throw StateError('gio trash failed');
  }

  @override
  Future<void> open(String path) async {
    await _runProcess('xdg-open', [path]);
  }
}
