import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../services/release_client.dart';

class DownloadsSection extends StatefulWidget {
  const DownloadsSection({
    super.key,
    required this.client,
    this.onOpenUrl,
  });

  final ReleaseClient client;
  final ValueChanged<String>? onOpenUrl;

  @override
  State<DownloadsSection> createState() => _DownloadsSectionState();
}

class _DownloadsSectionState extends State<DownloadsSection> {
  late Future<List<ReleaseInfo>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.client.fetch();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.landingDownloadsTitle, style: text.headlineMedium),
        const SizedBox(height: 8),
        Text(l10n.landingDownloadsBody,
            style: text.bodyMedium?.copyWith(color: p.textSecondary)),
        const SizedBox(height: 18),
        FutureBuilder<List<ReleaseInfo>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: p.accent),
                  ),
                  const SizedBox(width: 10),
                  Text(l10n.landingLoadingReleases, style: text.bodySmall),
                ],
              );
            }
            if (snap.hasError) {
              return Text(l10n.landingReleasesFailed,
                  style: text.bodySmall);
            }
            final releases = snap.data ?? const <ReleaseInfo>[];
            if (releases.isEmpty) {
              return Text(l10n.landingNoReleases, style: text.bodySmall);
            }
            final latest = releases.first;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final asset in latest.assets)
                      OasisButton(
                        label: asset.name,
                        variant: OasisButtonVariant.secondary,
                        onPressed: widget.onOpenUrl == null
                            ? null
                            : () => widget.onOpenUrl!(asset.url),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    OasisButton(
                      label: l10n.landingAllReleases,
                      variant: OasisButtonVariant.text,
                      onPressed: widget.onOpenUrl == null
                          ? null
                          : () => widget.onOpenUrl!(widget.client.releasesUrl),
                    ),
                    const SizedBox(width: 12),
                    Text(latest.tag, style: text.bodySmall),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
