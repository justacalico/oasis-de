import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_update.dart';
import 'version.dart';

class VersionCheckException implements Exception {
  final String message;

  const VersionCheckException(this.message);

  @override
  String toString() => 'VersionCheckException: $message';
}

class UpdateChecker {
  UpdateChecker({
    http.Client? client,
    this.projectPath = 'HttpAnimations/oasis-de',
    this.host = 'gitlab.com',
  })  : _client = client,
        _ownsClient = client == null;

  final String projectPath;
  final String host;

  static const _perPage = 100;
  static const _maxPages = 10;

  http.Client? _client;
  final bool _ownsClient;

  String get releasesUrl => 'https://$host/$projectPath/-/releases';

  Future<AppUpdate> check(String currentVersion) async {
    final current = Version.parse(currentVersion);
    final latest = await _fetchLatestRelease(
      allowPrerelease: current?.pre != null,
    );
    if (latest == null) {
      return AppUpdate(
        currentVersion: currentVersion,
        releaseUrl: releasesUrl,
      );
    }

    final latestVersion = latest.version;
    final releaseUrl = _releaseUrl(latest.tag);

    if (current == null) {
      return AppUpdate(
        currentVersion: currentVersion,
        latestVersion: latestVersion.toString(),
        updateAvailable: true,
        releaseUrl: releaseUrl,
        asset: latest.asset,
      );
    }

    return AppUpdate(
      currentVersion: currentVersion,
      latestVersion: latestVersion.toString(),
      updateAvailable: latestVersion.compareTo(current) > 0,
      releaseUrl: releaseUrl,
      asset: latest.asset,
    );
  }

  Future<List<int>> fetch(Uri uri) async {
    final client = _client ??= http.Client();
    final response = await client
        .get(uri)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw VersionCheckException('HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  void close() {
    if (_ownsClient) {
      _client?.close();
      _client = null;
    }
  }

  Future<({Version version, String tag, UpdateAsset? asset})?>
      _fetchLatestRelease({
    bool allowPrerelease = false,
  }) async {
    Version? maxVersion;
    String? maxTag;
    UpdateAsset? maxAsset;
    for (var page = 1; page <= _maxPages; page++) {
      final uri = Uri(
        scheme: 'https',
        host: host,
        pathSegments: ['api', 'v4', 'projects', projectPath, 'releases'],
        queryParameters: {
          'per_page': '$_perPage',
          'order_by': 'released_at',
          'sort': 'desc',
          'page': '$page',
        },
      );

      try {
        final client = _client ??= http.Client();
        final response = await client
            .get(uri, headers: {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          throw VersionCheckException('HTTP ${response.statusCode}');
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! List<dynamic>) {
          throw const VersionCheckException('unexpected response shape');
        }

        for (final release in decoded) {
          if (release is! Map<String, dynamic>) continue;
          final tag = release['tag_name'];
          if (tag is! String) continue;
          final version = Version.parse(tag);
          if (version == null) continue;
          if (!allowPrerelease && version.pre != null) continue;
          if (maxVersion == null || version.compareTo(maxVersion) > 0) {
            maxVersion = version;
            maxTag = tag;
            maxAsset = _releaseAsset(release);
          }
        }

        if (decoded.length < _perPage) break;
      } catch (e) {
        if (e is VersionCheckException) rethrow;
        throw VersionCheckException('$e');
      }
    }

    if (maxVersion == null || maxTag == null) return null;
    return (version: maxVersion, tag: maxTag, asset: maxAsset);
  }

  static const _packageSuffixes = [
    '.deb',
    '.rpm',
    '.pkg.tar.zst',
  ];

  UpdateAsset? _releaseAsset(Map<String, dynamic> release) {
    final assets = release['assets'];
    if (assets is! Map<String, dynamic>) return null;
    final links = assets['links'];
    if (links is! List<dynamic>) return null;

    String? checksum;
    final packages = <({String name, String url})>[];
    for (final link in links) {
      if (link is! Map<String, dynamic>) continue;
      final name = link['name'];
      final url = link['direct_asset_url'] ?? link['url'];
      if (name is! String || url is! String) continue;
      final lower = name.toLowerCase();
      if (lower.endsWith('.sha256') ||
          lower == 'sha256sums' ||
          lower == 'sha256sums.txt') {
        checksum = url;
      } else if (_packageSuffixes.any(lower.endsWith)) {
        packages.add((name: name, url: url));
      }
    }
    if (packages.isEmpty) return null;
    final pkg = packages.first;
    return UpdateAsset(
      name: pkg.name,
      url: pkg.url,
      checksumUrl: checksum,
    );
  }

  String _releaseUrl(String tag) =>
      '$releasesUrl/${Uri.encodeComponent(tag)}';
}
