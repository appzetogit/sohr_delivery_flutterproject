import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/incentive_offer.dart';

/// A compact offer row for everything below the hero card.
///
/// Deliberately flatter than the hero: one screen with two competing focal
/// points has none, and the rider only has attention for the offer they can
/// actually finish next.
class IncentiveOfferCard extends StatelessWidget {
  const IncentiveOfferCard({super.key, required this.offer});

  final IncentiveOffer offer;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final target = offer.activeTarget;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹${offer.targetAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: offer.progress.clamp(0.0, 1.0).toDouble()),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 7,
                backgroundColor: c.surfaceVariant,
                valueColor: AlwaysStoppedAnimation(
                  offer.isComplete ? AppColors.success : AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.isComplete
                      ? 'Target reached'
                      : '${offer.currentOrders} of $target deliveries',
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                ),
              ),
              if (offer.repeatable) ...[
                _Chip(
                  label: 'Repeatable',
                  fg: AppColors.primaryDark,
                  bg: AppColors.primary.withValues(alpha: 0.12),
                ),
                const SizedBox(width: 6),
              ],
              if (offer.isUrgent) _urgencyChip(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _urgencyChip() {
    final days = offer.daysLeft;
    final left = offer.remainingRedemptions;
    final label = (days != null && days <= 2)
        ? (days <= 0 ? 'Ends today' : 'Ends in ${days}d')
        : 'Only $left left';
    return _Chip(
      label: label,
      fg: AppColors.pendingText,
      bg: AppColors.pendingBg,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.fg, required this.bg});

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
