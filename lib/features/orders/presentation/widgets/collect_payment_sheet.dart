import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:sohr_delivery_partner/core/error/result.dart';
import 'package:sohr_delivery_partner/core/presentation/celebration/confetti.dart';
import 'package:sohr_delivery_partner/core/services/haptic_service.dart';
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
  bool _loadingQr = false;
  bool _completed = false;
  Uint8List? _qrImage;
  Timer? _paymentPoll;
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
    _paymentPoll?.cancel();
    _confettiController.dispose();
    super.dispose();
  }

  /// Shows the admin's Cashfree QR for this order. The money goes to the admin's
  /// account, and only the server can say it arrived, so the sheet watches
  /// payment-status instead of asking the rider to confirm.
  Future<void> _showAdminQr() async {
    setState(() {
      _loadingQr = true;
      _error = null;
    });
    final result = await ref.read(ordersRepositoryProvider).collectQr(widget.order.id);
    if (!mounted) return;
    await result.when(
      success: (data) async {
        final image = _decodeQrImage(data['imageUrl'] as String?);
        setState(() {
          _loadingQr = false;
          _qrImage = image;
          if (image == null) _error = 'Could not show the QR. Try again or collect cash.';
        });
        if (image != null) _startPaymentPoll();
      },
      failure: (error) async => setState(() {
        _loadingQr = false;
        _error = error.message;
      }),
    );
  }

  /// The image arrives as a `data:image/png;base64,...` string.
  Uint8List? _decodeQrImage(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    try {
      return base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
    } on FormatException {
      return null;
    }
  }

  void _startPaymentPoll() {
    _paymentPoll?.cancel();
    _paymentPoll = Timer.periodic(const Duration(seconds: 4), (_) => _checkPayment());
  }

  Future<void> _checkPayment() async {
    final result = await ref.read(ordersRepositoryProvider).paymentStatus(widget.order.id);
    if (!mounted || _completed) return;
    await result.when(
      success: (data) async {
        final payment = data['payment'];
        final status = payment is Map ? payment['status'] : null;
        if (status == 'paid') {
          await _finish();
        } else if (status == 'failed') {
          // The QR expired or was closed. Stop waiting on it; the rider can make a new one.
          _paymentPoll?.cancel();
          setState(() {
            _qrImage = null;
            _error = 'This QR expired. Show a new one or collect cash.';
          });
        }
      },
      // A dropped connection shouldn't end the wait; the next tick retries.
      failure: (_) async {},
    );
  }

  /// Switches the order to cash. The server closes any open QR first, and refuses
  /// if the customer has already paid it, so nobody pays twice.
  Future<void> _collectCash() async {
    _paymentPoll?.cancel();
    setState(() {
      _collecting = true;
      _error = null;
    });
    final result = await ref.read(ordersRepositoryProvider).collectCash(widget.order.id);
    if (!mounted) return;
    await result.when(
      success: (_) => _finish(),
      failure: (error) async {
        setState(() {
          _error = error.message;
          _collecting = false;
        });
        if (_qrImage != null) _startPaymentPoll();
      },
    );
  }

  Future<void> _finish() async {
    _paymentPoll?.cancel();
    setState(() => _completed = true);
    HapticService.success();
    _confettiController.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 2000));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1E1E1E);
    final subTextColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];
    final order = widget.order;

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
                  if (_qrImage != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16.r),
                      child: Container(
                        color: Colors.white,
                        padding: EdgeInsets.all(8.r),
                        child: Image.memory(
                          _qrImage!,
                          width: 220.w,
                          height: 220.w,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      'Ask the customer to scan this QR with any UPI app',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.sp, color: subTextColor),
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 14.w,
                          height: 14.w,
                          child: CircularProgressIndicator(strokeWidth: 2, color: theme.primaryColor),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'Waiting for payment…',
                          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: textColor),
                        ),
                      ],
                    ),
                  ] else
                    ElevatedButton.icon(
                      onPressed: _loadingQr || _collecting ? null : _showAdminQr,
                      icon: _loadingQr
                          ? SizedBox(
                              width: 16.w,
                              height: 16.w,
                              child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.qr_code_rounded),
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
                    onPressed: _collecting ? null : _collectCash,
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
