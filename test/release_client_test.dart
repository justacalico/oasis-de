import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_landing/services/release_client.dart';

ReleaseClient _client(http.Client c) =>
    ReleaseClient(client: c, projectPath: 'x/y', host: 'gitlab.test');

void main() {
  test('parses releases and their assets', () async {
    final client = MockClient((req) async => http.Response(
        jsonEncode([
          {
            'tag_name': 'v1.0.0',
            'name': 'Oasis 1.0.0',
            'assets': {
              'links': [
                {
                  'name': 'oasis.deb',
                  'direct_asset_url': 'https://dl/oasis.deb',
                  'url': 'https://page',
                },
                {'name': 'oasis.zip', 'url': 'https://dl/oasis.zip'},
                {'name': 4, 'url': 'https://bad'},
                'junk',
              ],
            },
          },
          'skipped',
          {'tag_name': 'v0.9.0'},
        ]),
        200));
    final releases = await _client(client).fetch();
    expect(releases.length, 2);
    expect(releases.first.tag, 'v1.0.0');
    expect(releases.first.name, 'Oasis 1.0.0');
    expect(releases.first.url,
        'https://gitlab.test/x/y/-/releases/v1.0.0');
    expect(releases.first.assets.map((a) => a.name),
        ['oasis.deb', 'oasis.zip']);
    expect(releases.first.assets[1].url, 'https://dl/oasis.zip');
    expect(releases.last.name, 'v0.9.0');
    expect(releases.last.assets, isEmpty);
    expect(_client(client).releasesUrl,
        'https://gitlab.test/x/y/-/releases');
  });

  test('paginates while pages are full', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response(
          jsonEncode(
              List.generate(20, (i) => {'tag_name': 'v0.$i.0'})),
          200);
    });
    final releases = await _client(client).fetch();
    expect(calls, 3);
    expect(releases.length, 60);
  });

  test('http error throws', () async {
    final client = MockClient((req) async => http.Response('x', 404));
    expect(() => _client(client).fetch(),
        throwsA(isA<ReleaseClientException>()));
  });

  test('non-list body throws', () async {
    final client =
        MockClient((req) async => http.Response('{"x":1}', 200));
    expect(() => _client(client).fetch(),
        throwsA(isA<ReleaseClientException>()));
  });
}
