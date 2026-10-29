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
}
