import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

class AboutWindow extends StatelessWidget {
  const AboutWindow({super.key, required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final host = OasisHost.maybeOf(context);

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const OasisAppIcon(
            icon: Icons.water_drop,
            colors: [Color(0xFF4FC3F7), Color(0xFF0078C8)],
            size: 84,
          ),
          const SizedBox(height: 16),
          Text(l10n.appName,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(l10n.versionLabel(version),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(
            l10n.aboutTagline,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: p.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 340,
            child: host == null
                ? null
                : UpdateCheckTile(
                    service: host.updates!, onOpenUrl: host.openUrl),
          ),
        ],
      ),
    );
  }
}
