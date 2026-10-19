import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rings [child] — a damped left-right swing pivoting on the point it hangs
/// from, the way a handbell settles after it is struck.
///
/// Driven by [trigger]: bump it and the bell rings once. An int rather than a
/// bool because two orders arriving back to back must ring twice, and a bool
/// would only toggle. The widget is otherwise inert, so it costs nothing on a
/// screen where nothing is arriving.
class BellShake extends StatefulWidget {
  const BellShake({
    super.key,
    required this.trigger,
    required this.child,
    this.duration = const Duration(milliseconds: 900),
  });

  /// Changes value each time the bell should ring.
  final int trigger;

  final Widget child;
  final Duration duration;

  @override
  State<BellShake> createState() => _BellShakeState();
}

class _BellShakeState extends State<BellShake>
    with SingleTickerProviderStateMixin {
  /// Swings each way this many times before it settles.
  static const _swings = 3.0;

  /// Peak tilt, in radians (~17°). Enough to read as a ring at 22sp without
  /// the icon looking like it is falling over.
  static const _maxAngle = 0.30;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didUpdateWidget(BellShake old) {
    super.didUpdateWidget(old);
    // forward(from: 0) rather than reset+forward: a second order arriving
    // mid-ring restarts the swing cleanly instead of stacking onto it.
    if (widget.trigger != old.trigger) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // The icon is built once and reused across every frame of the swing.
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        if (t == 0 || t == 1) return child!;

        // Amplitude decays over the swing so it eases to rest rather than
        // stopping dead. The exponent is what makes it feel like a bell
        // losing energy instead of a linear wobble.
        final decay = math.pow(1 - t, 1.6).toDouble();
        final angle = math.sin(t * math.pi * 2 * _swings) * _maxAngle * decay;

        return Transform.rotate(
          angle: angle,
          // A bell pivots where it hangs, not through its middle.
          alignment: Alignment.topCenter,
          child: child,
        );
      },
    );
  }
}
