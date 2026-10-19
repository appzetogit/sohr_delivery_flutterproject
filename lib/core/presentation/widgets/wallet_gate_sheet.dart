import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../services/haptic_service.dart';
import '../../theme/app_colors.dart';

/// What the rider chose in [showWalletGateSheet].
///
/// Both routes end on the Pocket screen, because that is where the Razorpay
/// checkout and the deposit flow actually live; this says which one to open
/// on arrival, so the choice is not decorative.
enum WalletGateAction { topUp, depositCash }

/// Set when the gate sheet is answered, read once by the Pocket screen.
///
/// A provider rather than a navigation argument: Pocket is a tab in an
/// IndexedStack, not a pushed route, so there is nothing to pass arguments to.
/// A Notifier, not StateProvider — Riverpod 3 dropped the latter.
class WalletGateActionNotifier extends Notifier<WalletGateAction?> {
  @override
  WalletGateAction? build() => null;

  void request(WalletGateAction action) => state = action;

  /// Read-and-clear, so switching back to Pocket later does not reopen it.
  ///
  /// Writes only when something is actually pending. An unconditional
  /// `state = null` still notifies, and that counts as modifying a provider —
  /// which throws if it lands during a build or initState.
  WalletGateAction? take() {
    final pending = state;
    if (pending != null) state = null;
    return pending;
  }
}

final walletGateActionProvider =
    NotifierProvider<WalletGateActionNotifier, WalletGateAction?>(
  WalletGateActionNotifier.new,
);

/// Shown when a rider under the admin's minimum wallet balance tries to go
/// online. A bottom sheet rather than an alert: the balance, the shortfall and
/// the ways out need room, and this reads as an action to take rather than an
/// error to dismiss.
///
/// Returns the chosen action, or null if the rider backed out. Going online is
/// refused by the server either way — nothing here decides that.
Future<WalletGateAction?> showWalletGateSheet(
  BuildContext context, {
  required Map<String, dynamic>? wallet,
  String? fallbackMessage,
}) {
  return showModalBottomSheet<WalletGateAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _WalletGateSheet(
      wallet: wallet,
      fallbackMessage: fallbackMessage,
    ),
  );
}

class _WalletGateSheet extends StatefulWidget {
  const _WalletGateSheet({
    required this.wallet,
    this.fallbackMessage,
  });

  final Map<String, dynamic>? wallet;
  final String? fallbackMessage;

  @override
  State<_WalletGateSheet> createState() => _WalletGateSheetState();
}

class _WalletGateSheetState extends State<_WalletGateSheet> {
  WalletGateAction _selected = WalletGateAction.topUp;

  double get _minimum =>
      (widget.wallet?['minWalletBalanceForOrders'] as num?)?.toDouble() ?? 0;
  double get _balance =>
      (widget.wallet?['pocketBalance'] as num?)?.toDouble() ?? 0;
  double get _cashInHand =>
      (widget.wallet?['cashInHand'] as num?)?.toDouble() ?? 0;

  /// What they must add to clear the floor. Never negative: the sheet only
  /// opens below it, but a stale wallet read should not print a minus sign.
  double get _shortfall => (_minimum - _balance).clamp(0, double.infinity);

  /// Depositing collected COD restores the balance rupee for rupee, so it is
  /// only worth offering when they are actually carrying some.
  bool get _canDepositCash => _cashInHand > 0;

  String _money(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E4EA),
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                ),
                SizedBox(height: 18.h),
                if (_minimum > 0) ...[
                  Text(
                    '\u20b9${_money(_balance)}  Low wallet balance!',
                    style: TextStyle(
                      fontSize: 21.sp,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                      color: const Color(0xFF16211A),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Add \u20b9${_money(_shortfall)} more to reach the '
                    '\u20b9${_money(_minimum)} minimum and go Online.',
                    style: TextStyle(
                      fontSize: 13.sp,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF6B7A70),
                    ),
                  ),
                ] else
                  // No threshold in the payload means an older backend; repeat
                  // what it did say rather than inventing numbers.
                  Text(
                    widget.fallbackMessage ?? 'You cannot go online right now.',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF16211A),
                    ),
                  ),
                SizedBox(height: 18.h),
                _OptionTile(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Recharge Wallet',
                  subtitle: 'Add money with UPI, card or netbanking',
                  selected: _selected == WalletGateAction.topUp,
                  onTap: () => setState(() => _selected = WalletGateAction.topUp),
                ),
                if (_canDepositCash) ...[
                  SizedBox(height: 10.h),
                  _OptionTile(
                    icon: Icons.payments_rounded,
                    label: 'Deposit COD cash',
                    subtitle:
                        'Hand over the \u20b9${_money(_cashInHand)} you collected',
                    selected: _selected == WalletGateAction.depositCash,
                    onTap: () =>
                        setState(() => _selected = WalletGateAction.depositCash),
                  ),
                ],
                SizedBox(height: 20.h),
                SizedBox(
                  width: double.infinity,
                  height: 52.h,
                  child: ElevatedButton(
                    onPressed: () {
                      HapticService.light();
                      Navigator.of(context).pop(_selected);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                    ),
                    child: Text(
                      switch (_selected) {
                        WalletGateAction.depositCash => 'Deposit Now',
                        WalletGateAction.topUp => 'Recharge Now',
                      },
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Not now',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    'Orders you have already accepted are not affected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A selectable top-up route, radio on the right like the reference design.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticService.selection();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
        decoration: BoxDecoration(
          // Tinted rather than filled when selected: a solid purple row would
          // fight the Recharge button for attention.
          color:
              selected ? AppColors.primary.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFE2E4EA),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22.sp,
              color: selected ? AppColors.primaryDark : Colors.grey[600],
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF16211A),
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 22.sp,
              color: selected ? AppColors.primary : const Color(0xFFC7CBD4),
            ),
          ],
        ),
      ),
    );
  }
}
