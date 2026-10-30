import 'package:flutter/foundation.dart';

import 'file_item.dart';
import 'files_backend.dart';

enum FilesSort { name, date, size, type }

class FilesState extends ChangeNotifier {
  FilesState({FilesBackend? backend})
      : _backend = backend ?? IoFilesBackend();

  final FilesBackend _backend;

  String dir = '';
  List<FileItem> _entries = [];
  bool loading = false;
  String? error;
  FilesSort sort = FilesSort.name;
  bool ascending = true;
  bool showHidden = false;
  bool gridView = false;
  String query = '';
  final Set<String> selection = {};
  List<String> _clipboard = [];
  bool _clipboardCut = false;
  List<FileBookmark> bookmarks = [];

  bool get hasClipboard => _clipboard.isNotEmpty;
  List<String> get clipboard => _clipboard;
  bool get clipboardCut => _clipboardCut;

  List<FileItem> get entries {
    final items = List.of(_entries);
    int cmp(FileItem a, FileItem b) => switch (sort) {
          FilesSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          FilesSort.date =>
            (b.modified ?? DateTime(0)).compareTo(a.modified ?? DateTime(0)),
          FilesSort.size => a.size.compareTo(b.size),
          FilesSort.type => a.extension.compareTo(b.extension),
        };
    items.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      final r = cmp(a, b);
      return ascending ? r : -r;
    });
    return items;
  }

  List<FileItem> get selectedItems =>
      entries.where((e) => selection.contains(e.path)).toList();

  FileItem? get singleSelection {
    final sel = selectedItems;
    return sel.length == 1 ? sel.first : null;
  }

  Future<void> init(String startDir) async {
    bookmarks = await _backend.bookmarks();
    await cd(startDir);
  }

  Future<void> cd(String target) async {
    dir = target;
    query = '';
    selection.clear();
    await refresh();
  }

  Future<void> up() {
    final i = dir.lastIndexOf('/');
    if (i <= 0) return cd('/');
    return cd(dir.substring(0, i));
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      _entries = query.isEmpty
          ? await _backend.list(dir, showHidden: showHidden)
          : await _backend.search(dir, query);
    } catch (_) {
      error = dir;
      _entries = [];
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> setQuery(String q) async {
    if (q == query) return;
    query = q;
    await refresh();
  }

  void setSort(FilesSort s) {
    if (s == sort) {
      ascending = !ascending;
    } else {
      sort = s;
      ascending = true;
    }
    notifyListeners();
  }

  void toggleHidden() {
    showHidden = !showHidden;
    refresh();
  }

  void toggleGrid() {
    gridView = !gridView;
    notifyListeners();
  }

  void select(FileItem item, {bool additive = false}) {
    if (additive) {
      if (!selection.remove(item.path)) selection.add(item.path);
    } else {
      selection
        ..clear()
        ..add(item.path);
    }
    notifyListeners();
  }

  void selectAll() {
    selection
      ..clear()
      ..addAll(entries.map((e) => e.path));
    notifyListeners();
  }

  void clearSelection() {
    if (selection.isEmpty) return;
    selection.clear();
    notifyListeners();
  }

  Future<void> open(FileItem item) async {
    if (item.isDir) {
      await cd(item.path);
    } else {
      await _backend.open(item.path);
    }
  }

  void copy({bool cut = false}) {
    if (selection.isEmpty) return;
    _clipboard = selection.toList();
    _clipboardCut = cut;
    notifyListeners();
  }

  Future<void> paste() async {
    if (_clipboard.isEmpty) return;
    await _backend.paste(_clipboard, dir, move: _clipboardCut);
    if (_clipboardCut) {
      _clipboard = [];
      _clipboardCut = false;
    }
    await refresh();
  }

  Future<void> newFolder(String name) async {
    await _backend.mkdir(dir, name);
    await refresh();
  }

  Future<void> renameSelected(String newName) async {
    final item = singleSelection;
    if (item == null) return;
    await _backend.rename(item.path, newName);
    selection.clear();
    await refresh();
  }

  Future<void> trashSelection() async {
    if (selection.isEmpty) return;
    await _backend.trash(selection.toList());
    selection.clear();
    await refresh();
  }
}
