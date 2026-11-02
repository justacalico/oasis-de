import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

/// Rebuilds whenever the wall-clock minute rolls over. The timer is armed
/// for the next minute boundary rather than polling, so it fires exactly
/// once per minute.
class MinuteClock extends StatefulWidget {
  const MinuteClock({super.key, required this.builder});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<MinuteClock> createState() => _MinuteClockState();
}

class _MinuteClockState extends State<MinuteClock> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = clock.now();
    _scheduleTick();
  }

  void _scheduleTick() {
    final next = DateTime(
      _now.year,
      _now.month,
      _now.day,
      _now.hour,
      _now.minute + 1,
    );
    _timer = Timer(next.difference(_now), _tick);
  }

  void _tick() {
    if (mounted) {
      setState(() => _now = clock.now());
      _scheduleTick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
