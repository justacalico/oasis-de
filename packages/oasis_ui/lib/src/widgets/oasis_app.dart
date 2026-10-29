import 'package:flutter/widgets.dart';

class OasisApp {
  const OasisApp({
    required this.id,
    required this.name,
    required this.icon,
    required this.iconColors,
    required this.builder,
    this.exec,
    this.iconPath,
  });

  final String id;
  final String name;
  final IconData icon;
  final List<Color> iconColors;
  final WidgetBuilder builder;
  final List<String>? exec;
  final String? iconPath;

  bool get isExternal => exec != null;
}
