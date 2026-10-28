import 'dart:convert';

import 'package:http/http.dart' as http;

class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url});

  final String name;
  final String url;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.url,
    required this.assets,
  });

  final String tag;
  final String name;
  final String url;
  final List<ReleaseAsset> assets;
}

class ReleaseClientException implements Exception {
  const ReleaseClientException(this.message);

  final String message;
}

class ReleaseClient {
  ReleaseClient({
    http.Client? client,
    this.projectPath = 'HttpAnimations/oasis-de',
    this.host = 'gitlab.com',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String projectPath;
  final String host;

  static const _maxPages = 3;

  String get releasesUrl => 'https://$host/$projectPath/-/releases';

  Future<List<ReleaseInfo>> fetch() async {
    final all = <ReleaseInfo>[];
    for (var page = 1; page <= _maxPages; page++) {
      final uri = Uri(
        scheme: 'https',
        host: host,
        pathSegments: ['api', 'v4', 'projects', projectPath, 'releases'],
        queryParameters: {
          'per_page': '20',
          'order_by': 'released_at',
          'sort': 'desc',
          'page': '$page',
        },
      );
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw ReleaseClientException('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const ReleaseClientException('unexpected response shape');
      }
      for (final raw in decoded) {
        if (raw is! Map<String, dynamic>) continue;
        final tag = raw['tag_name'];
        if (tag is! String) continue;
        final name = raw['name'];
        final assets = <ReleaseAsset>[];
        final links = raw['assets'] is Map ? raw['assets']['links'] : null;
        if (links is List) {
          for (final l in links) {
            if (l is! Map) continue;
            final an = l['name'];
            final url = l['direct_asset_url'] ?? l['url'];
            if (an is String && url is String) {
              assets.add(ReleaseAsset(name: an, url: url));
            }
          }
        }
        all.add(ReleaseInfo(
          tag: tag,
          name: name is String ? name : tag,
          url: 'https://$host/$projectPath/-/releases/${Uri.encodeComponent(tag)}',
          assets: assets,
        ));
      }
      if (decoded.length < 20) break;
    }
    return all;
  }
}
