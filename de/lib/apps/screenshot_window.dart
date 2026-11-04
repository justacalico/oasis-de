import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../services/screenshot.dart';
import '../shell/shell_controller.dart';

/// The Screenshot app's window: pick region or full screen, an
/// optional countdown, and a preview of whatever was captured last.
class ScreenshotWindow extends StatefulWidget {
  const ScreenshotWindow({super.key, required this.controller});

  final ShellController controller;

  static const delays = [0, 3, 5, 10];

  @override
  State<ScreenshotWindow> createState() => _ScreenshotWindowState();
}

class _ScreenshotWindowState extends State<ScreenshotWindow> {
  ScreenshotMode _mode = ScreenshotMode.region;
  int _delay = 0;

  void _take() =>
      widget.controller.requestScreenshot(_mode, delaySeconds: _delay);

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: OasisButton(
                  label: l10n.screenshotModeRegion,
                  dense: true,
                  variant: _mode == ScreenshotMode.region
                      ? OasisButtonVariant.primary
                      : OasisButtonVariant.secondary,
                  onPressed: () =>
                      setState(() => _mode = ScreenshotMode.region),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OasisButton(
                  label: l10n.screenshotModeFullscreen,
                  dense: true,
                  variant: _mode == ScreenshotMode.fullscreen
                      ? OasisButtonVariant.primary
                      : OasisButtonVariant.secondary,
                  onPressed: () =>
                      setState(() => _mode = ScreenshotMode.fullscreen),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(l10n.screenshotDelay, style: text.bodyMedium),
              const SizedBox(width: 10),
              for (final d in ScreenshotWindow.delays) ...[
                if (d > 0) const SizedBox(width: 6),
                OasisButton(
                  label: d == 0
                      ? l10n.screenshotDelayNone
                      : l10n.screenshotDelaySeconds(d),
                  dense: true,
                  variant: _delay == d
                      ? OasisButtonVariant.primary
                      : OasisButtonVariant.secondary,
                  onPressed: () => setState(() => _delay = d),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OasisButton(
              label: l10n.screenshotTake,
              variant: OasisButtonVariant.primary,
              onPressed: _take,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.controller.screenshots,
              builder: (context, _) {
                final shots = widget.controller.screenshots;
                final image = shots.lastCapture;
                if (image == null) {
                  return Center(
                    child: Text(
                      l10n.screenshotNoCapture,
                      style: text.bodyMedium?.copyWith(color: p.textTertiary),
                    ),
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: p.cardBackground,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: RawImage(image: image, fit: BoxFit.contain),
                      ),
                    ),
                    if (shots.lastPath != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        shots.lastPath!,
                        style: text.bodySmall?.copyWith(color: p.textTertiary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
