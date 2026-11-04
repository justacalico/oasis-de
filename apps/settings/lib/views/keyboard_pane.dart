import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../state/settings_state.dart';

class KeyboardPane extends StatefulWidget {
  const KeyboardPane({super.key, required this.state});

  final SettingsState state;

  @override
  State<KeyboardPane> createState() => _KeyboardPaneState();
}

class _KeyboardPaneState extends State<KeyboardPane> {
  late final OasisKeybindsService _keybinds =
      widget.state.keybinds ?? OasisKeybindsService();
  String? _recording;

  String _actionLabel(OasisLocalizations l10n, String action) =>
      switch (action) {
        OasisKeybindsService.actionLauncher => l10n.keybindLauncher,
        OasisKeybindsService.actionAppGrid => l10n.appGrid,
        OasisKeybindsService.actionCycleWindows => l10n.keybindCycleWindows,
        OasisKeybindsService.actionCycleWindowsBack =>
          l10n.keybindCycleWindowsBack,
        OasisKeybindsService.actionDismiss => l10n.keybindDismiss,
        OasisKeybindsService.actionShowDesktop => l10n.keybindShowDesktop,
        OasisKeybindsService.actionZoom => l10n.keybindZoom,
        OasisKeybindsService.actionQuit => l10n.keybindQuit,
        OasisKeybindsService.actionScreenshot => l10n.keybindScreenshot,
        _ => action,
      };

  KeyEventResult _capture(String action, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _recording = null);
      return KeyEventResult.handled;
    }
    final combo = OasisKeyCombo.fromKeyDown(event);
    if (combo == null) return KeyEventResult.handled;
    _keybinds.rebind(action, combo);
    setState(() => _recording = null);
    return KeyEventResult.handled;
  }

  void _addCustom() {
    showOasisDialog(
      context,
      (context, close) => Material(
        type: MaterialType.transparency,
        child: _CustomKeybindDialog(
          onAdd: (command, combo) {
            _keybinds.addCustom(command: command, combo: combo);
            close();
          },
          onCancel: close,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: _keybinds,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsKeyboard, style: text.titleLarge),
            const SizedBox(height: 16),
            OasisSection(
              title: l10n.keybindShortcuts,
              children: [
                for (final action in OasisKeybindsService.builtinActions)
                  OasisRow(
                    title: _actionLabel(l10n, action),
                    trailing: _CaptureChip(
                      label:
                          _keybinds.comboFor(action)?.label ??
                          l10n.keybindNotSet,
                      recording: _recording == action,
                      hint: l10n.keybindRecording,
                      onKey: (e) => _capture(action, e),
                      onTap: () => setState(() => _recording = action),
                    ),
                    onTap: () => setState(() => _recording = action),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            OasisSection(
              title: l10n.keybindCustom,
              children: [
                for (final c in _keybinds.custom)
                  OasisRow(
                    title: c.command,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CaptureChip(
                          label: c.combo?.label ?? l10n.keybindNotSet,
                          recording: _recording == c.id,
                          hint: l10n.keybindRecording,
                          onKey: (e) => _capture(c.id, e),
                          onTap: () => setState(() => _recording = c.id),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _keybinds.removeCustom(c.id),
                          child: Tooltip(
                            message: l10n.keybindRemove,
                            child: const Icon(Icons.close, size: 16),
                          ),
                        ),
                      ],
                    ),
                    onTap: () => setState(() => _recording = c.id),
                  ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OasisButton(
                      label: l10n.keybindAdd,
                      dense: true,
                      onPressed: _addCustom,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OasisButton(
              label: l10n.keybindReset,
              onPressed: _keybinds.resetDefaults,
            ),
          ],
        );
      },
    );
  }
}

class _CaptureChip extends StatefulWidget {
  const _CaptureChip({
    required this.label,
    required this.recording,
    required this.hint,
    required this.onKey,
    required this.onTap,
  });

  final String label;
  final bool recording;
  final String hint;
  final KeyEventResult Function(KeyEvent) onKey;
  final VoidCallback onTap;

  @override
  State<_CaptureChip> createState() => _CaptureChipState();
}

class _CaptureChipState extends State<_CaptureChip> {
  final _node = FocusNode();

  @override
  void didUpdateWidget(_CaptureChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recording && !oldWidget.recording) _node.requestFocus();
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return Focus(
      focusNode: _node,
      onKeyEvent: (_, event) =>
          widget.recording ? widget.onKey(event) : KeyEventResult.ignored,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: widget.recording ? p.accentSoft : const Color(0x00000000),
            border: Border.all(color: widget.recording ? p.accent : p.divider),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.recording ? widget.hint : widget.label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: widget.recording ? p.accent : p.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomKeybindDialog extends StatefulWidget {
  const _CustomKeybindDialog({required this.onAdd, required this.onCancel});

  final void Function(String command, OasisKeyCombo combo) onAdd;
  final VoidCallback onCancel;

  @override
  State<_CustomKeybindDialog> createState() => _CustomKeybindDialogState();
}

class _CustomKeybindDialogState extends State<_CustomKeybindDialog> {
  final _command = TextEditingController();
  OasisKeyCombo? _combo;
  var _recording = false;

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  KeyEventResult _capture(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _recording = false);
      return KeyEventResult.handled;
    }
    final combo = OasisKeyCombo.fromKeyDown(event);
    if (combo == null) return KeyEventResult.handled;
    setState(() {
      _combo = combo;
      _recording = false;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final canAdd = _combo != null && _command.text.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.keybindAdd, style: text.titleMedium),
        const SizedBox(height: 12),
        OasisTextField(
          controller: _command,
          autofocus: true,
          hintText: l10n.keybindCommandHint,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: _CaptureChip(
            label: _combo?.label ?? l10n.keybindNotSet,
            recording: _recording,
            hint: l10n.keybindRecording,
            onKey: _capture,
            onTap: () => setState(() => _recording = true),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            OasisButton(
              label: l10n.dialogCancel,
              variant: OasisButtonVariant.text,
              onPressed: widget.onCancel,
            ),
            OasisButton(
              label: l10n.keybindAdd,
              variant: OasisButtonVariant.primary,
              onPressed: canAdd
                  ? () => widget.onAdd(_command.text.trim(), _combo!)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
