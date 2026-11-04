import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'app_update.dart';
import 'update_checker.dart';

typedef UpdateDownloader = Future<List<int>> Function(Uri uri);
typedef UpdateInstaller = Future<bool> Function(String path);
typedef UpdateFileWriter = Future<void> Function(File file, List<int> bytes);
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

abstract class OasisUpdateApi extends ChangeNotifier {
  AppUpdate? get update;
  bool get checking;
  bool get failed;
  bool get installing;
  bool get installDone;
  bool get installFailed;
  String get releasesPageUrl;
  Future<AppUpdate?> check();
  Future<bool> install();
}

class UpdateService extends OasisUpdateApi {
  UpdateService({
    UpdateChecker? checker,
    required Future<String> Function() currentVersion,
    UpdateDownloader? downloader,
    UpdateInstaller? installer,
    UpdateFileWriter? writeFile,
    ProcessRunner? runProcess,
    List<String>? assetPreference,
    String? osReleasePath,
  })  : _checker = checker ??
            UpdateChecker(
              assetPreference: assetPreference ??
                  _detectAssetPreference(osReleasePath) ??
                  const [],
            ),
        _currentVersion = currentVersion,
        _downloader = downloader,
        _installer = installer,
        _writeFile = writeFile,
        _runProcess = runProcess ?? Process.run;

  final UpdateChecker _checker;
  final Future<String> Function() _currentVersion;
  final UpdateDownloader? _downloader;
  final UpdateInstaller? _installer;
  final UpdateFileWriter? _writeFile;
  final ProcessRunner _runProcess;

  AppUpdate? _update;
  bool _checking = false;
  bool _failed = false;
  bool _installing = false;
  bool _installDone = false;
  bool _installFailed = false;
  Future<AppUpdate?>? _inFlight;

  @override
  AppUpdate? get update => _update;
  @override
  bool get checking => _checking;
  @override
  bool get failed => _failed;
  @override
  bool get installing => _installing;
  @override
  bool get installDone => _installDone;
  @override
  bool get installFailed => _installFailed;
  @override
  String get releasesPageUrl => _checker.releasesUrl;

  @override
  Future<AppUpdate?> check() {
    final existing = _inFlight;
    if (existing != null) return existing;
    return _inFlight = _run().whenComplete(() => _inFlight = null);
  }

  Future<AppUpdate?> _run() async {
    _checking = true;
    _failed = false;
    notifyListeners();
    try {
      final version = await _currentVersion();
      final update = await _checker.check(version);
      _update = update;
      _installDone = false;
      _installFailed = false;
      return update;
    } catch (_) {
      _failed = true;
      return null;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  @override
  Future<bool> install() async {
    final update = _update;
    final asset = update?.asset;
    if (update == null ||
        !update.updateAvailable ||
        asset == null ||
        _installing) {
      return false;
    }
    _installing = true;
    _installDone = false;
    _installFailed = false;
    notifyListeners();
    try {
      final download = _downloader ?? _checker.fetch;
      var ok = false;
      final sumUrl = asset.checksumUrl;
      if (sumUrl != null) {
        final bytes = await download(Uri.parse(asset.url));
        final sums = utf8.decode(await download(Uri.parse(sumUrl)));
        final sum = sha256.convert(bytes).toString();
        final safeName = asset.name.split(RegExp(r'[/\\]')).last;
        final nameOk =
            safeName.isNotEmpty && safeName != '.' && safeName != '..';
        if (nameOk && _checksumMatches(sums, sum, asset.name)) {
          final file = File(
            '${Directory.systemTemp.path}/oasis-$safeName',
          );
          final writer = _writeFile;
          if (writer != null) {
            await writer(file, bytes);
          } else {
            await file.writeAsBytes(bytes, flush: true);
          }
          final installer = _installer;
          ok = installer != null
              ? await installer(file.path)
              : await _systemInstall(file.path);
        }
      }
      _installDone = ok;
      _installFailed = !ok;
      return ok;
    } catch (_) {
      _installFailed = true;
      return false;
    } finally {
      _installing = false;
      notifyListeners();
    }
  }

  bool _checksumMatches(String sums, String sum, String name) {
    for (final raw in sums.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final m = RegExp(r'^([0-9a-fA-F]{64})\s*[ *]?(\S.*)?$')
          .firstMatch(line);
      if (m == null) continue;
      final hex = m.group(1)!.toLowerCase();
      final fname = (m.group(2) ?? '').trim();
      if (fname.isEmpty) return hex == sum;
      if (fname == name || fname.endsWith('/$name')) return hex == sum;
    }
    return false;
  }

  /// Picks a package suffix that matches the local distro so the checker
  /// prefers e.g. the rpm on Fedora instead of whatever link comes first.
  static List<String>? _detectAssetPreference([String? osReleasePath]) {
    if (kIsWeb) return null;
    try {
      final text = File(osReleasePath ?? '/etc/os-release')
          .readAsStringSync()
          .toLowerCase();
      final ids = RegExp(r'^(?:id|id_like)="?([a-z0-9 ]+)', multiLine: true)
          .allMatches(text)
          .expand((m) => m.group(1)!.split(RegExp(r'\s+')));
      for (final id in ids) {
        switch (id) {
          case 'debian':
          case 'ubuntu':
          case 'raspbian':
          case 'linuxmint':
          case 'pop':
            return const ['.deb'];
          case 'fedora':
          case 'rhel':
          case 'centos':
          case 'opensuse':
          case 'suse':
            return const ['.rpm'];
          case 'arch':
          case 'manjaro':
            return const ['.pkg.tar.zst'];
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _systemInstall(String path) async {
    try {
      final r = await _runProcess(
        'pkcon',
        ['install-local', '-y', path],
      );
      if (r.exitCode == 0) return true;
    } catch (_) {}
    final lower = path.toLowerCase();
    final tool = lower.endsWith('.deb')
        ? ['apt-get', 'install', '-y', path]
        : lower.endsWith('.rpm')
            ? ['dnf', 'install', '-y', path]
            : lower.endsWith('.pkg.tar.zst')
                ? ['pacman', '-U', '--noconfirm', path]
                : null;
    if (tool == null) return false;
    try {
      final r = await _runProcess('pkexec', tool);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _checker.close();
    super.dispose();
  }
}
