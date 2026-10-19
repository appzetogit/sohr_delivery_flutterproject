import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The confetti the app celebrates with, in normalised (0..1) coordinates so
/// one burst description paints correctly at any size — a full-screen dialog
/// or a single card.
///
/// Lifted verbatim from the customer app's `lib/src/shared/celebration/
/// confetti.dart` so a completed delivery bursts exactly the way an applied
/// coupon does. Kept as a copy rather than a shared package: the two apps do
/// not share code, and the physics here is 160 lines with no dependencies
/// beyond dart:math. If you tune one, tune the other.
/// One confetti chip: where it starts, where it drifts, and how it tumbles.
class ConfettiParticle {
  const ConfettiParticle({
    required this.origin,
    required this.velocity,
    required this.color,
    required this.size,
    required this.spin,
    required this.round,
  });

  final Offset origin;
  final Offset velocity;
  final Color color;
  final double size;
  final double spin;
  final bool round;

  /// Normalised centre at [t] (0..1): the launch vector plus gravity. Exposed
  /// so a test can prove chips are actually on screen mid-burst — a burst that
  /// flies off instantly looks identical to one that never rendered.
  Offset positionAt(double t) => Offset(
        origin.dx + velocity.dx * t,
        origin.dy + velocity.dy * t + _gravity * t * t * 0.5,
      );

  /// Gravity in normalised units, tuned so chips float high up into top screen area.
  static const _gravity = 0.65;

  static const _palette = [
    Color(0xFFFFC107),
    Color(0xFFFF6B6B),
    Color(0xFF4ECDC4),
    Color(0xFF7C5CFF),
    Color(0xFF2ECC71),
    Color(0xFFFF8A3D),
    Color(0xFF3498DB),
    Color(0xFFE91E63),
  ];

  /// A contained burst from one point, for celebrating inside a card.
  ///
  /// [burst]'s screen-wide cannons and top cascade read as noise in a box a
  /// hundred pixels tall, and its chips are sized for a full screen. This fans
  /// upward from [origin] and falls back under the same gravity, so the whole
  /// thing happens within the card it is painted over.
  ///
  /// The horizontal travel is deliberately the smaller of the two: normalised
  /// coordinates stretch to the paint box, and a card is far wider than it is
  /// tall, so an even fan would throw chips off the sides while barely lifting
  /// them.
  static List<ConfettiParticle> pop({
    required int count,
    required int seed,
    Offset origin = const Offset(0.5, 0.5),
    List<Color> palette = _palette,
  }) {
    final rand = math.Random(seed);
    return List.generate(count, (i) {
      // Spread across the half-circle above the origin, one chip per slice, so
      // they fan out instead of travelling as a clump.
      final angle = -math.pi + (i + rand.nextDouble()) / count * math.pi;
      final speed = 0.55 + rand.nextDouble() * 0.45;
      return ConfettiParticle(
        origin: origin,
        velocity: Offset(
          math.cos(angle) * speed * 0.30,
          math.sin(angle) * speed * 0.95,
        ),
        color: palette[rand.nextInt(palette.length)],
        size: 3.5 + rand.nextDouble() * 3.5,
        spin: (rand.nextDouble() - 0.5) * 9,
        round: rand.nextBool(),
      );
    });
  }

  /// Upward fans and top-floating confetti particles that cover the top of screen.
  static List<ConfettiParticle> burst({required int count, required int seed}) {
    final rand = math.Random(seed);
    return List.generate(count, (i) {
      if (i < count * 0.75) {
        // Upward cannons from left/right lower-mid screen extending high to top
        final fromLeft = i.isEven;
        final angle = (fromLeft ? 1.0 : -1.0) *
            (math.pi / 8 + rand.nextDouble() * math.pi / 3);
        final speed = 0.85 + rand.nextDouble() * 0.70;
        return ConfettiParticle(
          origin: Offset(fromLeft ? 0.05 : 0.95, 0.60),
          velocity: Offset(math.sin(angle) * speed, -math.cos(angle) * speed),
          color: _palette[rand.nextInt(_palette.length)],
          size: 6 + rand.nextDouble() * 7,
          spin: (rand.nextDouble() - 0.5) * 12,
          round: rand.nextBool(),
        );
      } else {
        // High top-screen cascade floating down
        return ConfettiParticle(
          origin: Offset(
            0.05 + rand.nextDouble() * 0.90,
            -0.05 + rand.nextDouble() * 0.35,
          ),
          velocity: Offset(
            (rand.nextDouble() - 0.5) * 0.5,
            0.15 + rand.nextDouble() * 0.45,
          ),
          color: _palette[rand.nextInt(_palette.length)],
          size: 5 + rand.nextDouble() * 7,
          spin: (rand.nextDouble() - 0.5) * 10,
          round: rand.nextBool(),
        );
      }
    });
  }
}

class ConfettiPainter extends CustomPainter {
  const ConfettiPainter({required this.particles, required this.progress});

  final List<ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    final paint = Paint();
    // Fade out over the last third so the burst settles instead of vanishing.
    final fade = progress < 0.66 ? 1.0 : (1 - (progress - 0.66) / 0.34);

    for (final p in particles) {
      final at = p.positionAt(progress);
      final centre = Offset(at.dx * size.width, at.dy * size.height);
      if (centre.dy > size.height + 40) continue;

      paint.color = p.color.withValues(alpha: fade.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(p.spin * progress);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.55,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.progress != progress;
}
