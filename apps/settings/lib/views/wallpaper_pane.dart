import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

class WallpaperPane extends StatefulWidget {
  const WallpaperPane({super.key, required this.wallpaper});

  final OasisWallpaperService wallpaper;

  @override
  State<WallpaperPane> createState() => _WallpaperPaneState();
}

class _WallpaperPaneState extends State<WallpaperPane> {
  final _pathController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final text = Theme.of(context).textTheme;
    final wallpaper = widget.wallpaper;

    final fits = [
      (BoxFit.cover, l10n.wallpaperFitCover),
      (BoxFit.contain, l10n.wallpaperFitContain),
      (BoxFit.fill, l10n.wallpaperFitFill),
    ];

    return AnimatedBuilder(
      animation: wallpaper,
      builder: (context, _) {
        final path = wallpaper.imagePath;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsWallpaper, style: text.titleLarge),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(OasisStyle.of(context).cardRadius),
              child: SizedBox(
                height: 180,
                width: double.infinity,
                child: OasisWallpaper(service: wallpaper),
              ),
            ),
            const SizedBox(height: 16),
            OasisSection(
              children: [
                OasisRow(
                  leading: const Icon(Icons.landscape),
                  title: l10n.wallpaperDunes,
                  trailing: wallpaper.hasCustomImage
                      ? const SizedBox.shrink()
                      : Icon(Icons.check, size: 16, color: p.accent),
                  onTap: wallpaper.useDefault,
                ),
                if (path != null)
                  OasisRow(
                    leading: const Icon(Icons.image),
                    title: path.split('/').last,
                    subtitle: path,
                    trailing:
                        Icon(Icons.check, size: 16, color: p.accent),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            OasisSection(
              title: l10n.wallpaperCustom,
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: OasisSearchField(
                          hint: l10n.wallpaperPathHint,
                          icon: Icons.image_outlined,
                          controller: _pathController,
                          onSubmitted: _apply,
                        ),
                      ),
                      const SizedBox(width: 10),
                      OasisButton(
                        label: l10n.wallpaperApply,
                        variant: OasisButtonVariant.primary,
                        onPressed: () => _apply(_pathController.text),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (wallpaper.hasCustomImage) ...[
              const SizedBox(height: 16),
              OasisSection(
                title: l10n.wallpaperFit,
                children: [
                  for (final f in fits)
                    OasisRow(
                      title: f.$2,
                      trailing: wallpaper.fit == f.$1
                          ? Icon(Icons.check, size: 16, color: p.accent)
                          : const SizedBox.shrink(),
                      onTap: () => wallpaper.fit = f.$1,
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  void _apply(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    widget.wallpaper.imagePath = trimmed;
  }
}
