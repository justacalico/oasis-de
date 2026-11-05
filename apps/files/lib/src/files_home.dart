import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'file_item.dart';
import 'files_backend.dart';
import 'files_browser.dart';
import 'files_state.dart';
import 'files_tiles.dart';

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

  @override
  void initState() {
    super.initState();
    _state = widget.state ?? FilesState();
    _state.init(
      widget.startDir ?? Platform.environment['HOME'] ?? '/',
    );
  }

  @override
  void dispose() {
    if (widget.state == null) _state.dispose();
    super.dispose();
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
      onClosed: ctrl.dispose,
      (dialogContext, close) => Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(dialogContext).textTheme.titleSmall,
            ),
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

  Future<FileConflictResolution?> _conflictDialog(
    OasisLocalizations l10n,
    String name,
  ) {
    final completer = Completer<FileConflictResolution?>();
    showOasisDialog(
      context,
      onClosed: () {
        if (!completer.isCompleted) completer.complete(null);
      },
      (dialogContext, close) {
        void choose(FileConflictResolution? choice) {
          if (!completer.isCompleted) completer.complete(choice);
          close();
        }

        return Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.filesConflictTitle,
                style: Theme.of(dialogContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.filesConflictMessage(name),
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OasisButton(
                    label: l10n.filesCancel,
                    variant: OasisButtonVariant.text,
                    dense: true,
                    onPressed: () => choose(null),
                  ),
                  OasisButton(
                    label: l10n.filesKeepBoth,
                    dense: true,
                    onPressed: () =>
                        choose(FileConflictResolution.keepBoth),
                  ),
                  OasisButton(
                    label: l10n.filesReplace,
                    variant: OasisButtonVariant.primary,
                    dense: true,
                    onPressed: () =>
                        choose(FileConflictResolution.replace),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    return completer.future;
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
          onDone: (name) => s.renameSelected(
            name,
            onConflict: (n) => _conflictDialog(l10n, n),
          ),
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
              Expanded(
                child: FilesBrowser(
                  state: s,
                  onActivate: s.open,
                  onSecondaryTap: (item, pos) =>
                      _contextMenu(context, l10n, item, pos),
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
                          onTap: () => s.setQuery(''),
                          child: Text(
                            l10n.filesClearSearch,
                            style: text.bodySmall
                                ?.copyWith(color: p.accent),
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
                                  '${sel.first.isDir ? l10n.filesFolder : formatFileSize(sel.first.size)} · '
                                  '${formatFileDate(context, sel.first.modified)}'
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
