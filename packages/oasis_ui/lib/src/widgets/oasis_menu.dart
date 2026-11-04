import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';
import 'oasis_glass.dart';
import 'oasis_tooltip.dart';

class OasisMenuItem {
  const OasisMenuItem({
    required this.label,
    this.enabled = true,
    this.separatorAfter = false,
    this.checked = false,
    this.trailing,
    this.action,
    this.children,
    this.onOpen,
    this.onClose,
    this.onHover,
  });

  final String label;
  final bool enabled;
  final bool separatorAfter;
  final bool checked;
  final Widget? trailing;
  final void Function(BuildContext context)? action;

  /// Nested submenu contents, opened on hover instead of [action].
  final List<OasisMenuItem> Function()? children;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final VoidCallback? onHover;
}

class OasisPopupItem<T> {
  const OasisPopupItem({required this.value, required this.label});

  final T value;
  final String label;
}

/// Tracks submenu flyouts spawned from a menu so they share the root
/// menu's lifetime: hovering a sibling replaces the deepest level and
/// closing the root closes them all.
class OasisMenuCascade {
  OasisMenuCascade(this._overlay);

  final OverlayState _overlay;
  final List<OverlayEntry> _subs = [];
  final List<OasisMenuItem> _owners = [];

  Rect localize(Rect global) {
    final box = _overlay.context.findRenderObject()! as RenderBox;
    return box.globalToLocal(global.topLeft) & global.size;
  }

  void open(
    int depth,
    Rect anchor,
    OasisMenuItem owner,
    List<OasisMenuItem> items,
    VoidCallback onSelect,
  ) {
    closeFrom(depth);
    _subs.add(
      OverlayEntry(
        builder: (context) => CustomSingleChildLayout(
          delegate: _OasisSubmenuLayout(anchor),
          child: _OasisMenuGlass(
            child: OasisMenuList(
              items: items,
              depth: depth,
              cascade: this,
              onSelect: onSelect,
            ),
          ),
        ),
      ),
    );
    _owners.add(owner);
    _overlay.insert(_subs.last);
  }

  void closeFrom(int depth) {
    while (_subs.length >= depth) {
      _subs.removeLast().remove();
      _owners.removeLast().onClose?.call();
    }
  }

  void close() {
    while (_subs.isNotEmpty) {
      _subs.removeLast().remove();
      _owners.removeLast().onClose?.call();
    }
  }
}

class _OasisMenuGlass extends StatelessWidget {
  const _OasisMenuGlass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = OasisStyle.of(context);
    return OasisGlass(
      borderRadius: style.menuRadius,
      blur: 36,
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 210,
          maxWidth: 240,
          maxHeight: 400,
        ),
        child: IntrinsicWidth(child: SingleChildScrollView(child: child)),
      ),
    );
  }
}

/// Shared menu column used by [showOasisMenu], cascading submenus and
/// embedded dropdowns such as the shell menu bar.
class OasisMenuList extends StatelessWidget {
  const OasisMenuList({
    super.key,
    required this.items,
    required this.onSelect,
    this.cascade,
    this.depth = 0,
  });

  final List<OasisMenuItem> items;
  final VoidCallback onSelect;
  final OasisMenuCascade? cascade;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final style = OasisStyle.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items) ...[
          OasisMenuEntry(
            item: item,
            depth: depth,
            cascade: cascade,
            onSelect: onSelect,
          ),
          if (item.separatorAfter)
            Divider(
              height: 9,
              thickness: 0.5,
              indent: 12,
              endIndent: 12,
              color: style.palette.divider,
            ),
        ],
      ],
    );
  }
}

void showOasisMenu(
  BuildContext context,
  Offset position,
  List<OasisMenuItem> items,
) {
  final overlay = Overlay.of(context);
  final box = overlay.context.findRenderObject()! as RenderBox;
  final local = box.globalToLocal(position);
  final cascade = OasisMenuCascade(overlay);
  late final OverlayEntry entry;
  var closed = false;
  void close() {
    if (closed) return;
    closed = true;
    cascade.close();
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: close,
            onSecondaryTapUp: (_) => close(),
          ),
        ),
        CustomSingleChildLayout(
          delegate: _OasisMenuLayout(local),
          child: _OasisMenuGlass(
            child: OasisMenuList(
              items: items,
              cascade: cascade,
              onSelect: close,
            ),
          ),
        ),
      ],
    ),
  );
  overlay.insert(entry);
}

class _OasisMenuLayout extends SingleChildLayoutDelegate {
  const _OasisMenuLayout(this.anchor);

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const margin = 8.0;
    final maxX = (size.width - childSize.width - margin).clamp(
      margin,
      double.infinity,
    );
    var dy = anchor.dy;
    if (dy + childSize.height > size.height - margin) {
      dy = anchor.dy - childSize.height;
    }
    final maxY = (size.height - childSize.height - margin).clamp(
      margin,
      double.infinity,
    );
    dy = dy.clamp(margin, maxY);
    return Offset(anchor.dx.clamp(margin, maxX), dy);
  }

  @override
  bool shouldRelayout(_OasisMenuLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}

/// Positions a submenu against the entry that spawned it, hugging its
/// right edge and flipping left or upward when the flyout would leave
/// the screen.
class _OasisSubmenuLayout extends SingleChildLayoutDelegate {
  const _OasisSubmenuLayout(this.anchor);

  final Rect anchor;

  static const _overlap = 4.0;
  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var dx = anchor.right - _overlap;
    if (dx + childSize.width > size.width - _margin) {
      dx = anchor.left - childSize.width + _overlap;
      if (dx < _margin) dx = size.width - childSize.width - _margin;
    }
    var dy = anchor.top - 5;
    if (dy + childSize.height > size.height - _margin) {
      dy = anchor.bottom - childSize.height + 5;
      if (dy < _margin) dy = _margin;
    }
    return Offset(
      dx.clamp(_margin, size.width - _margin),
      dy.clamp(_margin, size.height - _margin),
    );
  }

  @override
  bool shouldRelayout(_OasisSubmenuLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}

class OasisPopupMenuButton<T> extends StatelessWidget {
  const OasisPopupMenuButton({
    super.key,
    required this.icon,
    this.tooltip,
    required this.items,
    required this.onSelected,
    this.selectedValue,
  });

  final Widget icon;
  final String? tooltip;
  final List<OasisPopupItem<T>> items;
  final ValueChanged<T> onSelected;
  final T? selectedValue;

  @override
  Widget build(BuildContext context) {
    return OasisTooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          final box = context.findRenderObject()! as RenderBox;
          final pos = box.localToGlobal(Offset(0, box.size.height + 4));
          showOasisMenu(context, pos, [
            for (final item in items)
              OasisMenuItem(
                label: item.label,
                checked: item.value == selectedValue,
                action: (_) => onSelected(item.value),
              ),
          ]);
        },
        child: Padding(padding: const EdgeInsets.all(8), child: icon),
      ),
    );
  }
}

class OasisMenuEntry extends StatefulWidget {
  const OasisMenuEntry({
    super.key,
    required this.item,
    required this.onSelect,
    this.cascade,
    this.depth = 0,
  });

  final OasisMenuItem item;
  final VoidCallback onSelect;
  final OasisMenuCascade? cascade;
  final int depth;

  @override
  State<OasisMenuEntry> createState() => _OasisMenuEntryState();
}

class _OasisMenuEntryState extends State<OasisMenuEntry> {
  var _hovered = false;

  bool get _hasSub => widget.item.children != null;

  Rect? _anchor() {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  void _openSubmenu() {
    final cascade = widget.cascade;
    final anchor = _anchor();
    final children = widget.item.children;
    if (cascade == null || anchor == null || children == null) return;
    widget.item.onOpen?.call();
    cascade.open(
      widget.depth + 1,
      cascade.localize(anchor),
      widget.item,
      children(),
      widget.onSelect,
    );
  }

  void _enter() {
    final item = widget.item;
    if (item.enabled) setState(() => _hovered = true);
    item.onHover?.call();
    final cascade = widget.cascade;
    if (cascade == null) return;
    if (_hasSub && item.enabled) {
      _openSubmenu();
    } else {
      cascade.closeFrom(widget.depth + 1);
    }
  }

  void _exit() {
    if (widget.item.enabled) setState(() => _hovered = false);
  }

  void _tap() {
    final item = widget.item;
    if (!item.enabled) return;
    if (_hasSub) {
      _openSubmenu();
      return;
    }
    widget.onSelect();
    item.action?.call(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final enabled = widget.item.enabled;
    final color = !enabled
        ? p.textTertiary
        : _hovered
        ? const Color(0xFFFFFFFF)
        : p.textPrimary;
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: _hovered ? p.accent : const Color(0x00000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: widget.item.checked
                      ? Icon(Icons.check, size: 14, color: color)
                      : null,
                ),
                Expanded(
                  child: Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: color),
                  ),
                ),
                if (widget.item.trailing != null) ...[
                  const SizedBox(width: 8),
                  IconTheme.merge(
                    data: IconThemeData(color: color, size: 14),
                    child: widget.item.trailing!,
                  ),
                ],
                if (_hasSub) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, size: 14, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
