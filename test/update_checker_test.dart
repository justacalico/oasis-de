import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_landing/services/release_client.dart';
import 'package:oasis_ui/oasis_ui.dart';

UpdateChecker _checker(http.Client client) =>
    UpdateChecker(client: client, projectPath: 'a/b', host: 'example.com');

String _page(List<Map<String, dynamic>> releases) => jsonEncode(releases);

void main() {
  test('skips prerelease tags for stable users', () async {
    final client = MockClient((req) async => http.Response(
          _page([
            {'tag_name': 'v2.0.0-beta'},
            {'tag_name': 'v1.2.0'},
          ]),
          200,
        ));
    final update = await _checker(client).check('1.0.0');
    expect(update.latestVersion, '1.2.0');

    final beta = await _checker(client).check('1.0.0-beta');
    expect(beta.latestVersion, '2.0.0-beta');
  });

  test('finds the highest semver tag across pages', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      final page = req.url.queryParameters['page'];
      if (page == '1') {
        final items = List.generate(100, (i) => {'tag_name': 'v0.$i.0'});
        items.add({'tag_name': 'not-a-version'});
        return http.Response(_page(items), 200);
      }
      return http.Response(
        _page([
          {'tag_name': 'v1.2.0'},
          {'tag_name': 'v1.10.0'},
        ]),
        200,
      );
    });
    final update = await _checker(client).check('1.0.0');
    expect(calls, 2);
    expect(update.latestVersion, '1.10.0');
    expect(update.updateAvailable, isTrue);
    expect(update.releaseUrl, 'https://example.com/a/b/-/releases/v1.10.0');
  });

  test('reports no update when current is newest', () async {
    final client = MockClient(
      (req) async => http.Response(
        _page([
          {'tag_name': 'v0.9.0'},
          {'tag_name': 'v1.0.0'},
        ]),
        200,
      ),
    );
    final update = await _checker(client).check('1.0.0');
    expect(update.updateAvailable, isFalse);
    expect(update.latestVersion, '1.0.0');
  });

  test('unparsable current version still reports the latest', () async {
    final client = MockClient(
      (req) async => http.Response(
        _page([
          {'tag_name': 'v2.0.0'},
        ]),
        200,
      ),
    );
    final update = await _checker(client).check('dev-build');
    expect(update.updateAvailable, isTrue);
    expect(update.latestVersion, '2.0.0');
    expect(update.currentVersion, 'dev-build');
  });

  test('no releases at all yields an empty result', () async {
    final client = MockClient((req) async => http.Response('[]', 200));
    final update = await _checker(client).check('1.0.0');
    expect(update.updateAvailable, isFalse);
    expect(update.latestVersion, '');
    expect(update.releaseUrl, 'https://example.com/a/b/-/releases');
  });

  test('skips non-map entries, non-string tags and odd bodies', () async {
    final client = MockClient(
      (req) async => http.Response(
        jsonEncode([
          42,
          {'tag_name': 7},
          {'other': true},
          {'tag_name': 'v3.0.0-beta.1'},
          {'tag_name': 'v3.0.0-alpha'},
        ]),
        200,
      ),
    );
    final update = await _checker(client).check('3.0.0');
    expect(update.latestVersion, '');
    expect(update.updateAvailable, isFalse);
  });

  test('http error throws VersionCheckException', () async {
    final client = MockClient((req) async => http.Response('nope', 500));
    expect(
      () => _checker(client).check('1.0.0'),
      throwsA(isA<VersionCheckException>()),
    );
  });

  test('non-list body throws VersionCheckException', () async {
    final client = MockClient((req) async => http.Response('{"a":1}', 200));
    expect(
      () => _checker(client).check('1.0.0'),
      throwsA(isA<VersionCheckException>()),
    );
  });

  test('network failure is wrapped', () async {
    final client = MockClient((req) async => throw Exception('down'));
    expect(
      () => _checker(client).check('1.0.0'),
      throwsA(
        isA<VersionCheckException>().having(
          (e) => e.toString(),
          'msg',
          contains('down'),
        ),
      ),
    );
  });

  test('exception message formats', () {
    expect(
      const VersionCheckException('x').toString(),
      'VersionCheckException: x',
    );
  });

  test('close is safe with and without a client', () {
    _checker(MockClient((_) async => http.Response('[]', 200))).close();
    UpdateChecker().close();
  });

  test('AppUpdate equality and hashCode', () {
    const a = AppUpdate(
      currentVersion: '1.0.0',
      latestVersion: '1.2.0',
      updateAvailable: true,
      releaseUrl: 'r',
    );
    const b = AppUpdate(
      currentVersion: '1.0.0',
      latestVersion: '1.2.0',
      updateAvailable: true,
      releaseUrl: 'r',
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == const AppUpdate(), isFalse);
    expect(a == Object(), isFalse);
  });

  test('ReleaseClient releasesUrl honours host and project', () {
    expect(
      ReleaseClient(
        client: MockClient((_) async => http.Response('[]', 200)),
        host: 'gitlab.test',
        projectPath: 'x/y',
      ).releasesUrl,
      'https://gitlab.test/x/y/-/releases',
    );
    expect(
      ReleaseClient().releasesUrl,
      'https://gitlab.com/HttpAnimations/oasis-de/-/releases',
    );
  });
}
