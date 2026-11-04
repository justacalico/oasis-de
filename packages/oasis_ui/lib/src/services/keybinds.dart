import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'oasis_store.dart';

final _modifierKeys = {
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.superKey,
  LogicalKeyboardKey.hyper,
  LogicalKeyboardKey.fn,
};

// GTK reports the Super (command) key as LogicalKeyboardKey.superKey rather
// than metaLeft/metaRight, so HardwareKeyboard.isMetaPressed and Flutter's
// meta synonyms both miss it on Linux. Every meta check in the shell has to
// go through this set instead.
final metaModifierKeys = LogicalKeyboardKey.expandSynonyms({
  LogicalKeyboardKey.meta,
})..add(LogicalKeyboardKey.superKey);

/// Whether a meta modifier is held, counting the Super key that Linux
/// reports as [LogicalKeyboardKey.superKey].
bool isMetaOrSuperPressed(HardwareKeyboard hw) =>
    hw.logicalKeysPressed.any(metaModifierKeys.contains);

final _keyLabels = {
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.arrowUp: 'Up',
  LogicalKeyboardKey.arrowDown: 'Down',
  LogicalKeyboardKey.arrowLeft: 'Left',
  LogicalKeyboardKey.arrowRight: 'Right',
  LogicalKeyboardKey.backspace: 'Backspace',
  LogicalKeyboardKey.delete: 'Delete',
  LogicalKeyboardKey.printScreen: 'Print',
};

/// A non-modifier key plus the modifiers held down with it.
class OasisKeyCombo {
  const OasisKeyCombo({
    required this.key,
    this.meta = false,
    this.control = false,
    this.alt = false,
    this.shift = false,
  });

  final LogicalKeyboardKey key;
  final bool meta;
  final bool control;
  final bool alt;
  final bool shift;

  /// Builds a combo from a key-down event, reading the modifiers that are
  /// currently held. Returns null when the event itself is a modifier press.
  static OasisKeyCombo? fromKeyDown(KeyDownEvent event) {
    if (_modifierKeys.contains(event.logicalKey)) return null;
    final hw = HardwareKeyboard.instance;
    return OasisKeyCombo(
      key: event.logicalKey,
      control: hw.isControlPressed,
      alt: hw.isAltPressed,
      shift: hw.isShiftPressed,
      meta: isMetaOrSuperPressed(hw),
    );
  }

  SingleActivator get activator => _OasisActivator(
    key,
    meta: meta,
    control: control,
    alt: alt,
    shift: shift,
  );

  String get label {
    final keyLabel =
        _keyLabels[key] ??
        (key.keyLabel.length == 1 ? key.keyLabel : key.debugName ?? '?');
    return [
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) 'Super',
      keyLabel,
    ].join('+');
  }

  String encode() =>
      '${key.keyId}:${meta ? 'm' : ''}${control ? 'c' : ''}'
      '${alt ? 'a' : ''}${shift ? 's' : ''}';

  static OasisKeyCombo? decode(Object? raw) {
    if (raw is! String) return null;
    final sep = raw.indexOf(':');
    if (sep <= 0) return null;
    final keyId = int.tryParse(raw.substring(0, sep));
    final key = keyId == null ? null : LogicalKeyboardKey.findKeyByKeyId(keyId);
    if (key == null || _modifierKeys.contains(key)) return null;
    final flags = raw.substring(sep + 1);
    return OasisKeyCombo(
      key: key,
      meta: flags.contains('m'),
      control: flags.contains('c'),
      alt: flags.contains('a'),
      shift: flags.contains('s'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OasisKeyCombo &&
      other.key == key &&
      other.meta == meta &&
      other.control == control &&
      other.alt == alt &&
      other.shift == shift;

  @override
  int get hashCode => Object.hash(key, meta, control, alt, shift);
}

/// A [SingleActivator] that treats the Linux Super key as meta. Flutter's own
/// meta synonyms only cover metaLeft/metaRight, so a plain [SingleActivator]
/// never fires for Super-based shortcuts under GTK.
class _OasisActivator extends SingleActivator {
  const _OasisActivator(
    super.trigger, {
    super.control,
    super.shift,
    super.alt,
    super.meta,
  });

  static final _controlKeys = LogicalKeyboardKey.expandSynonyms({
    LogicalKeyboardKey.control,
  });
  static final _shiftKeys = LogicalKeyboardKey.expandSynonyms({
    LogicalKeyboardKey.shift,
  });
  static final _altKeys = LogicalKeyboardKey.expandSynonyms({
    LogicalKeyboardKey.alt,
  });

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is! KeyDownEvent &&
        !(includeRepeats && event is KeyRepeatEvent)) {
      return false;
    }
    final pressed = state.logicalKeysPressed;
    return event.logicalKey == trigger &&
        control == pressed.any(_controlKeys.contains) &&
        shift == pressed.any(_shiftKeys.contains) &&
        alt == pressed.any(_altKeys.contains) &&
        meta == pressed.any(metaModifierKeys.contains);
  }
}

/// A user-defined binding that runs a shell command.
class OasisCustomKeybind {
  const OasisCustomKeybind({
    required this.id,
    required this.command,
    this.combo,
  });

  final String id;
  final String command;
  final OasisKeyCombo? combo;

  OasisCustomKeybind copyWith({OasisKeyCombo? Function()? combo}) =>
      OasisCustomKeybind(
        id: id,
        command: command,
        combo: combo == null ? this.combo : combo(),
      );
}

/// Registry of every keyboard shortcut in the desktop. Bindings for built-in
/// shell actions and user-defined command shortcuts are kept here and
/// persisted through [OasisStore].
class OasisKeybindsService extends ChangeNotifier {
  OasisKeybindsService({OasisStore? store}) : _store = store {
    _restore();
  }

  static const storeKey = 'shell.keybinds';

  static const actionLauncher = 'shell.launcher';
  static const actionAppGrid = 'shell.launchpad';
  static const actionCycleWindows = 'shell.cycleWindows';
  static const actionCycleWindowsBack = 'shell.cycleWindowsBack';
  static const actionDismiss = 'shell.dismiss';
  static const actionShowDesktop = 'shell.showDesktop';
  static const actionZoom = 'shell.zoom';
  static const actionQuit = 'shell.quit';
  static const actionScreenshot = 'shell.screenshot';

  static const builtinActions = [
    actionLauncher,
    actionAppGrid,
    actionCycleWindows,
    actionCycleWindowsBack,
    actionDismiss,
    actionShowDesktop,
    actionZoom,
    actionQuit,
    actionScreenshot,
  ];

  static const defaults = <String, OasisKeyCombo>{
    actionLauncher: OasisKeyCombo(key: LogicalKeyboardKey.space, meta: true),
    actionAppGrid: OasisKeyCombo(
      key: LogicalKeyboardKey.space,
      control: true,
    ),
    actionCycleWindows: OasisKeyCombo(key: LogicalKeyboardKey.tab, alt: true),
    actionCycleWindowsBack: OasisKeyCombo(
      key: LogicalKeyboardKey.tab,
      alt: true,
      shift: true,
    ),
    actionDismiss: OasisKeyCombo(key: LogicalKeyboardKey.escape),
    actionShowDesktop: OasisKeyCombo(key: LogicalKeyboardKey.keyD, meta: true),
    actionZoom: OasisKeyCombo(key: LogicalKeyboardKey.arrowUp, meta: true),
    actionQuit: OasisKeyCombo(key: LogicalKeyboardKey.keyQ, meta: true),
    actionScreenshot: OasisKeyCombo(key: LogicalKeyboardKey.printScreen),
  };

  final OasisStore? _store;
  final Map<String, OasisKeyCombo> _bindings = {...defaults};
  final List<OasisCustomKeybind> _custom = [];
  var _customSeq = 0;

  List<OasisCustomKeybind> get custom => List.unmodifiable(_custom);

  OasisKeyCombo? comboFor(String action) =>
      _bindings[action] ?? customById(action)?.combo;

  OasisCustomKeybind? customById(String id) {
    for (final c in _custom) {
      if (c.id == id) return c;
    }
    return null;
  }

  String? actionForCombo(OasisKeyCombo combo) {
    for (final e in _bindings.entries) {
      if (e.value == combo) return e.key;
    }
    for (final c in _custom) {
      if (c.combo == combo) return c.id;
    }
    return null;
  }

  /// Every live binding keyed by its activator, ready for shortcut dispatch.
  Map<SingleActivator, String> get activators => {
    for (final e in _bindings.entries) e.value.activator: e.key,
    for (final c in _custom)
      if (c.combo != null) c.combo!.activator: c.id,
  };

  /// Assigns [combo] to [action], which is either a built-in action id or a
  /// custom keybind id. Any existing binding that used the combo is cleared.
  void rebind(String action, OasisKeyCombo combo) {
    final i = _custom.indexWhere((c) => c.id == action);
    if (i < 0 && !defaults.containsKey(action)) return;
    _steal(combo);
    if (i >= 0) {
      _custom[i] = _custom[i].copyWith(combo: () => combo);
    } else {
      _bindings[action] = combo;
    }
    _persist();
    notifyListeners();
  }

  String addCustom({required OasisKeyCombo combo, required String command}) {
    _steal(combo);
    final id = 'custom:${++_customSeq}';
    _custom.add(OasisCustomKeybind(id: id, command: command, combo: combo));
    _persist();
    notifyListeners();
    return id;
  }

  void removeCustom(String id) {
    _custom.removeWhere((c) => c.id == id);
    _persist();
    notifyListeners();
  }

  void resetDefaults() {
    _bindings
      ..clear()
      ..addAll(defaults);
    _persist();
    notifyListeners();
  }

  void _steal(OasisKeyCombo combo) {
    _bindings.removeWhere((_, c) => c == combo);
    for (var i = 0; i < _custom.length; i++) {
      if (_custom[i].combo == combo) {
        _custom[i] = _custom[i].copyWith(combo: () => null);
      }
    }
  }

  void _persist() {
    _store?.write(
      storeKey,
      jsonEncode({
        'bindings': {
          for (final e in _bindings.entries) e.key: e.value.encode(),
        },
        'custom': [
          for (final c in _custom)
            {'id': c.id, 'command': c.command, 'combo': c.combo?.encode()},
        ],
        'seq': _customSeq,
      }),
    );
  }

  void _restore() {
    final raw = _store?.read(storeKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final bindings = data['bindings'];
      if (bindings is Map) {
        for (final e in bindings.entries) {
          if (e.key is! String || !defaults.containsKey(e.key)) continue;
          final combo = OasisKeyCombo.decode(e.value);
          if (combo != null) _bindings[e.key as String] = combo;
        }
      }
      final custom = data['custom'];
      if (custom is List) {
        for (final entry in custom) {
          if (entry is! Map) continue;
          final id = entry['id'];
          final command = entry['command'];
          if (id is! String || command is! String) continue;
          _custom.add(
            OasisCustomKeybind(
              id: id,
              command: command,
              combo: OasisKeyCombo.decode(entry['combo']),
            ),
          );
        }
      }
      final seq = data['seq'];
      _customSeq = seq is int ? seq : _custom.length;
    } on FormatException {
      return;
    }
  }
}
