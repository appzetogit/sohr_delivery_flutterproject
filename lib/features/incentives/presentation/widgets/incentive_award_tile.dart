import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/incentive_offer.dart';

/// One earned payout, with the status that answers "where is my money?".
///
/// `credited` is in the wallet; `pending` is waiting on an admin. Riders ask
/// support about this more than anything else, so the distinction is the whole
/// reason this row exists rather than a plain "earned" count.
class IncentiveAwardTile extends StatelessWidget {
  const IncentiveAwardTile({
    super.key,
    required this.award,
    required this.offerTitle,
  });

  final IncentiveAward award;
  final String offerTitle;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = _statusStyle(award.status);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: style.bg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(style.icon, size: 19, color: style.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  style.label,
                  style: TextStyle(fontSize: 12, color: style.fg),
                ),
              ],
            ),
          ),
          Text(
            '₹${award.amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              // Only real, banked money gets the success colour. A pending
              // amount in green would read as paid.
              color: award.status == 'credited'
                  ? AppColors.successText
                  : c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  _StatusStyle _statusStyle(String status) {
    switch (status) {
      case 'credited':
        return const _StatusStyle(
          label: 'Added to your wallet',
          icon: Icons.account_balance_wallet_rounded,
          fg: AppColors.successText,
          bg: AppColors.successBg,
        );
      case 'cancelled':
        return const _StatusStyle(
          label: 'Not approved',
          icon: Icons.close_rounded,
          fg: AppColors.errorText,
          bg: AppColors.errorBg,
        );
      case 'failed':
        return const _StatusStyle(
          label: 'Could not be paid',
          icon: Icons.error_outline_rounded,
          fg: AppColors.errorText,
          bg: AppColors.errorBg,
        );
      default:
        return const _StatusStyle(
          label: 'Waiting for approval',
          icon: Icons.hourglass_bottom_rounded,
          fg: AppColors.pendingText,
          bg: AppColors.pendingBg,
        );
    }
  }
}

class _StatusStyle {
  const _StatusStyle({
    required this.label,
    required this.icon,
    required this.fg,
    required this.bg,
  });

  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
}
