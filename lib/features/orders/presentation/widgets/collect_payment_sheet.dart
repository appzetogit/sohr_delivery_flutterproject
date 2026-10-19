import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:sohr_delivery_partner/core/constants/app_constants.dart';
import 'package:sohr_delivery_partner/core/error/result.dart';
import 'package:sohr_delivery_partner/core/presentation/celebration/confetti.dart';
import 'package:sohr_delivery_partner/core/services/haptic_service.dart';
import 'package:sohr_delivery_partner/features/auth/application/auth_controller.dart';
import 'package:sohr_delivery_partner/features/auth/application/auth_state.dart';
import 'package:sohr_delivery_partner/features/orders/data/models/delivery_order.dart';
import 'package:sohr_delivery_partner/features/orders/data/orders_repository.dart';

class CollectPaymentSheet extends ConsumerStatefulWidget {
  const CollectPaymentSheet({super.key, required this.order});

  final DeliveryOrder order;

  @override
  ConsumerState<CollectPaymentSheet> createState() => _CollectPaymentSheetState();
}

class _CollectPaymentSheetState extends ConsumerState<CollectPaymentSheet>
    with SingleTickerProviderStateMixin {
  bool _collecting = false;
  bool _showQr = false;
  bool _completed = false;
  String? _error;

  late final AnimationController _confettiController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  late final List<ConfettiParticle> _particles = ConfettiParticle.burst(
    count: 80,
    seed: widget.order.id.hashCode,
  );

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  /// Both "Collect Cash Instead" and "Payment Received" (after showing the
  /// driver's own QR) hit the same cash-collection API — the backend marks a
  /// cash order paid automatically once delivery completes, regardless of how
  /// the money was physically handed over, so there's no separate "QR paid"
  /// endpoint to call here.
  Future<void> _confirmCollected() async {
    setState(() {
      _collecting = true;
      _error = null;
    });
    final result = await ref.read(ordersRepositoryProvider).collectCash(widget.order.id);
    if (!mounted) return;
    await result.when(
      success: (_) async {
        setState(() => _completed = true);
        HapticService.success();
        _confettiController.forward(from: 0);
        await Future.delayed(const Duration(milliseconds: 2000));
        if (mounted) Navigator.of(context).pop(true);
      },
      failure: (error) async => setState(() {
        _error = error.message;
        _collecting = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1E1E1E);
    final subTextColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];
    final order = widget.order;
    final authState = ref.watch(authControllerProvider);
    final upiQrCode = authState is AuthAuthenticated ? authState.user.upiQrCode : null;

    return SafeArea(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            margin: EdgeInsets.all(12.w),
            padding: EdgeInsets.all(20.r),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(28.r),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Collect Payment',
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w900, color: textColor),
                    ),
                    Text(
                      '₹${order.total.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w900, color: theme.primaryColor),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),
                if (_completed)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.h),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _confettiController,
                          builder: (context, child) {
                            final scale = 0.8 + 0.25 * CurvedAnimation(
                              parent: _confettiController,
                              curve: const Interval(0.0, 0.4, curve: Curves.elasticOut),
                            ).value;
                            return Transform.scale(
                              scale: scale,
                              child: child,
                            );
                          },
                          child: Container(
                            height: 64.r,
                            width: 64.r,
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withValues(alpha: 0.3),
                                  blurRadius: 16.r,
                                  spreadRadius: 2.r,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: Colors.green,
                              size: 48.sp,
                            ),
                          ),
                        ),
                        SizedBox(height: 14.h),
                        Text(
                          'Delivery Completed',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp, color: textColor),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          '₹${order.total.toStringAsFixed(0)} collected successfully 🎉',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp, color: Colors.green),
                        ),
                      ],
                    ),
                  )
                else ...[
                  if (_showQr) ...[
                    if (upiQrCode != null && upiQrCode.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16.r),
                        child: Image.network(
                          AppConstants.resolveMediaUrl(upiQrCode),
                          width: 200.w,
                          height: 200.w,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(Icons.broken_image, size: 50.sp, color: Colors.grey),
                        ),
                      )
                    else
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        child: Text(
                          'No UPI QR code uploaded on your profile yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.sp, color: subTextColor),
                        ),
                      ),
                    SizedBox(height: 12.h),
                    Text(
                      'Ask the customer to scan this QR to pay',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.sp, color: subTextColor),
                    ),
                    SizedBox(height: 16.h),
                    ElevatedButton.icon(
                      onPressed: _collecting ? null : _confirmCollected,
                      icon: _collecting
                          ? SizedBox(
                              width: 16.w,
                              height: 16.w,
                              child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Payment Received'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 48.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                      ),
                    ),
                  ] else
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _showQr = true),
                      icon: const Icon(Icons.qr_code_rounded),
                      label: const Text('Show QR to Customer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 48.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                      ),
                    ),
                  if (_error != null) ...[
                    SizedBox(height: 8.h),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ],
                  SizedBox(height: 12.h),
                  OutlinedButton.icon(
                    onPressed: _collecting ? null : _confirmCollected,
                    icon: _collecting
                        ? SizedBox(
                            width: 16.w,
                            height: 16.w,
                            child: CircularProgressIndicator(strokeWidth: 2, color: theme.primaryColor),
                          )
                        : const Icon(Icons.money_rounded),
                    label: const Text('Collect Cash Instead'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(double.infinity, 48.h),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_completed)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _confettiController,
                  builder: (context, _) => CustomPaint(
                    painter: ConfettiPainter(
                      particles: _particles,
                      progress: _confettiController.value,
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
