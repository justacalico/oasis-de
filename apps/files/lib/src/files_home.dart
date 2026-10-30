import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'file_item.dart';
import 'files_state.dart';

class FilesHome extends StatefulWidget {
  const FilesHome({
    super.key,
    this.state,
    this.startDir,
  });

  final FilesState? state;
  final String? startDir;

  @override
  State<FilesHome> createState() => _FilesHomeState();
}

class _FilesHomeState extends State<FilesHome> {
  late final FilesState _state;
  final _pathCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _state = widget.state ?? FilesState();
    _state.addListener(_syncPath);
    _state.init(
      widget.startDir ?? Platform.environment['HOME'] ?? '/',
    );
    _pathCtrl.text = _state.dir;
  }

  void _syncPath() {
    if (_state.dir != _pathCtrl.text) {
      _pathCtrl.text = _state.dir;
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _state.removeListener(_syncPath);
    if (widget.state == null) _state.dispose();
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

  String _bookmarkLabel(OasisLocalizations l10n, FileBookmark b) {
    return switch (b.kind) {
      BookmarkKind.home => l10n.filesBookmarkHome,
      BookmarkKind.documents => l10n.filesBookmarkDocuments,
      BookmarkKind.downloads => l10n.filesBookmarkDownloads,
      BookmarkKind.pictures => l10n.filesBookmarkPictures,
      BookmarkKind.music => l10n.filesBookmarkMusic,
      BookmarkKind.videos => l10n.filesBookmarkVideos,
      BookmarkKind.trash => l10n.filesBookmarkTrash,
      BookmarkKind.mount => b.label,
      BookmarkKind.root => l10n.filesBookmarkRoot,
    };
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var v = bytes.toDouble();
    var i = -1;
    do {
      v /= 1024;
      i++;
    } while (v >= 1024 && i < units.length - 1);
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1)} ${units[i]}';
  }

  String _fmtDate(BuildContext context, DateTime? dt) {
    if (dt == null) return '';
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMd(locale).add_Hm().format(dt);
  }

  void _nameDialog(
    OasisLocalizations l10n, {
    required String title,
    required String confirm,
    String initial = '',
    required ValueChanged<String> onDone,
  }) {
    final ctrl = TextEditingController(text: initial);
    showOasisDialog(
      context,
      (dialogContext, close) => Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(dialogContext).textTheme.titleSmall),
          const SizedBox(height: 10),
          OasisTextField(
            controller: ctrl,
            autofocus: true,
            filled: true,
            hintText: l10n.filesName,
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) {
                onDone(v.trim());
                close();
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OasisButton(
                label: l10n.filesCancel,
                variant: OasisButtonVariant.text,
                dense: true,
                onPressed: close,
              ),
              const SizedBox(width: 8),
              OasisButton(
                label: confirm,
                dense: true,
                onPressed: () {
                  if (ctrl.text.trim().isNotEmpty) {
                    onDone(ctrl.text.trim());
                    close();
                  }
                },
              ),
            ],
          ),
          ],
        ),
      ),
    );
  }

  void _contextMenu(
    BuildContext context,
    OasisLocalizations l10n,
    FileItem item,
    Offset pos,
  ) {
    final s = _state;
    if (!s.selection.contains(item.path)) s.select(item);
    showOasisMenu(context, pos, [
      OasisMenuItem(
        label: l10n.filesOpen,
        action: (_) => s.open(item),
      ),
      OasisMenuItem(
        label: l10n.filesRename,
        action: (_) => _nameDialog(
          l10n,
          title: l10n.filesRename,
          confirm: l10n.filesRename,
          initial: item.name,
          onDone: s.renameSelected,
        ),
      ),
      OasisMenuItem(
        label: l10n.filesCopy,
        action: (_) => s.copy(),
        separatorAfter: true,
      ),
      OasisMenuItem(
        label: l10n.filesCut,
        action: (_) => s.copy(cut: true),
      ),
      OasisMenuItem(
        label: l10n.filesDelete,
        action: (_) => s.trashSelection(),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final text = Theme.of(context).textTheme;

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          final s = _state;
          final items = s.entries;
          final sel = s.selectedItems;
          return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Row(
                children: [
                  _ToolBtn(
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
                  _ToolBtn(
                    icon: s.showHidden
                        ? Icons.visibility
                        : Icons.visibility_off,
                    tooltip: l10n.filesShowHidden,
                    onTap: s.toggleHidden,
                  ),
                  _ToolBtn(
                    icon: s.gridView ? Icons.list : Icons.grid_view,
                    tooltip:
                        s.gridView ? l10n.filesListView : l10n.filesGridView,
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
                          _BookmarkTile(
                            label: _bookmarkLabel(l10n, b),
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
                  Expanded(child: _body(l10n, p, items)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: p.cardBackground.withValues(alpha: 0.5),
                border: Border(
                  top: BorderSide(
                    color: p.textTertiary.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (s.query.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          s.setQuery('');
                        },
                        child: Text(
                          l10n.filesClearSearch,
                          style: text.bodySmall?.copyWith(color: p.accent),
                        ),
                      ),
                    ),
                  Text(
                    l10n.filesItems(items.length),
                    style: text.bodySmall,
                  ),
                  const Spacer(),
                  if (sel.isNotEmpty)
                    Flexible(
                      child: Text(
                        sel.length == 1
                            ? '${sel.first.name} · '
                                '${sel.first.isDir ? l10n.filesFolder : _fmtSize(sel.first.size)} · '
                                '${_fmtDate(context, sel.first.modified)}'
                            : l10n.filesSelected(sel.length),
                        style: text.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(width: 10),
                  _ActionBtn(
                    label: l10n.filesNewFolder,
                    onTap: () => _nameDialog(
                      l10n,
                      title: l10n.filesNewFolder,
                      confirm: l10n.filesCreate,
                      onDone: s.newFolder,
                    ),
                  ),
                  if (s.hasClipboard)
                    _ActionBtn(
                      label: l10n.filesPaste,
                      onTap: s.paste,
                    ),
                  if (sel.isNotEmpty) ...[
                    _ActionBtn(
                      label: l10n.filesCopy,
                      onTap: () => s.copy(),
                    ),
                    _ActionBtn(
                      label: l10n.filesDelete,
                      onTap: s.trashSelection,
                    ),
                  ],
                ],
              ),
            ),
          ],
          );
        },
      ),
    );
  }

  Widget _body(
    OasisLocalizations l10n,
    dynamic p,
    List<FileItem> items,
  ) {
    final s = _state;
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
      return GridView.extent(
        maxCrossAxisExtent: 110,
        childAspectRatio: 0.85,
        padding: const EdgeInsets.all(8),
        children: [for (final i in items) _tile(l10n, i, grid: true)],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      itemCount: items.length,
      itemExtent: 34,
      itemBuilder: (context, idx) => _tile(l10n, items[idx], grid: false),
    );
  }

  DateTime? _lastTap;
  String? _lastTapPath;

  void _tap(FileItem item) {
    final now = DateTime.now();
    final last = _lastTap;
    if (_lastTapPath == item.path &&
        last != null &&
        now.difference(last).inMilliseconds < 400) {
      _lastTapPath = null;
      _state.open(item);
      return;
    }
    _lastTapPath = item.path;
    _lastTap = now;
    _state.select(
      item,
      additive: HardwareKeyboard.instance.isControlPressed,
    );
  }

  Widget _tile(OasisLocalizations l10n, FileItem item, {required bool grid}) {
    final s = _state;
    final selected = s.selection.contains(item.path);
    return GestureDetector(
      onTapDown: (_) => _tap(item),
      onSecondaryTapUp: (d) =>
          _contextMenu(context, l10n, item, d.globalPosition),
      child: grid
          ? _GridTile(item: item, selected: selected)
          : _ListTile(
              item: item,
              selected: selected,
              fmtSize: _fmtSize,
              dateText: _fmtDate(context, item.modified),
            ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return OasisTooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 17, color: p.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: OasisButton(label: label, dense: true, onPressed: onTap),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: active
                ? p.accent.withValues(alpha: 0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

IconData fileIcon(FileItem item) {
  if (item.isDir) return Icons.folder;
  if (item.isImage) return Icons.image;
  if (item.isAudio) return Icons.music_note;
  if (item.isVideo) return Icons.movie;
  if (item.isArchive) return Icons.folder_zip;
  if (item.isPdf) return Icons.picture_as_pdf;
  return Icons.description;
}

class _ListTile extends StatelessWidget {
  const _ListTile({
    required this.item,
    required this.selected,
    required this.fmtSize,
    required this.dateText,
  });

  final FileItem item;
  final bool selected;
  final String Function(int) fmtSize;
  final String dateText;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: selected
            ? p.accent.withValues(alpha: 0.25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(fileIcon(item), size: 16, color: p.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.name,
              style: text.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              item.isDir ? '' : fmtSize(item.size),
              style: text.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              dateText,
              style: text.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.item, required this.selected});

  final FileItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: selected
            ? p.accent.withValues(alpha: 0.25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (item.isImage)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image(
                  image: item.thumb ?? FileImage(File(item.path)),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      Icon(fileIcon(item), size: 34, color: p.accent),
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Icon(fileIcon(item), size: 34, color: p.accent),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            item.name,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
