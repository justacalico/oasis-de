import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/apps/shell_apps.dart';
import 'package:oasis_files/oasis_files.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';

class _FakeBackend extends FilesBackend {
  _FakeBackend(this.tree);

  final Map<String, List<FileItem>> tree;
  final opened = <String>[];
  final trashed = <String>[];
  final made = <String>[];
  final renamed = <String>[];
  final pasted = <String>[];
  var failList = false;

  @override
  Future<List<FileItem>> list(String dir, {bool showHidden = false}) async {
    if (failList) throw StateError('no dir');
    final items = tree[dir] ?? [];
    return items
        .where((e) => showHidden || !e.name.startsWith('.'))
        .toList();
  }

  @override
  Future<List<FileItem>> search(
    String root,
    String query, {
    int limit = 200,
  }) async {
    final needle = query.toLowerCase();
    final found = <FileItem>[];
    final pending = [root];
    while (pending.isNotEmpty && found.length < limit) {
      final d = pending.removeAt(0);
      for (final i in tree[d] ?? <FileItem>[]) {
        if (i.name.toLowerCase().contains(needle)) found.add(i);
        if (i.isDir) pending.add(i.path);
      }
    }
    return found;
  }

  @override
  Future<List<FileBookmark>> bookmarks() async => [
        const FileBookmark(kind: BookmarkKind.home, path: '/home/u'),
        const FileBookmark(kind: BookmarkKind.downloads, path: '/dl'),
        const FileBookmark(
          kind: BookmarkKind.mount,
          path: '/media/usb',
          label: 'usb',
        ),
        const FileBookmark(kind: BookmarkKind.root, path: '/'),
      ];

  @override
  Future<void> mkdir(String parent, String name) async =>
      made.add('$parent/$name');

  @override
  Future<void> rename(String path, String newName) async =>
      renamed.add('$path->$newName');

  @override
  Future<void> paste(
    List<String> paths,
    String destDir, {
    required bool move,
  }) async =>
      pasted.add('${paths.join(",")}>$destDir:${move ? "mv" : "cp"}');

  @override
  Future<void> trash(List<String> paths) async => trashed.addAll(paths);

  @override
  Future<void> open(String path) async => opened.add(path);
}

class _FailImage extends ImageProvider<_FailImage> {
  @override
  Future<_FailImage> obtainKey(_) async => this;

  @override
  ImageStreamCompleter loadImage(a, b) =>
      OneFrameImageStreamCompleter(Future.error('bad image'));
}

FileItem _file(String path, {int size = 10, DateTime? modified}) =>
    FileItem(
      path: path,
      name: path.split('/').last,
      isDir: false,
      size: size,
      modified: modified ?? DateTime(2024, 5, 4, 10),
    );

FileItem _dir(String path) =>
    FileItem(path: path, name: path.split('/').last, isDir: true);

_FakeBackend _backend() => _FakeBackend({
      '/home/u': [
        _dir('/home/u/docs'),
        _file('/home/u/a.txt', size: 100),
        _file('/home/u/b.png', size: 3000,
            modified: DateTime(2024, 6, 1)),
        _file('/home/u/.hidden'),
      ],
      '/home/u/docs': [_file('/home/u/docs/report.pdf', size: 9)],
    });

FilesState _state(_FakeBackend b) => FilesState(backend: b);

void main() {
  test('FileItem classifies extensions', () {
    FileItem f(String n) => FileItem(path: '/x/$n', name: n, isDir: false);
    expect(f('a.png').isImage, isTrue);
    expect(f('a.png').isText, isFalse);
    expect(f('s.mp3').isAudio, isTrue);
    expect(f('v.mkv').isVideo, isTrue);
    expect(f('x.tar.gz').isArchive, isTrue);
    expect(f('d.dart').isText, isTrue);
    expect(f('p.pdf').isPdf, isTrue);
    expect(f('noext').extension, '');
    expect(f('.dotfile').extension, '');
    expect(_dir('/x/d').isImage, isFalse);
    expect(fileIcon(_dir('/x/d')), Icons.folder);
    expect(fileIcon(f('i.jpg')), Icons.image);
    expect(fileIcon(f('m.wav')), Icons.music_note);
    expect(fileIcon(f('v.mp4')), Icons.movie);
    expect(fileIcon(f('z.zip')), Icons.folder_zip);
    expect(fileIcon(f('r.pdf')), Icons.picture_as_pdf);
    expect(fileIcon(f('x.bin')), Icons.description);
  });

  test('state browses, sorts, searches and selects', () async {
    final b = _backend();
    final s = _state(b);
    await s.init('/home/u');
    expect(s.dir, '/home/u');
    expect(s.bookmarks.length, 4);
    expect(s.entries.map((e) => e.name),
        ['docs', 'a.txt', 'b.png']);

    s.toggleHidden();
    await Future<void>.delayed(Duration.zero);
    expect(s.entries.any((e) => e.name == '.hidden'), isTrue);

    s.setSort(FilesSort.size);
    expect(s.entries[2].name, 'a.txt');
    s.setSort(FilesSort.size);
    expect(s.entries[1].name, 'b.png');
    s.setSort(FilesSort.date);
    expect(s.entries[1].name, 'b.png');
    s.setSort(FilesSort.type);
    expect(s.entries[1].name, '.hidden');
    s.setSort(FilesSort.name);
    expect(s.entries[1].name, '.hidden');

    await s.setQuery('report');
    expect(s.entries.single.name, 'report.pdf');
    await s.setQuery('');
    await s.setQuery('');

    await s.cd('/home/u/docs');
    expect(s.entries.single.name, 'report.pdf');
    await s.up();
    expect(s.dir, '/home/u');
    await s.cd('/');
    await s.up();
    expect(s.dir, '/');
    await s.cd('/home/u');

    final item = s.entries.first;
    s.select(item);
    expect(s.singleSelection, item);
    s.select(item, additive: true);
    expect(s.selection, isEmpty);
    s.selectAll();
    expect(s.selection.length, s.entries.length);
    s.clearSelection();
    s.clearSelection();
    s.toggleGrid();
    expect(s.gridView, isTrue);
    s.dispose();
  });

  test('state file operations delegate to the backend', () async {
    final b = _backend();
    final s = _state(b);
    await s.init('/home/u');

    await s.newFolder('New');
    expect(b.made, ['/home/u/New']);

    s.select(s.entries[1]);
    await s.renameSelected('renamed.txt');
    expect(b.renamed, ['/home/u/a.txt->renamed.txt']);
    await s.renameSelected('nope');

    s.select(s.entries[0]);
    await s.open(s.entries[0]);
    expect(s.dir, '/home/u/docs');

    await s.open(_file('/home/u/docs/report.pdf'));
    expect(b.opened, ['/home/u/docs/report.pdf']);

    s.selectAll();
    s.copy(cut: true);
    expect(s.clipboardCut, isTrue);
    await s.cd('/home/u');
    await s.paste();
    expect(b.pasted.single, contains('mv'));
    expect(s.hasClipboard, isFalse);

    s.select(s.entries.first);
    s.copy();
    s.copy();
    expect(s.clipboard, isNotEmpty);
    await s.paste();
    expect(b.pasted.last, contains('cp'));

    s.select(s.entries.first);
    await s.trashSelection();
    expect(b.trashed, isNotEmpty);
    await s.trashSelection();
    s.dispose();
  });

  test('state reports listing errors', () async {
    final b = _backend()..failList = true;
    final s = _state(b);
    await s.init('/nope');
    expect(s.error, '/nope');
    s.dispose();
  });

  test('default backend is the io backend', () {
    expect(FilesState(), isA<FilesState>());
  });

  test('IoFilesBackend works on a real temp tree', () async {
    final root = Directory.systemTemp.createTempSync('oasisfiles');
    addTearDown(() => root.delete(recursive: true));
    Directory('${root.path}/sub').createSync();
    File('${root.path}/a.txt').writeAsStringSync('hi');
    File('${root.path}/sub/deep.txt').writeAsStringSync('x');
    File('${root.path}/.h').writeAsStringSync('h');

    final ran = <List<String>>[];
    final b = IoFilesBackend(
      home: root.path,
      runProcess: (exe, args) async {
        ran.add([exe, ...args]);
        return ProcessResult(0, exe == 'gio' ? 0 : 0, '', '');
      },
    );

    var items = await b.list(root.path);
    expect(items.map((e) => e.name), containsAll(['sub', 'a.txt']));
    expect(items.any((e) => e.name == '.h'), isFalse);
    items = await b.list(root.path, showHidden: true);
    expect(items.any((e) => e.name == '.h'), isTrue);

    final found = await b.search(root.path, 'deep');
    expect(found.single.name, 'deep.txt');

    await b.mkdir(root.path, 'made');
    expect(Directory('${root.path}/made').existsSync(), isTrue);

    await b.rename('${root.path}/a.txt', 'b.txt');
    expect(File('${root.path}/b.txt').existsSync(), isTrue);
    await b.rename('${root.path}/sub', 'sub2');
    expect(Directory('${root.path}/sub2').existsSync(), isTrue);

    await b.paste(['${root.path}/b.txt'], '${root.path}/sub2', move: false);
    expect(File('${root.path}/sub2/b.txt').existsSync(), isTrue);
    await b.paste(['${root.path}/sub2'], '${root.path}/made', move: false);
    expect(
      File('${root.path}/made/sub2/deep.txt').existsSync(),
      isTrue,
    );
    await b.paste(['${root.path}/b.txt'], '${root.path}/made', move: true);
    expect(File('${root.path}/made/b.txt').existsSync(), isTrue);
    await b.paste(['${root.path}/made'], root.path, move: true);

    await b.trash(['${root.path}/made']);
    expect(ran.last.first, 'gio');
    await b.open('${root.path}/b.txt');
    expect(ran.last.first, 'xdg-open');

    final marks = await b.bookmarks();
    expect(marks.any((m) => m.kind == BookmarkKind.home), isTrue);
    expect(marks.any((m) => m.kind == BookmarkKind.root), isTrue);
  });

  test('IoFilesBackend bookmarks lists mounted volumes', () async {
    final mounts = Directory.systemTemp.createTempSync('oasis-mounts');
    addTearDown(() => mounts.deleteSync(recursive: true));
    Directory('${mounts.path}/usb').createSync();
    final b = IoFilesBackend(
      home: '/nonexistent-home',
      mountRoots: [mounts.path, '${mounts.path}/missing'],
    );
    final marks = await b.bookmarks();
    final mounts2 = marks.where((m) => m.kind == BookmarkKind.mount);
    expect(mounts2.single.label, 'usb');
  });

  test('IoFilesBackend trash propagates failure', () async {
    final b = IoFilesBackend(
      runProcess: (exe, args) async => ProcessResult(0, 1, '', 'denied'),
    );
    expect(() => b.trash(['/x']), throwsStateError);
  });

  Widget host(FilesState s) => OasisHost(
        appearance: OasisAppearance(),
        updates: UpdateService(currentVersion: () async => '1'),
        setLocale: (_) {},
        child: FilesHome(state: s, startDir: '/home/u'),
      );

  testWidgets('files home browses and selects', (tester) async {
    final b = _backend();
    final s = _state(b);
    await pumpOasis(tester, host(s), size: const Size(900, 600));
    await tester.pumpAndSettle();
    expect(find.text('a.txt'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('File System'), findsOneWidget);
    expect(find.text('usb'), findsOneWidget);
    expect(find.text('3 items'), findsOneWidget);

    await tester.tap(find.text('a.txt'));
    await tester.pump();
    expect(find.textContaining('a.txt ·'), findsOneWidget);
    expect(find.text('Copy'), findsWidgets);

    await tester.tap(find.text('docs'), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.text('docs'), warnIfMissed: false);
    await tester.pump();
    s.dispose();
  });

  testWidgets('files home ops: dialogs, search, grid, hidden, menu',
      (tester) async {
    final b = _backend();
    final s = _state(b);
    await pumpOasis(tester, host(s), size: const Size(900, 600));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'MadeDir');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(b.made, ['/home/u/MadeDir']);

    await tester.tap(find.text('a.txt'));
    await tester.pump();
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(find.text('Paste'), findsOneWidget);
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(b.pasted, isNotEmpty);

    await tester.tap(find.text('Move to trash'));
    await tester.pumpAndSettle();
    expect(b.trashed, isNotEmpty);

    final grid = find.byTooltip('Grid view');
    await tester.tap(grid);
    await tester.pump();
    expect(find.byType(GridView), findsOneWidget);
    await tester.tap(find.byTooltip('List view'));
    await tester.pump();

    await tester.tap(find.byTooltip('Show hidden files'));
    await tester.pumpAndSettle();
    expect(find.text('.hidden'), findsOneWidget);

    await tester.enterText(
      find.byType(EditableText).at(1),
      'report',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('Clear search'), findsOneWidget);
    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('a.txt'), findsOneWidget);

    final ctx = tester.getCenter(find.text('a.txt'));
    await tester.tapAt(ctx, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a.txt').first, warnIfMissed: false);
    await tester.pump();
    s.dispose();
  });

  testWidgets('files context menu actions and keyboard paths',
      (tester) async {
    final b = _backend();
    final s = _state(b);
    await pumpOasis(tester, host(s), size: const Size(900, 600));
    await tester.pumpAndSettle();

    final ctx = tester.getCenter(find.text('a.txt'));
    await tester.tapAt(ctx, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(b.opened, ['/home/u/a.txt']);

    await tester.tapAt(ctx, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy').last);
    await tester.pumpAndSettle();
    expect(s.hasClipboard, isTrue);

    await tester.tapAt(ctx, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cut'));
    await tester.pumpAndSettle();
    expect(s.clipboardCut, isTrue);

    await tester.tapAt(ctx, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to trash').last);
    await tester.pumpAndSettle();
    expect(b.trashed, contains('/home/u/a.txt'));

    await tester.tapAt(ctx, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'zz.txt');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(b.renamed, ['/home/u/a.txt->zz.txt']);

    await tester.enterText(find.byType(EditableText).at(1), 'report');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('report.pdf'), findsOneWidget);
    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Downloads'));
    await tester.pumpAndSettle();
    expect(s.dir, '/dl');

    await s.cd('/home/u');
    await tester.pumpAndSettle();
    s.select(s.entries[1]);
    s.select(s.entries[2], additive: true);
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    s.dispose();
  });

  testWidgets('grid view renders image thumbnails', (tester) async {
    final b = _FakeBackend({
      '/g': [
        FileItem(path: '/g/ok.png', name: 'ok.png', isDir: false),
        FileItem(
          path: '/g/bad.png',
          name: 'bad.png',
          isDir: false,
          thumb: _FailImage(),
        ),
        FileItem(path: '/g/a.txt', name: 'a.txt', isDir: false),
      ],
    });
    final s = _state(b);
    await pumpOasis(tester, host(s), size: const Size(900, 600));
    await s.cd('/g');
    s.toggleGrid();
    s.select(s.entries.first);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
    expect(find.byIcon(Icons.image), findsWidgets);
    s.dispose();
  });

  testWidgets('shell files app builder produces a window', (tester) async {
    final apps = buildShellApps(
      lookupOasisLocalizations(const Locale('en')),
      version: '1.0.0',
      appearance: OasisAppearance(),
      wallpaper: OasisWallpaperService(),
      updates: UpdateService(currentVersion: () async => '1'),
      setLocale: (_) {},
    );
    final files = apps.firstWhere((a) => a.id == 'files');
    await tester.pumpWidget(
      wrapOasis(
        Builder(builder: files.builder),
        size: const Size(900, 600),
      ),
    );
    await tester.pump();
    expect(find.byType(FilesHome), findsOneWidget);
  });

  testWidgets('files home empty, error and navigation', (tester) async {
    final b = _FakeBackend({'/empty': []});
    final s = _state(b);
    await pumpOasis(tester, host(s), size: const Size(900, 600));
    await tester.pumpAndSettle();
    await s.cd('/empty');
    await tester.pumpAndSettle();
    expect(find.text('This folder is empty'), findsOneWidget);

    await s.setQuery('zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching files'), findsOneWidget);

    b.failList = true;
    await s.cd('/gone');
    await tester.pumpAndSettle();
    expect(find.text("Can't open /gone"), findsOneWidget);

    b.failList = false;
    b.tree['/gone'] = [_file('/gone/x.txt')];
    await s.cd('/gone');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(EditableText).first,
      '/home/u',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(s.dir, '/home/u');
    await tester.tap(find.byTooltip('Up'));
    await tester.pumpAndSettle();
    expect(s.dir, '/home');
    s.dispose();
  });
}
