import 'dart:io';

import 'package:flutter/material.dart';
import 'package:oasis_files/oasis_files.dart';
import 'package:oasis_ui/oasis_ui.dart';

class WallpaperPane extends StatefulWidget {
  const WallpaperPane({
    super.key,
    required this.wallpaper,
    this.filesBackend,
  });

  final OasisWallpaperService wallpaper;
  final FilesBackend? filesBackend;

  @override
  State<WallpaperPane> createState() => _WallpaperPaneState();
}

class _WallpaperPaneState extends State<WallpaperPane> {
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
                for (final preset in oasisWallpaperPresets)
                  OasisRow(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 40,
                        height: 28,
                        child: CustomPaint(
                          painter: OasisDunesPainter(
                            skyTop: preset.top ?? p.desktopGradientStart,
                            skyBottom:
                                preset.mid ?? p.desktopGradientMid,
                            duneFar:
                                preset.bottom ?? p.desktopGradientEnd,
                            duneNear: preset.bottom ??
                                p.desktopGradientEnd,
                            night: p.isDark,
                          ),
                        ),
                      ),
                    ),
                    title: _presetName(l10n, preset.id),
                    trailing: !wallpaper.hasCustomImage &&
                            wallpaper.preset == preset.id
                        ? Icon(Icons.check, size: 16, color: p.accent)
                        : const SizedBox.shrink(),
                    onTap: () => wallpaper.usePreset(preset.id),
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
                        child: Text(
                          l10n.wallpaperBrowseHint,
                          style: text.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 10),
                      OasisButton(
                        label: l10n.wallpaperBrowse,
                        variant: OasisButtonVariant.primary,
                        onPressed: _browse,
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

  String _presetName(OasisLocalizations l10n, String id) =>
      switch (id) {
        'peaks' => l10n.wallpaperPeaks,
        'aurora' => l10n.wallpaperAurora,
        'ember' => l10n.wallpaperEmber,
        _ => l10n.wallpaperDunes,
      };

  Future<void> _browse() async {
    final path = await _pickImage(context);
    if (path == null || !mounted) return;
    widget.wallpaper.imagePath = path;
  }

  Future<String?> _pickImage(BuildContext context) {
    final home = Platform.environment['HOME'];
    final pictures = home == null ? '' : '$home/Pictures';
    final startDir = Directory(pictures).existsSync() ? pictures : null;
    return showOasisFilePicker(
      context,
      title: OasisLocalizations.of(context).wallpaperPickTitle,
      initialDir: startDir,
      extensions: FileItem.imageExtensions,
      backend: widget.filesBackend,
    );
  }
}
