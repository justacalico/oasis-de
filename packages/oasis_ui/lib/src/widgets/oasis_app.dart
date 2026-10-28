import 'package:flutter/widgets.dart';

class OasisApp {
  const OasisApp({
    required this.id,
    required this.name,
    required this.icon,
    required this.iconColors,
    required this.builder,
  });

  final String id;
  final String name;
  final IconData icon;
  final List<Color> iconColors;
  final WidgetBuilder builder;
}
