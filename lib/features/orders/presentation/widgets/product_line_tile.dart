import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:sohr_delivery_partner/core/constants/app_constants.dart';
import 'package:sohr_delivery_partner/core/theme/app_colors.dart';
import 'package:sohr_delivery_partner/features/orders/data/models/delivery_order.dart';

/// One product line on a Quick Commerce order.
///
/// Shows everything the rider needs to match the line against what is
/// physically on the counter: photo, name, pack size / brand / variant,
/// add-ons, unit count and price.
///
/// [checked] and [onToggleChecked] turn it into a pickup checklist row. That
/// tick is a **rider-side aid only** — the backend has no per-item
/// verification endpoint (partial fulfilment is explicitly not implemented),
/// so it is never sent anywhere and never implies a server-side state.
class ProductLineTile extends StatelessWidget {
  const ProductLineTile({
    super.key,
    required this.item,
    this.checked,
    this.onToggleChecked,
    this.dense = false,
  });

  final OrderItem item;
  final bool? checked;
  final VoidCallback? onToggleChecked;

  /// Compact variant for read-only summaries (order detail, trip history).
  final bool dense;

  bool get _isChecklist => checked != null && onToggleChecked != null;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final imageUrl = AppConstants.resolveMediaUrl(item.image);
    final size = dense ? 44.r : 56.r;

    final tile = Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 8.h : 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isChecklist) ...[
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Icon(
                checked! ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 24.sp,
                color: checked! ? AppColors.success : c.border,
              ),
            ),
            SizedBox(width: 12.w),
          ],
          _Thumbnail(url: imageUrl, size: size, border: c.border),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 13.sp : 14.sp,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                    decoration: _isChecklist && checked!
                        ? TextDecoration.lineThrough
                        : null,
                    decorationColor: c.textSecondary,
                  ),
                ),
                if (item.subtitle.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 2.h),
                    child: Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.sp, color: c.textSecondary),
                    ),
                  ),
                for (final addon in item.addons)
                  Padding(
                    padding: EdgeInsets.only(top: 2.h),
                    child: Text(
                      '+ ${addon.name}',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: c.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (item.notes != null)
                  Padding(
                    padding: EdgeInsets.only(top: 4.h),
                    child: Text(
                      item.notes!,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.pendingText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Unit count is the loudest thing on the row: getting the count
              // wrong is the mistake that actually costs a redelivery.
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  '× ${item.quantity}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                '₹${item.lineTotal.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: dense ? 12.sp : 13.sp,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              if (item.hasDiscount)
                Text(
                  '₹${(item.compareAtPrice * item.quantity).toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: c.textSecondary,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: c.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    if (!_isChecklist) return tile;
    return InkWell(
      onTap: onToggleChecked,
      borderRadius: BorderRadius.circular(12.r),
      child: tile,
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.url,
    required this.size,
    required this.border,
  });

  final String url;
  final double size;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.inventory_2_outlined,
      size: size * 0.45,
      color: AppColors.offline,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.of(context).surfaceVariant,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: border),
        ),
        child: url.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
