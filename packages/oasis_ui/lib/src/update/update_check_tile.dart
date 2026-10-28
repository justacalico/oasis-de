import 'package:flutter/material.dart';

import '../../l10n/generated/oasis_localizations.dart';
import '../theme/oasis_theme.dart';
import '../widgets/oasis_button.dart';
import 'update_service.dart';

class UpdateCheckTile extends StatelessWidget {
  const UpdateCheckTile({
    super.key,
    required this.service,
    this.onOpenUrl,
  });

  final UpdateService service;
  final ValueChanged<String>? onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final text = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final update = service.update;
        Widget status;
        if (service.checking) {
          status = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: p.accent),
              ),
              const SizedBox(width: 8),
              Text(l10n.updateChecking, style: text.bodySmall),
            ],
          );
        } else if (service.failed) {
          status = Text(l10n.updateFailed, style: text.bodySmall);
        } else if (update == null) {
          status = const SizedBox.shrink();
        } else if (update.updateAvailable) {
          status = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.updateAvailable(update.latestVersion),
                  style: text.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OasisButton(
                    label: l10n.updateViewRelease,
                    dense: true,
                    onPressed: onOpenUrl == null
                        ? null
                        : () => onOpenUrl!(update.releaseUrl),
                  ),
                  const SizedBox(width: 8),
                  OasisButton(
                    label: l10n.updateAllReleases,
                    variant: OasisButtonVariant.text,
                    dense: true,
                    onPressed: onOpenUrl == null
                        ? null
                        : () => onOpenUrl!(service.releasesPageUrl),
                  ),
                ],
              ),
            ],
          );
        } else {
          status = Text(l10n.updateUpToDate, style: text.bodySmall);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.updateCheck, style: text.bodyMedium),
                  const SizedBox(height: 4),
                  status,
                ],
              ),
            ),
            const SizedBox(width: 10),
            OasisButton(
              label: l10n.updateCheck,
              dense: true,
              onPressed: service.checking ? null : () => service.check(),
            ),
          ],
        );
      },
    );
  }
}
