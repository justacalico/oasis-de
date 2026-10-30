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
  })  : _home = home ?? Platform.environment['HOME'] ?? '/',
        _runProcess = runProcess ?? Process.run;

  final String _home;
  final FilesProcessRunner _runProcess;

  @override
  Future<List<FileItem>> list(String dir, {bool showHidden = false}) async {
    final items = <FileItem>[];
    await for (final entity in Directory(dir).list(followLinks: false)) {
      final name = entity.path.split('/').last;
      if (!showHidden && name.startsWith('.')) continue;
      final stat = await entity.stat();
      items.add(
        FileItem(
          path: entity.path,
          name: name,
          isDir: stat.type == FileSystemEntityType.directory,
          size: stat.size,
          modified: stat.modified,
        ),
      );
    }
    return items;
  }

  @override
  Future<List<FileItem>> search(
    String root,
    String query, {
    int limit = 200,
  }) async {
    final needle = query.toLowerCase();
    final found = <FileItem>[];
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
        if (item.isDir) pending.add(item.path);
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
    for (final base in ['/media', '/run/media/$_user', '/mnt']) {
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

  @override
  Future<void> mkdir(String parent, String name) =>
      Directory('$parent/$name').create(recursive: true);

  @override
  Future<void> rename(String path, String newName) {
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
      final target = '$destDir/$name';
      if (move) {
        if (FileSystemEntity.typeSync(path) ==
            FileSystemEntityType.directory) {
          await Directory(path).rename(target);
        } else {
          await File(path).rename(target);
        }
      } else {
        await _copy(path, target);
      }
    }
  }

  Future<void> _copy(String from, String to) async {
    if (FileSystemEntity.typeSync(from) ==
        FileSystemEntityType.directory) {
      await Directory(to).create(recursive: true);
      await for (final e in Directory(from).list()) {
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
