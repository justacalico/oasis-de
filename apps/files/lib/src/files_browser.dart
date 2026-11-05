import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'file_item.dart';
import 'files_state.dart';
import 'files_tiles.dart';

class FilesBrowser extends StatefulWidget {
  const FilesBrowser({
    super.key,
    required this.state,
    this.extensions,
    this.multiSelect = true,
    this.showViewToggle = true,
    this.onActivate,
    this.onSecondaryTap,
  });

  final FilesState state;
  final Set<String>? extensions;
  final bool multiSelect;
  final bool showViewToggle;
  final ValueChanged<FileItem>? onActivate;
  final void Function(FileItem item, Offset position)? onSecondaryTap;

  @override
  State<FilesBrowser> createState() => _FilesBrowserState();
}

class _FilesBrowserState extends State<FilesBrowser> {
  final _pathCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  Timer? _searchTimer;
  DateTime? _lastTap;
  String? _lastTapPath;

  FilesState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _state.addListener(_syncPath);
    _pathCtrl.text = _state.dir;
  }

  void _syncPath() {
    if (_state.dir != _pathCtrl.text) {
      _pathCtrl.text = _state.dir;
    }
    if (_state.query.isEmpty && _searchCtrl.text.isNotEmpty) {
      _searchCtrl.clear();
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _state.removeListener(_syncPath);
    _pathCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    _searchTimer?.cancel();
    _searchTimer = Timer(
      const Duration(milliseconds: 300),
      () => _state.setQuery(q.trim()),
    );
  }

  List<FileItem> get _items {
    final exts = widget.extensions;
    if (exts == null) return _state.entries;
    return [
      for (final e in _state.entries)
        if (e.isDir || exts.contains(e.extension)) e,
    ];
  }

  void _tap(FileItem item) {
    final now = DateTime.now();
    final last = _lastTap;
    if (_lastTapPath == item.path &&
        last != null &&
        now.difference(last).inMilliseconds < 400) {
      _lastTapPath = null;
      (widget.onActivate ?? _state.open)(item);
      return;
    }
    _lastTapPath = item.path;
    _lastTap = now;
    _state.select(
      item,
      additive: widget.multiSelect &&
          HardwareKeyboard.instance.isControlPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final s = _state;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(
            children: [
              FileToolButton(
                icon: Icons.arrow_upward,
                tooltip: l10n.filesUp,
                onTap: s.up,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OasisTextField(
                  controller: _pathCtrl,
                  filled: true,
                  hintText: l10n.filesLocation,
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) s.cd(v.trim());
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 170,
                child: OasisTextField(
                  controller: _searchCtrl,
                  filled: true,
                  hintText: l10n.filesSearch,
                  icon: const Icon(Icons.search, size: 16),
                  onChanged: _search,
                  onSubmitted: (v) => s.setQuery(v.trim()),
                ),
              ),
              const SizedBox(width: 6),
              FileToolButton(
                icon: s.showHidden
                    ? Icons.visibility
                    : Icons.visibility_off,
                tooltip: l10n.filesShowHidden,
                onTap: s.toggleHidden,
              ),
              if (widget.showViewToggle)
                FileToolButton(
                  icon: s.gridView ? Icons.list : Icons.grid_view,
                  tooltip: s.gridView
                      ? l10n.filesListView
                      : l10n.filesGridView,
                  onTap: s.toggleGrid,
                ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 176,
                child: ListView(
                  padding: const EdgeInsets.only(left: 8),
                  children: [
                    for (final b in s.bookmarks)
                      FileBookmarkTile(
                        label: fileBookmarkLabel(l10n, b),
                        active: s.dir == b.path,
                        onTap: () => s.cd(b.path),
                      ),
                  ],
                ),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: p.textTertiary.withValues(alpha: 0.3),
              ),
              Expanded(child: _body(l10n)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(OasisLocalizations l10n) {
    final s = _state;
    final items = _items;
    if (s.loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (s.error != null) {
      return Center(child: Text(l10n.filesError(s.error!)));
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          s.query.isEmpty ? l10n.filesEmpty : l10n.filesNoResults,
        ),
      );
    }
    if (s.gridView) {
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 110,
          childAspectRatio: 0.85,
        ),
        padding: const EdgeInsets.all(8),
        itemCount: items.length,
        itemBuilder: (context, idx) => _tile(items[idx], grid: true),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      itemCount: items.length,
      itemExtent: 34,
      itemBuilder: (context, idx) => _tile(items[idx], grid: false),
    );
  }

  Widget _tile(FileItem item, {required bool grid}) {
    final s = _state;
    final selected = s.selection.contains(item.path);
    final onSecondaryTap = widget.onSecondaryTap;
    return GestureDetector(
      onTapDown: (_) => _tap(item),
      onSecondaryTapUp: onSecondaryTap == null
          ? null
          : (d) => onSecondaryTap(item, d.globalPosition),
      child: grid
          ? FileGridTile(item: item, selected: selected)
          : FileListTile(item: item, selected: selected),
    );
  }
}
