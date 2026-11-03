import 'dart:async';

import '../services/notifications.dart';
import 'shell_constants.dart';

class ShellNotifications {
  ShellNotifications({
    required void Function() onChanged,
    required bool Function() isFocusOn,
    required void Function(int id, String action) onAction,
    required void Function(int id, int reason) onClosed,
  })  : _onChanged = onChanged,
        _isFocusOn = isFocusOn,
        _onAction = onAction,
        _onClosed = onClosed;

  final void Function() _onChanged;
  final bool Function() _isFocusOn;
  final void Function(int id, String action) _onAction;
  final void Function(int id, int reason) _onClosed;

  final List<OasisNotification> items = [];
  OasisNotification? banner;
  Timer? _bannerTimer;
  var _localId = 0;

  int nextLocalId() => --_localId;

  void push(OasisNotification n) {
    if (!n.transient) {
      items.removeWhere((o) => o.id == n.id);
      items.insert(0, n);
      if (items.length > kMaxNotifications) items.length = kMaxNotifications;
    }
    if (!_isFocusOn()) {
      banner = n;
      _scheduleBannerDismiss();
    }
    _onChanged();
  }

  Duration? get _bannerTimeout {
    final n = banner;
    if (n == null) return null;
    if (n.expireTimeout == 0 || n.urgency >= 2) return null;
    if (n.expireTimeout > 0) {
      return Duration(milliseconds: n.expireTimeout);
    }
    return kBannerTimeout;
  }

  void _scheduleBannerDismiss() {
    _bannerTimer?.cancel();
    final timeout = _bannerTimeout;
    if (timeout == null) return;
    _bannerTimer = Timer(timeout, () {
      banner = null;
      _onChanged();
    });
  }

  void pauseDismiss() => _bannerTimer?.cancel();

  void resumeDismiss() => _scheduleBannerDismiss();

  void dismissBanner() {
    banner = null;
    _bannerTimer?.cancel();
    _onChanged();
  }

  void dismiss(int id, {int reason = 2}) {
    if (banner?.id == id) banner = null;
    items.removeWhere((n) => n.id == id);
    _onClosed(id, reason);
    _onChanged();
  }

  void invokeAction(OasisNotification n, String action) {
    _onAction(n.id, action);
    dismiss(n.id);
  }

  void clear() {
    for (final n in items) {
      _onClosed(n.id, 2);
    }
    items.clear();
    banner = null;
    _onChanged();
  }

  void dispose() => _bannerTimer?.cancel();
}
