import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:sohr_delivery_partner/core/services/haptic_service.dart';
import 'package:sohr_delivery_partner/core/theme/app_colors.dart';
import 'package:sohr_delivery_partner/features/orders/data/models/delivery_order.dart';
import 'package:sohr_delivery_partner/features/orders/presentation/widgets/product_line_tile.dart';

/// Shows the order's products.
///
/// At the store (`checklist: true`) each line can be ticked off as it is
/// handed over, and the confirm button stays disabled until every line is
/// ticked. Everywhere else it is a plain read-only list.
///
/// Returns `true` only when the rider confirms a fully-ticked checklist —
/// the caller is what actually calls `confirm-pickup`.
Future<bool?> showOrderProductsSheet(
  BuildContext context, {
  required DeliveryOrder order,
  bool checklist = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OrderProductsSheet(order: order, checklist: checklist),
  );
}

class _OrderProductsSheet extends StatefulWidget {
  const _OrderProductsSheet({required this.order, required this.checklist});

  final DeliveryOrder order;
  final bool checklist;

  @override
  State<_OrderProductsSheet> createState() => _OrderProductsSheetState();
}

class _OrderProductsSheetState extends State<_OrderProductsSheet> {
  /// Ticked line indices. Local only — see [ProductLineTile] for why this is
  /// never sent to the backend.
  final Set<int> _picked = {};

  bool get _allPicked => _picked.length == widget.order.items.length;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final order = widget.order;
    final items = order.items;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
        ),
        child: Column(
          children: [
            SizedBox(height: 10.h),
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.checklist ? 'Collect from store' : 'Products',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w900,
                            color: c.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          '${order.itemsSummary} · ${order.store.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.checklist)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.w,
                        vertical: 5.h,
                      ),
                      decoration: BoxDecoration(
                        color: _allPicked
                            ? AppColors.successBg
                            : AppColors.pendingBg,
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Text(
                        '${_picked.length}/${items.length}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w900,
                          color: _allPicked
                              ? AppColors.successText
                              : AppColors.pendingText,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            Expanded(
              child: items.isEmpty
                  ? _EmptyProducts(color: c.textSecondary)
                  : ListView.separated(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: c.border),
                      itemBuilder: (_, i) => ProductLineTile(
                        item: items[i],
                        checked: widget.checklist ? _picked.contains(i) : null,
                        onToggleChecked: widget.checklist
                            ? () {
                                HapticService.light();
                                setState(() {
                                  _picked.contains(i)
                                      ? _picked.remove(i)
                                      : _picked.add(i);
                                });
                              }
                            : null,
                      ),
                    ),
            ),
            _Footer(
              order: order,
              checklist: widget.checklist,
              allPicked: _allPicked,
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.order,
    required this.checklist,
    required this.allPicked,
  });

  final DeliveryOrder order;
  final bool checklist;
  final bool allPicked;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 20.h),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Order total',
                  style: TextStyle(fontSize: 13.sp, color: c.textSecondary),
                ),
                const Spacer(),
                Text(
                  '₹${order.total.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w900,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4.h),
            Row(
              children: [
                Text(
                  order.isPaid ? 'Already paid' : 'Collect on delivery',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: order.isPaid
                        ? AppColors.successText
                        : AppColors.pendingText,
                  ),
                ),
                const Spacer(),
                Text(
                  'You earn ₹${order.riderEarning.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 12.sp, color: c.textSecondary),
                ),
              ],
            ),
            if (checklist) ...[
              SizedBox(height: 14.h),
              ElevatedButton(
                onPressed: allPicked
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: Text(
                  allPicked ? 'Confirm pickup' : 'Tick every product to confirm',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 40.sp, color: color),
          SizedBox(height: 12.h),
          Text(
            'No products on this order',
            style: TextStyle(fontSize: 13.sp, color: color),
          ),
        ],
      ),
    );
  }
}
