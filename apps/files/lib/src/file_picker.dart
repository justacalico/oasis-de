import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'file_item.dart';
import 'files_backend.dart';
import 'files_browser.dart';
import 'files_state.dart';

Future<String?> showOasisFilePicker(
  BuildContext context, {
  String? title,
  String? initialDir,
  Set<String>? extensions,
  String? confirmLabel,
  FilesState? state,
  FilesBackend? backend,
}) {
  final result = Completer<String?>();
  showOasisDialog(
    context,
    constraints: const BoxConstraints(maxWidth: 640),
    onClosed: () {
      if (!result.isCompleted) result.complete(null);
    },
    (dialogContext, close) {
      void finish(String? path) {
        if (!result.isCompleted) result.complete(path);
        close();
      }

      return SizedBox(
        width: 600,
        height: 420,
        child: OasisFilePicker(
          state: state,
          backend: backend,
          initialDir: initialDir,
          extensions: extensions,
          title:
              title ?? OasisLocalizations.of(dialogContext).filePickerTitle,
          confirmLabel: confirmLabel,
          onSelected: finish,
          onCancel: () => finish(null),
        ),
      );
    },
  );
  return result.future;
}

class OasisFilePicker extends StatefulWidget {
  const OasisFilePicker({
    super.key,
    this.state,
    this.backend,
    this.initialDir,
    this.extensions,
    this.title,
    this.confirmLabel,
    required this.onSelected,
    this.onCancel,
  });

  final FilesState? state;
  final FilesBackend? backend;
  final String? initialDir;
  final Set<String>? extensions;
  final String? title;
  final String? confirmLabel;
  final ValueChanged<String> onSelected;
  final VoidCallback? onCancel;

  @override
  State<OasisFilePicker> createState() => _OasisFilePickerState();
}

class _OasisFilePickerState extends State<OasisFilePicker> {
  late final FilesState _state =
      widget.state ?? FilesState(backend: widget.backend);

  @override
  void initState() {
    super.initState();
    _state.init(
      widget.initialDir ?? Platform.environment['HOME'] ?? '/',
    );
  }

  @override
  void dispose() {
    if (widget.state == null) _state.dispose();
    super.dispose();
  }

  void _activate(FileItem item) {
    if (item.isDir) {
      _state.cd(item.path);
    } else {
      widget.onSelected(item.path);
    }
  }

  void _confirm() {
    final sel = _state.singleSelection;
    if (sel == null) return;
    _activate(sel);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          final sel = _state.singleSelection;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.title != null) ...[
                Text(widget.title!, style: text.titleSmall),
                const SizedBox(height: 6),
              ],
              Expanded(
                child: FilesBrowser(
                  state: _state,
                  extensions: widget.extensions,
                  multiSelect: false,
                  onActivate: _activate,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sel == null || sel.isDir ? '' : sel.name,
                      style: text.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  OasisButton(
                    label: l10n.filesCancel,
                    variant: OasisButtonVariant.text,
                    dense: true,
                    onPressed: widget.onCancel,
                  ),
                  const SizedBox(width: 8),
                  OasisButton(
                    label: sel != null && sel.isDir
                        ? l10n.filesOpen
                        : widget.confirmLabel ?? l10n.filesChoose,
                    dense: true,
                    onPressed: sel == null ? null : _confirm,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
