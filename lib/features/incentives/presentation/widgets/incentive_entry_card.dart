import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/incentives_controller.dart';

/// Entry point to the incentives screen, shown on Pocket.
///
/// Renders nothing at all when there is no live offer. An empty promo slot on
/// the screen riders check for their money is worse than no slot: it trains
/// them to scroll past the position where the real thing will later appear.
class IncentiveEntryCard extends ConsumerWidget {
  const IncentiveEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(headlineIncentiveProvider);
    if (offer == null) return const SizedBox.shrink();

    final c = AppColors.of(context);
    final remaining = offer.remainingOrders;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/incentives'),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.onPrimary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: AppColors.onPrimary,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        offer.isComplete
                            ? '₹${offer.targetAmount.toStringAsFixed(0)} unlocked!'
                            : 'Earn ₹${offer.targetAmount.toStringAsFixed(0)} more',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        offer.isComplete
                            ? 'Tap to see your reward'
                            : remaining == 1
                            ? 'Just 1 more delivery'
                            : '$remaining more deliveries to go',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onPrimary.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 9),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 0,
                            end: offer.progress.clamp(0.0, 1.0).toDouble(),
                          ),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) =>
                              LinearProgressIndicator(
                                value: value,
                                minHeight: 6,
                                backgroundColor: AppColors.onPrimary.withValues(
                                  alpha: 0.25,
                                ),
                                valueColor: const AlwaysStoppedAnimation(
                                  AppColors.onPrimary,
                                ),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.onPrimary.withValues(alpha: 0.85),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
