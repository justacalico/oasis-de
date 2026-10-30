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

class UpdateService extends ChangeNotifier {
  UpdateService({
    UpdateChecker? checker,
    required Future<String> Function() currentVersion,
    UpdateDownloader? downloader,
    UpdateInstaller? installer,
    UpdateFileWriter? writeFile,
    ProcessRunner? runProcess,
  })  : _checker = checker ?? UpdateChecker(),
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

  AppUpdate? get update => _update;
  bool get checking => _checking;
  bool get failed => _failed;
  bool get installing => _installing;
  bool get installDone => _installDone;
  bool get installFailed => _installFailed;
  String get releasesPageUrl => _checker.releasesUrl;

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
        if (_checksumMatches(sums, sum, asset.name)) {
          final file = File(
            '${Directory.systemTemp.path}/oasis-${asset.name}',
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
