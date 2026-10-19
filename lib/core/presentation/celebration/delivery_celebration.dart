import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../services/haptic_service.dart';
import '../../theme/app_colors.dart';
import 'confetti.dart';

/// The delivery-complete celebration, modelled on the customer app's
/// coupon-applied one: a confetti burst behind a card that springs in, and a
/// single Continue that takes the rider home.
///
/// Shown only once the server has accepted the completion, so a failed
/// finish never gets a party — the caller awaits this and navigates when it
/// returns.
///
/// [earning] is what the rider made on this trip, straight off the order, and
Future<void> showDeliveryCelebration(
  BuildContext context, {
  required double earning,
  String? vertical,
  required int seed,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _DeliveryCelebration(
      earning: earning,
      accent: AppColors.primary,
      badge: '🍔  FOOD DELIVERY',
      seed: seed,
    ),
  );
}

class _DeliveryCelebration extends StatefulWidget {
  const _DeliveryCelebration({
    required this.earning,
    required this.accent,
    required this.badge,
    required this.seed,
  });

  final double earning;
  final Color accent;
  final String badge;

  /// Fixes the chip layout, so one delivery always bursts the same way.
  final int seed;

  @override
  State<_DeliveryCelebration> createState() => _DeliveryCelebrationState();
}

class _DeliveryCelebrationState extends State<_DeliveryCelebration>
    with SingleTickerProviderStateMixin {
  static const _burst = Duration(milliseconds: 2600);

  late final AnimationController _confetti = AnimationController(
    vsync: this,
    duration: _burst,
  )..forward();

  @override
  void initState() {
    super.initState();
    HapticService.success();
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  late final List<ConfettiParticle> _particles = ConfettiParticle.burst(
    count: 85,
    seed: widget.seed,
  );

  @override
  Widget build(BuildContext context) {
    final earned = widget.earning % 1 == 0
        ? widget.earning.toStringAsFixed(0)
        : widget.earning.toStringAsFixed(2);

    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Confetti sits behind and around the card, and ignores pointers so
          // Continue stays reachable while the burst is still running.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _confetti,
                builder: (context, _) => CustomPaint(
                  painter: ConfettiPainter(
                    particles: _particles,
                    progress: _confetti.value,
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.w),
              child: ScaleTransition(
                // Springs in over the first slice of the burst, so the card
                // arrives with the chips rather than after them.
                scale: CurvedAnimation(
                  parent: _confetti,
                  curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
                ),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24.r),
                  elevation: 12,
                  shadowColor: Colors.black.withValues(alpha: 0.2),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24.w, 28.h, 24.w, 22.h),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _confetti,
                          builder: (context, child) {
                            final scale = 0.8 + 0.2 * CurvedAnimation(
                              parent: _confetti,
                              curve: const Interval(0.1, 0.5, curve: Curves.elasticOut),
                            ).value;
                            return Transform.scale(
                              scale: scale,
                              child: child,
                            );
                          },
                          child: Container(
                            height: 68.r,
                            width: 68.r,
                            decoration: BoxDecoration(
                              color: widget.accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: widget.accent.withValues(alpha: 0.25),
                                  blurRadius: 16.r,
                                  spreadRadius: 2.r,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.check_rounded,
                              size: 36.sp,
                              color: widget.accent,
                            ),
                          ),
                        ),
                        SizedBox(height: 14.h),
                        Text(
                          'Delivery complete',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF6B7A70),
                          ),
                        ),
                        SizedBox(height: 6.h),
                        // The earning is the headline: it is the one number a
                        // rider wants at the end of a trip.
                        Text(
                          'You earned ₹$earned',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24.sp,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                            color: const Color(0xFF16211A),
                          ),
                        ),
                        SizedBox(height: 12.h),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14.w,
                            vertical: 6.h,
                          ),
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: widget.accent.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            widget.badge,
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: widget.accent,
                            ),
                          ),
                        ),
                        SizedBox(height: 14.h),
                        Text(
                          'Added to your earnings 🎉',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.sp,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF6B7A70),
                          ),
                        ),
                        SizedBox(height: 22.h),
                        SizedBox(
                          width: double.infinity,
                          height: 48.h,
                          child: ElevatedButton(
                            onPressed: () {
                              HapticService.light();
                              Navigator.of(context).pop();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.accent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14.r),
                              ),
                            ),
                            child: Text(
                              'Continue',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15.sp,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
