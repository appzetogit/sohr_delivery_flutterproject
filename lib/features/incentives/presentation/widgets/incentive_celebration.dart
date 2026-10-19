import 'package:flutter/material.dart';

import '../../../../core/presentation/celebration/confetti.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/theme/app_colors.dart';

/// The payoff moment: shown when the push says an incentive just unlocked.
///
/// Deliberately not [showDeliveryCelebration] — that one is badged FOOD/MART
/// DELIVERY and framed around a single trip's earning, which would read as the
/// wrong event here.
///
/// [pending] flips the wording for an offer whose payout still needs an admin
/// to release it. Telling a rider money has landed when it has not is the fast
/// way to lose their trust in the whole feature.
Future<void> showIncentiveCelebration(
  BuildContext context, {
  required String amount,
  required int seed,
  bool pending = false,
}) {
  HapticService.heavy();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) =>
        _IncentiveCelebration(amount: amount, seed: seed, pending: pending),
  );
}

class _IncentiveCelebration extends StatefulWidget {
  const _IncentiveCelebration({
    required this.amount,
    required this.seed,
    required this.pending,
  });

  final String amount;
  final int seed;
  final bool pending;

  @override
  State<_IncentiveCelebration> createState() => _IncentiveCelebrationState();
}

class _IncentiveCelebrationState extends State<_IncentiveCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();

  late final List<ConfettiParticle> _particles = ConfettiParticle.burst(
    count: 60,
    seed: widget.seed,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: ConfettiPainter(
                    particles: _particles,
                    progress: _controller.value,
                  ),
                ),
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryLight, AppColors.primary],
                      ),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: AppColors.onPrimary,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Incentive unlocked!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₹${widget.amount}',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.pending
                        ? 'It will reach your wallet once approved.'
                        : 'Added to your wallet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Great!',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
