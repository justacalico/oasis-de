import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';

class OasisSection extends StatelessWidget {
  const OasisSection({
    super.key,
    this.title,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final style = OasisStyle.of(context);
    final p = style.palette;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, thickness: 0.5, color: p.divider));
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 6),
            child: Text(title!,
                style: Theme.of(context).textTheme.titleMedium),
          ),
        Material(
          color: p.cardBackground,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.cardRadius),
            side: BorderSide(color: p.divider, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ],
    );
  }
}

class OasisRow extends StatelessWidget {
  const OasisRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final text = Theme.of(context).textTheme;
    final content = Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[
            DefaultTextStyle(
              style: text.bodyMedium!,
              child: IconTheme(
                data: IconThemeData(color: p.textSecondary, size: 20),
                child: leading!,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: text.bodyMedium),
                if (subtitle != null)
                  Text(subtitle!, style: text.bodySmall),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            DefaultTextStyle(
              style: text.bodySmall!,
              child: trailing!,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}
