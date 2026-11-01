import 'package:flutter/widgets.dart';

import '../wayland/wayland_service.dart';

/// Ratio of view pixels to compositor-logical pixels for the subtree below.
///
/// The shell lays chrome, windows and client surfaces out in compositor
/// logical coordinates (mode size divided by the output scale). Everything
/// that converts from global pointer or render coordinates back into that
/// space divides by this factor.
class ViewScale extends InheritedWidget {
  const ViewScale({super.key, required this.factor, required super.child});

  /// View pixels per compositor-logical pixel. `1` when the embedder already
  /// applies the output scale to the engine pixel ratio (KMS runner).
  final double factor;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ViewScale>()?.factor ?? 1;

  /// Converts a view-space offset (pointer position, `localToGlobal`) into
  /// compositor-logical coordinates.
  static Offset globalToLogical(BuildContext context, Offset global) =>
      global / of(context);

  @override
  bool updateShouldNotify(ViewScale old) => old.factor != factor;
}

/// Scales the whole shell to match the primary output's scale when the host
/// can't do it in the embedder. On KMS the engine pixel ratio already tracks
/// the output scale, so `factor` comes out to one and this wraps the child in
/// nothing but a [ViewScale] marker.
class ShellViewScaler extends StatelessWidget {
  const ShellViewScaler({super.key, this.wayland, required this.child});

  final WaylandService? wayland;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wl = wayland;
    if (wl == null) return ViewScale(factor: 1, child: child);
    return AnimatedBuilder(
      animation: wl,
      child: child,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scale = wl.primaryOutput?.scale ?? mq.devicePixelRatio;
        final k = scale / mq.devicePixelRatio;
        if ((k - 1).abs() < 0.01) {
          return ViewScale(factor: 1, child: child!);
        }
        final logical = mq.size / k;
        return ViewScale(
          factor: k,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Transform.scale(
              scale: k,
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: logical,
                child: MediaQuery(
                  data: mq.copyWith(
                    size: logical,
                    devicePixelRatio: scale,
                  ),
                  child: child!,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
