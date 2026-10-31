import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

class SettingsDropdownRow extends StatelessWidget {
  const SettingsDropdownRow({
    super.key,
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labels,
  });

  final String title;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final Map<String, String>? labels;

  @override
  Widget build(BuildContext context) {
    return OasisRow(
      title: title,
      trailing: DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final item in items)
            DropdownMenuItem(
              value: item,
              child: Text(labels?[item] ?? item),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
