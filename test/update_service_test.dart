import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_ui/oasis_ui.dart';

class _FakeChecker extends UpdateChecker {
  _FakeChecker(this.result);

  final AppUpdate? result;
  Object? error;
  var calls = 0;

  @override
  String get releasesUrl => 'https://gitlab.com/x/y/-/releases';

  @override
  Future<AppUpdate> check(String currentVersion) async {
    calls++;
    if (error != null) throw error!;
    return result!;
  }
}

void main() {
  test('check caches result and dedupes concurrent calls', () async {
    final checker = _FakeChecker(const AppUpdate(
        currentVersion: '1.0.0',
        latestVersion: '2.0.0',
        updateAvailable: true,
        releaseUrl: 'r'));
    final service = UpdateService(checker: checker, currentVersion: () async => '1.0.0');
    expect(service.checking, isFalse);
    final a = service.check();
    final b = service.check();
    expect(identical(a, b), isTrue);
    await a;
    expect(checker.calls, 1);
    expect(service.update!.latestVersion, '2.0.0');
    expect(service.checking, isFalse);
    expect(service.failed, isFalse);
    service.dispose();
  });

  test('failure sets failed and keeps cached update', () async {
    final checker = _FakeChecker(
        const AppUpdate(latestVersion: '2.0.0', updateAvailable: true));
    final service = UpdateService(checker: checker, currentVersion: () async => '1.0.0');
    await service.check();
    expect(service.update!.updateAvailable, isTrue);

    checker.error = Exception('net down');
    final result = await service.check();
    expect(result, isNull);
    expect(service.failed, isTrue);
    expect(service.update!.updateAvailable, isTrue);
    expect(service.releasesPageUrl, 'https://gitlab.com/x/y/-/releases');
    service.dispose();
  });

  test('default version provider resolves', () async {
    final checker = _FakeChecker(const AppUpdate());
    final service = UpdateService(checker: checker, currentVersion: () async => '1.0.0');
    await service.check();
    expect(checker.calls, 1);
    service.dispose();
  });

  AppUpdate installable(String name, {String? sum}) => AppUpdate(
        currentVersion: '1.0.0',
        latestVersion: '2.0.0',
        updateAvailable: true,
        releaseUrl: 'r',
        asset: UpdateAsset(
          name: name,
          url: 'https://x/$name',
          checksumUrl: sum == null ? null : 'https://x/$sum',
        ),
      );

  test('install without an update is a no-op', () async {
    final service = UpdateService(
      checker: _FakeChecker(const AppUpdate()),
      currentVersion: () async => '1.0.0',
    );
    expect(await service.install(), isFalse);
    expect(service.installDone, isFalse);
    service.dispose();
  });

  test('install downloads, verifies sha256 and runs installer', () async {
    final bytes = utf8.encode('pkg-bytes');
    final hex = sha256.convert(bytes).toString();
    String? installed;
    final service = UpdateService(
      checker: _FakeChecker(installable('oasis_2.0.0_amd64.deb',
          sum: 'sums')),
      currentVersion: () async => '1.0.0',
      downloader: (uri) async => uri.path.endsWith('sums')
          ? utf8.encode('$hex  oasis_2.0.0_amd64.deb\n')
          : bytes,
      installer: (path) async {
        installed = path;
        return File(path).readAsBytes().then((b) => b.isNotEmpty);
      },
    );
    await service.check();
    expect(await service.install(), isTrue);
    expect(installed, endsWith('oasis-oasis_2.0.0_amd64.deb'));
    expect(service.installDone, isTrue);
    expect(service.installFailed, isFalse);
    service.dispose();
  });

  test('install refuses a mismatched checksum', () async {
    var installerRan = false;
    final service = UpdateService(
      checker: _FakeChecker(installable('oasis.deb', sum: 'sums')),
      currentVersion: () async => '1.0.0',
      downloader: (uri) async => uri.path.endsWith('sums')
          ? utf8.encode('${'0' * 64}  oasis.deb\n')
          : utf8.encode('payload'),
      installer: (_) async {
        installerRan = true;
        return true;
      },
    );
    await service.check();
    expect(await service.install(), isFalse);
    expect(installerRan, isFalse);
    expect(service.installFailed, isTrue);
    service.dispose();
  });

  test('install without a checksum url refuses', () async {
    final service = UpdateService(
      checker: _FakeChecker(installable('oasis.deb')),
      currentVersion: () async => '1.0.0',
      downloader: (_) async => throw StateError('should not download'),
    );
    await service.check();
    expect(await service.install(), isFalse);
    expect(service.installFailed, isTrue);
    service.dispose();
  });

  test('install tolerates downloader failure', () async {
    final service = UpdateService(
      checker: _FakeChecker(installable('oasis.deb', sum: 'sums')),
      currentVersion: () async => '1.0.0',
      downloader: (_) async => throw Exception('net down'),
    );
    await service.check();
    expect(await service.install(), isFalse);
    expect(service.installFailed, isTrue);
    expect(service.installing, isFalse);
    service.dispose();
  });

  test('default installer uses pkcon then falls back per distro', () async {
    final bytes = utf8.encode('pkg');
    final hex = sha256.convert(bytes).toString();
    final ran = <List<String>>[];
    final service = UpdateService(
      checker: _FakeChecker(installable('oasis_2.0.0_amd64.deb', sum: 's')),
      currentVersion: () async => '1.0.0',
      downloader: (uri) async =>
          uri.path.endsWith('s') ? utf8.encode(hex) : bytes,
      runProcess: (exe, args) async {
        ran.add([exe, ...args]);
        return ProcessResult(1, exe == 'pkexec' ? 0 : 1, '', '');
      },
    );
    await service.check();
    expect(await service.install(), isTrue);
    expect(ran.first.first, 'pkcon');
    expect(ran.last.first, 'pkexec');
    expect(ran.last[1], 'apt-get');
    service.dispose();
  });

  test('default installer handles pacman and unknown suffixes', () async {
    final bytes = utf8.encode('pkg');
    final hex = sha256.convert(bytes).toString();
    final ran = <List<String>>[];
    Future<ProcessResult> run(String exe, List<String> args) async {
      ran.add([exe, ...args]);
      return ProcessResult(1, exe == 'pkexec' ? 0 : 1, '', '');
    }

    Future<UpdateService> mk(String name) async {
      final s = UpdateService(
        checker: _FakeChecker(installable(name, sum: 's')),
        currentVersion: () async => '1.0.0',
        downloader: (uri) async =>
            uri.path.endsWith('s') ? utf8.encode(hex) : bytes,
        runProcess: run,
      );
      await s.check();
      return s;
    }

    final pac = await mk('oasis-2.0.0.pkg.tar.zst');
    expect(await pac.install(), isTrue);
    expect(ran.last[1], 'pacman');
    pac.dispose();

    final weird = await mk('oasis-2.0.0.flatpak');
    expect(await weird.install(), isFalse);
    weird.dispose();
  });

  test('default installer fails when no tool works', () async {
    final bytes = utf8.encode('pkg');
    final hex = sha256.convert(bytes).toString();
    final service = UpdateService(
      checker: _FakeChecker(installable('oasis-2.0.0.rpm', sum: 's')),
      currentVersion: () async => '1.0.0',
      downloader: (uri) async =>
          uri.path.endsWith('s') ? utf8.encode(hex) : bytes,
      runProcess: (exe, args) async {
        if (exe == 'pkexec') throw const ProcessException('pkexec', []);
        return ProcessResult(1, 1, '', 'no pkcon');
      },
    );
    await service.check();
    expect(await service.install(), isFalse);
    expect(service.installFailed, isTrue);
    service.dispose();
  });
}
