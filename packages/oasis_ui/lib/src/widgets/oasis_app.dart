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
    this.keywords = const [],
    this.genericName,
  });

  final String id;
  final String name;
  final IconData icon;
  final List<Color> iconColors;
  final WidgetBuilder builder;
  final List<String>? exec;
  final String? iconPath;
  final List<String> keywords;
  final String? genericName;

  bool get isExternal => exec != null;
}
