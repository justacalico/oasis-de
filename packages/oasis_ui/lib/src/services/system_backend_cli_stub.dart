import 'system_backend.dart';

class CliSystemBackend extends NoopSystemBackend {
  const CliSystemBackend({
    this.run,
    this.powerSupplyDir,
    this.startProcess,
    this.userName,
    this.drmDir,
  });

  final Object? run;
  final Object? powerSupplyDir;
  final Object? startProcess;
  final Object? userName;
  final Object? drmDir;
}
