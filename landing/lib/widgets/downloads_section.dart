import 'package:flutter/material.dart';

import '../services/user_agent.dart';
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
  late Future<ReleaseInfo?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.client.latest();
  }

  void _retry() => setState(() => _future = widget.client.latest());

  String _archOf(String name) {
    final n = name.toLowerCase();
    if (n.contains('aarch64') || n.contains('arm64')) return 'ARM64';
    if (n.contains('x86_64') || n.contains('amd64')) return 'x86_64';
    return '';
  }

  String _formatOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.deb')) return 'DEB';
    if (n.endsWith('.rpm')) return 'RPM';
    if (n.contains('appimage')) return 'AppImage';
    if (n.contains('flatpak')) return 'Flatpak';
    if (n.contains('.pkg.tar')) return 'Pacman';
    if (n.endsWith('.tar.gz') || n.endsWith('.tgz')) return 'Tarball';
    if (n.endsWith('.zip')) return 'ZIP';
    return 'Binary';
  }

  int _primaryIndex(List<ReleaseAsset> assets) {
    final ua = (webUserAgent() ?? '').toLowerCase();
    final preferArm = ua.contains('arm') || ua.contains('aarch64');
    var best = 0;
    var bestScore = -99;
    for (var i = 0; i < assets.length; i++) {
      final n = assets[i].name.toLowerCase();
      final arm = n.contains('aarch64') || n.contains('arm64');
      final x64 = n.contains('x86_64') || n.contains('amd64');
      var score = 0;
      if (preferArm ? arm : x64) score += 2;
      if (preferArm ? x64 : arm) score -= 2;
      if (n.endsWith('.deb')) score += 1;
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
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
        FutureBuilder<ReleaseInfo?>(
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
              return Row(
                children: [
                  Text(l10n.landingReleasesFailed,
                      style: text.bodySmall),
                  const SizedBox(width: 10),
                  OasisButton(
                    label: l10n.landingRetry,
                    variant: OasisButtonVariant.text,
                    onPressed: _retry,
                  ),
                ],
              );
            }
            final latest = snap.data;
            if (latest == null) {
              return Text(l10n.landingNoReleases, style: text.bodySmall);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (i, asset) in latest.assets.indexed)
                      OasisButton(
                        label:
                            '${_formatOf(asset.name)}${_archOf(asset.name).isEmpty ? '' : ' · ${_archOf(asset.name)}'}',
                        variant: i == _primaryIndex(latest.assets)
                            ? OasisButtonVariant.primary
                            : OasisButtonVariant.secondary,
                        onPressed: widget.onOpenUrl == null
                            ? null
                            : () => widget.onOpenUrl!(asset.url),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(latest.tag, style: text.bodySmall),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        OasisButton(
          label: l10n.landingAllReleases,
          variant: OasisButtonVariant.text,
          onPressed: widget.onOpenUrl == null
              ? null
              : () => widget.onOpenUrl!(widget.client.releasesUrl),
        ),
      ],
    );
  }
}
