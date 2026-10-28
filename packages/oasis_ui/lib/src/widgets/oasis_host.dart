import 'package:flutter/widgets.dart';

import '../theme/oasis_theme.dart';
import '../update/update_service.dart';

class OasisHost extends InheritedWidget {
  const OasisHost({
    super.key,
    required this.appearance,
    required this.updates,
    required this.setLocale,
    this.locale,
    this.openUrl,
    required super.child,
  });

  final OasisAppearance appearance;
  final UpdateService updates;
  final ValueChanged<Locale?> setLocale;
  final Locale? locale;
  final ValueChanged<String>? openUrl;

  static OasisHost of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OasisHost>()!;

  static OasisHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OasisHost>();

  @override
  bool updateShouldNotify(OasisHost oldWidget) =>
      appearance != oldWidget.appearance ||
      updates != oldWidget.updates ||
      setLocale != oldWidget.setLocale ||
      locale != oldWidget.locale ||
      openUrl != oldWidget.openUrl;
}
