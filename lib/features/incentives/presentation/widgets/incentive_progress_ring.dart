import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Circular progress for one incentive cycle.
///
/// Animates from its previous value rather than snapping, so finishing a
/// delivery visibly moves the ring when the rider lands back on this screen --
/// that movement is most of what makes the feature feel alive.
///
/// Goes green only at 100%. Green is a status colour in this app, never a brand
/// accent, so an in-progress ring stays purple.
class IncentiveProgressRing extends StatelessWidget {
  const IncentiveProgressRing({
    super.key,
    required this.progress,
    required this.current,
    required this.target,
    this.size = 132,
    this.strokeWidth = 11,
  });

  final double progress;
  final int current;
  final int target;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final complete = progress >= 1;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0).toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(size),
                painter: _RingPainter(
                  progress: value,
                  strokeWidth: strokeWidth,
                  trackColor: c.isDark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.lightSurfaceVariant,
                  gradient: complete
                      ? const [AppColors.success, AppColors.success]
                      : const [AppColors.primaryLight, AppColors.primary],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (complete)
                    Icon(
                      Icons.check_rounded,
                      size: size * 0.30,
                      color: AppColors.success,
                    )
                  else
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '$current',
                            style: TextStyle(
                              fontSize: size * 0.27,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                              height: 1,
                            ),
                          ),
                          TextSpan(
                            text: '/$target',
                            style: TextStyle(
                              fontSize: size * 0.15,
                              fontWeight: FontWeight.w600,
                              color: c.textSecondary,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    complete ? 'Unlocked' : 'deliveries',
                    style: TextStyle(
                      fontSize: size * 0.085,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: complete ? AppColors.successText : c.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.gradient,
  });

  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final List<Color> gradient;

  static const _start = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.width - strokeWidth) / 2;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;

    final arc = Paint()
      ..shader = SweepGradient(
        startAngle: _start,
        endAngle: _start + math.pi * 2,
        colors: gradient,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _start,
      math.pi * 2 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
