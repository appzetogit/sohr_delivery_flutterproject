import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/delivery_order.dart';

class IncomingOrderBottomSheet extends StatelessWidget {
  final DeliveryOrder order;
  final int secondsLeft;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  
  const IncomingOrderBottomSheet({
    Key? key,
    required this.order,
    required this.secondsLeft,
    required this.onAccept,
    required this.onReject,
  }) : super(key: key);

  Future<void> _dial(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Determine if we are in dark mode (use platform brightness if theme is default)
    final isDark = theme.brightness == Brightness.dark || MediaQuery.of(context).platformBrightness == Brightness.dark;
    
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final borderColor = isDark ? Colors.white12 : Colors.black12;
    final boxBgColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 32.h),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24.r),
          topRight: Radius.circular(24.r),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40.w,
            height: 4.h,
            margin: EdgeInsets.only(bottom: 16.h),
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(4.r),
            ),
          ),

          // Header row
          Row(
            children: [
              Text(
                '#${order.id.toUpperCase().substring(0, order.id.length > 8 ? 8 : order.id.length)}',
                style: TextStyle(
                  color: subTextColor,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Countdown timer
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 44.w,
                    height: 44.w,
                    child: CircularProgressIndicator(
                      value: secondsLeft / 45.0,
                      color: const Color(0xFF9E6512),
                      backgroundColor: borderColor,
                      strokeWidth: 3,
                    ),
                  ),
                  Text(
                    '${secondsLeft}s',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          SizedBox(height: 16.h),
          
          // Rider earning. Deliberately the only amount on this card: the
          // order total and the cash to collect are the customer's side of the
          // trip and showed up here as "is that mine?".
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'YOUR EARNING',
              style: TextStyle(
                color: subTextColor,
                fontSize: 11.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '₹ ',
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  order.riderEarning.toStringAsFixed(2),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 40.sp,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),

          // The tip is the rider's, and it is already inside the total above —
          // spelling it out is the difference between "why is this one worth
          // more?" and knowing the customer tipped.
          if (order.deliveryTip > 0)
            Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                'includes ₹${order.deliveryTip.toStringAsFixed(0)} Delivery Tip',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: subTextColor,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

          SizedBox(height: 16.h),
          
          // Trip Info Boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoBox(
                icon: Icons.location_on,
                iconColor: const Color(0xFF2196F3),
                title: 'DISTANCE',
                value: order.tripDistanceKm != null && order.tripDistanceKm! > 0
                    ? '${order.tripDistanceKm!.toStringAsFixed(1)} km'
                    : '-- km',
                boxBgColor: boxBgColor,
                textColor: textColor,
                subTextColor: subTextColor,
              ),
              _buildInfoBox(
                icon: Icons.shopping_bag,
                iconColor: const Color(0xFFFFC107),
                title: 'TOTAL ITEMS',
                value: order.items.isNotEmpty ? '${order.items.length} Items' : '-- Items',
                boxBgColor: boxBgColor,
                textColor: textColor,
                subTextColor: subTextColor,
              ),
            ],
          ),
          
          SizedBox(height: 24.h),
          
          // Timeline
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: boxBgColor,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: borderColor),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 5.w, // center of the 12.w dot
                  top: 12.w, // start below the first dot
                  bottom: 24.h + 12.w, // end above the second dot (padding bottom is 24.h)
                  child: CustomPaint(
                    size: const Size(2, double.infinity),
                    painter: _DashedLinePainter(color: isDark ? Colors.white24 : Colors.black26),
                  ),
                ),
                Column(
                  children: [
                    _buildTimelineItem(
                      dotColor: const Color(0xFF9E6512),
                      title: order.isMartOrder
                          ? 'MART PICKUP'
                          : 'RESTAURANT PICKUP',
                      name: order.restaurant.name,
                      address: order.restaurant.address,
                      isFirst: true,
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    _buildTimelineItem(
                      dotColor: const Color(0xFF2196F3),
                      title: 'CUSTOMER DROP',
                      name: order.customerName.isNotEmpty ? order.customerName : 'Customer',
                      address: order.deliveryAddress.fullAddress.isNotEmpty ? order.deliveryAddress.fullAddress : 'Drop Location',
                      isFirst: false,
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          SizedBox(height: 24.h),
          
          // Actions
          _SlideToAcceptButton(onAccept: onAccept),
          
          SizedBox(height: 16.h),
          
          GestureDetector(
            onTap: onReject,
            child: Container(
              height: 56.h,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(32.r),
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Text(
                  'Reject Order',
                  style: TextStyle(
                    color: const Color(0xFFE53935),
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required Color boxBgColor,
    required Color textColor,
    required Color subTextColor,
  }) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 4.w),
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
        decoration: BoxDecoration(
          color: boxBgColor,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 20.sp),
            SizedBox(height: 8.h),
            Text(
              title,
              style: TextStyle(
                color: subTextColor,
                fontSize: 9.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              value,
              style: TextStyle(
                color: textColor,
                fontSize: 12.sp,
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem({
    required Color dotColor,
    required String title,
    required String name,
    required String address,
    required bool isFirst,
    required Color textColor,
    required Color subTextColor,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isFirst ? 24.h : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline graphics
          Container(
            width: 12.w,
            height: 12.w,
            margin: EdgeInsets.only(top: 2.h),
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 12.w),
          // Content
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: dotColor,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        name,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        address,
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 12.sp,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    var max = size.height;
    var dashWidth = 4.0;
    var dashSpace = 4.0;
    double startY = 4.0;

    while (startY < max) {
      canvas.drawLine(Offset(0, startY), Offset(0, startY + dashWidth), paint);
      startY += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _SlideToAcceptButton extends StatefulWidget {
  final VoidCallback onAccept;
  const _SlideToAcceptButton({required this.onAccept});

  @override
  State<_SlideToAcceptButton> createState() => _SlideToAcceptButtonState();
}

class _SlideToAcceptButtonState extends State<_SlideToAcceptButton> {
  double _dragValue = 0.0;
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final double height = 56.h;
    final double handleSize = 44.h;
    final double padding = 6.h;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxDrag = constraints.maxWidth - handleSize - (padding * 2);

        return Container(
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF9E6512),
            borderRadius: BorderRadius.circular(32.r),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Center(
                child: Text(
                  'SLIDE TO ACCEPT',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16.sp,
                  ),
                ),
              ),
              Positioned(
                left: padding + _dragValue,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (_accepted) return;
                    setState(() {
                      _dragValue += details.delta.dx;
                      if (_dragValue < 0) _dragValue = 0;
                      if (_dragValue > maxDrag) _dragValue = maxDrag;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_accepted) return;
                    if (_dragValue > maxDrag * 0.75) {
                      setState(() {
                        _dragValue = maxDrag;
                        _accepted = true;
                      });
                      widget.onAccept();
                    } else {
                      setState(() {
                        _dragValue = 0.0;
                      });
                    }
                  },
                  child: Container(
                    width: handleSize,
                    height: handleSize,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.keyboard_arrow_right_rounded,
                      color: Colors.black,
                      size: 28.sp,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
