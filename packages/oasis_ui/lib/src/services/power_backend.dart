abstract class OasisPowerBackend {
  /// Applies idle power timeouts. A null duration means "never".
  Future<void> setIdleTimeouts({Duration? displayOff, Duration? suspend});
}

class NoopPowerBackend implements OasisPowerBackend {
  const NoopPowerBackend();

  @override
  Future<void> setIdleTimeouts(
      {Duration? displayOff, Duration? suspend}) async {}
}
