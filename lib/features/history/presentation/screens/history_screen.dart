import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/result.dart';
import '../../../../core/services/sound_service.dart';
import '../../../main/presentation/screens/main_screen.dart';
import '../../../wallet/data/wallet_repository.dart';

const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _statusOptions = ['ALL TRIPS', 'Completed', 'Pending', 'Cancelled'];

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  int _selectedTabIndex = 0;
  DateTime _selectedDate = DateTime.now();
  String _statusFilter = 'ALL TRIPS';

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _trips = const [];

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  String get _period => switch (_selectedTabIndex) {
    1 => 'weekly',
    2 => 'monthly',
    _ => 'daily',
  };

  String _dateParam(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateLabel() {
    final formatted = '${_monthAbbr[_selectedDate.month - 1]} ${_selectedDate.day}';
    if (_selectedTabIndex == 2) {
      return '${_monthAbbr[_selectedDate.month - 1]} ${_selectedDate.year}';
    }
    return _isSameDay(_selectedDate, DateTime.now()) ? 'Today: $formatted' : formatted;
  }

  num _tripEarning(Map<String, dynamic> t) =>
      (t['deliveryEarning'] ?? t['earningAmount'] ?? t['amount'] ?? 0) as num;

  num _tripTotal(Map<String, dynamic> t) =>
      (t['totalAmount'] ?? t['orderTotal'] ?? 0) as num;

  String _tripRestaurant(Map<String, dynamic> t) =>
      (t['restaurantName'] ?? t['restaurant'] ?? 'Restaurant').toString();

  String _tripStatus(Map<String, dynamic> t) => (t['status'] ?? '').toString();

  String _tripOrderId(Map<String, dynamic> t) =>
      (t['orderId'] ?? t['id'] ?? t['_id'] ?? '').toString();

  /// Trip time, formatted in the DEVICE's timezone.
  ///
  /// Prefers the raw `date` timestamp over the server's pre-formatted `time`
  /// string. The server formatted that string with no timezone, so running in UTC
  /// it rendered every trip 5h30m early; and even once fixed, a time formatted
  /// server-side can only ever be right for one timezone. Formatting the ISO value
  /// here is correct wherever the rider is, and stops this screen depending on a
  /// backend build.
  String _tripTime(Map<String, dynamic> t) {
    final iso = (t['date'] ?? t['deliveredAt'] ?? t['createdAt'])?.toString();
    final dt = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (dt != null) {
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      return '${hour.toString().padLeft(2, '0')}:$minute ${dt.hour >= 12 ? 'PM' : 'AM'}';
    }
    // Older payloads with no usable timestamp still have the server's string.
    return (t['time'] ?? '').toString();
  }

  Future<void> _loadTrips() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = ref.read(walletRepositoryProvider);
    final result = await repo.getTripHistory(
      period: _period,
      date: _dateParam(_selectedDate),
      status: _statusFilter == 'ALL TRIPS' ? null : _statusFilter,
      limit: 200,
    );
    if (!mounted) return;
    result.when(
      success: (data) {
        final trips = (data['trips'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        setState(() {
          _trips = trips;
          _loading = false;
        });
      },
      failure: (e) => setState(() {
        _error = e.message;
        _loading = false;
      }),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    _loadTrips();
  }

  Future<void> _pickStatus() async {
    final theme = Theme.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 12.h),
            for (final option in _statusOptions)
              ListTile(
                title: Text(
                  option == 'ALL TRIPS' ? 'All' : option,
                  style: TextStyle(
                    fontWeight: option == _statusFilter
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                trailing: option == _statusFilter
                    ? Icon(Icons.check, color: theme.primaryColor)
                    : null,
                onTap: () => Navigator.of(context).pop(option),
              ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
    if (picked == null || picked == _statusFilter) return;
    setState(() => _statusFilter = picked);
    _loadTrips();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final totalEarnings = _trips.fold<num>(0, (sum, t) => sum + _tripEarning(t));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: theme.appBarTheme.iconTheme?.color,
          ),
          onPressed: () => ref.read(mainTabIndexProvider.notifier).setIndex(0),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TRIP HISTORY',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp),
            ),
            Text(
              'YOUR MILESTONES',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10.sp,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          Container(
            margin: EdgeInsets.only(right: 16.w),
            padding: EdgeInsets.all(8.r),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
            ),
            child: Icon(
              Icons.card_giftcard,
              color: theme.primaryColor,
              size: 20.sp,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Custom Tab Bar
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
            child: Row(
              children: [
                _buildTab('DAILY', 0, isDarkMode),
                _buildTab('WEEKLY', 1, isDarkMode),
                _buildTab('MONTHLY', 2, isDarkMode),
              ],
            ),
          ),

          // Filters
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildFilterDropdown(
                    icon: Icons.calendar_today_outlined,
                    label: _dateLabel(),
                    isDarkMode: isDarkMode,
                    onTap: _pickDate,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  flex: 2,
                  child: _buildFilterDropdown(
                    icon: Icons.filter_alt_outlined,
                    label: _statusFilter == 'ALL TRIPS' ? 'All' : _statusFilter,
                    isDarkMode: isDarkMode,
                    onTap: _pickStatus,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20.h),

          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                SoundService.playRefresh();
                await _loadTrips();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(left: 20.w, right: 20.w, bottom: 120.h),
                child: Column(
                  children: [
                    // Earnings Summary Card
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: 24.h),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(24.r),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'EARNINGS',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.sp,
                              color: theme.primaryColor,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 12.h),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '₹',
                                style: TextStyle(
                                  fontSize: 24.sp,
                                  fontWeight: FontWeight.w900,
                                  color: isDarkMode
                                      ? Colors.white
                                      : const Color(0xFF101828),
                                ),
                              ),
                              Text(
                                totalEarnings.toStringAsFixed(0),
                                style: TextStyle(
                                  fontSize: 40.sp,
                                  fontWeight: FontWeight.w900,
                                  color: isDarkMode
                                      ? Colors.white
                                      : const Color(0xFF101828),
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16.h),

                    if (_loading)
                      Padding(
                        padding: EdgeInsets.only(top: 60.h),
                        child: const Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      _buildErrorCard(theme, isDarkMode)
                    else if (_trips.isEmpty)
                      _buildEmptyState(theme, isDarkMode)
                    else
                      ..._trips.map((t) => _buildTripCard(t, theme, isDarkMode)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme, bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 40.h, horizontal: 20.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: Colors.grey[400], size: 40.sp),
          SizedBox(height: 16.h),
          Text(
            _error ?? 'Something went wrong',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14.sp),
          ),
          SizedBox(height: 16.h),
          TextButton(onPressed: _loadTrips, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 60.h, horizontal: 20.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(20.r),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[850] : const Color(0xFFF8F9FA),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.access_time,
              color: Colors.grey[400],
              size: 40.sp,
            ),
          ),
          SizedBox(height: 24.h),
          Text(
            'No Trips Yet',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp),
          ),
          SizedBox(height: 8.h),
          Text(
            "You haven't made any deliveries in this period.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14.sp),
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip, ThemeData theme, bool isDarkMode) {
    final status = _tripStatus(trip);
    final statusColor = switch (status.toLowerCase()) {
      'completed' => const Color(0xFF1EBE5D),
      'cancelled' => Colors.redAccent,
      _ => Colors.orange,
    };
    final statusIcon = switch (status.toLowerCase()) {
      'completed' => Icons.check_circle_rounded,
      'cancelled' => Icons.cancel_rounded,
      _ => Icons.schedule_rounded,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/trip-details', extra: trip),
        borderRadius: BorderRadius.circular(20.r),
        child: Container(
          margin: EdgeInsets.only(bottom: 12.h),
          padding: EdgeInsets.all(16.r),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                margin: EdgeInsets.only(top: 2.h),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(statusIcon, color: statusColor, size: 20.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _tripRestaurant(trip),
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.sp),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Text(
                            status.isEmpty ? '—' : status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.sp,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        if (_tripOrderId(trip).isNotEmpty)
                          Flexible(
                            child: Text(
                              '#${_tripOrderId(trip)}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey, fontSize: 12.sp),
                            ),
                          ),
                        if (_tripOrderId(trip).isNotEmpty && _tripTime(trip).isNotEmpty)
                          Text('  ·  ', style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
                        if (_tripTime(trip).isNotEmpty)
                          Text(
                            _tripTime(trip),
                            style: TextStyle(color: Colors.grey, fontSize: 12.sp),
                          ),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Order ₹${_tripTotal(trip).toStringAsFixed(0)}',
                          style: TextStyle(color: Colors.grey, fontSize: 13.sp),
                        ),
                        Text(
                          '+₹${_tripEarning(trip).toStringAsFixed(0)}',
                          style: TextStyle(
                            color: const Color(0xFF1EBE5D),
                            fontWeight: FontWeight.w900,
                            fontSize: 15.sp,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 4.w),
              Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 20.sp),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index, bool isDarkMode) {
    bool isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_selectedTabIndex == index) return;
          setState(() {
            _selectedTabIndex = index;
          });
          _loadTrips();
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12.h),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDarkMode ? Colors.grey[800] : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(30.r),
            border: Border.all(
              color: isSelected ? Colors.transparent : Colors.transparent,
            ),
            boxShadow: isSelected && !isDarkMode
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.sp,
                color: isSelected
                    ? (isDarkMode ? Colors.white : Colors.black)
                    : Colors.grey,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required IconData icon,
    required String label,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey, size: 18.sp),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 20.sp),
          ],
        ),
      ),
    );
  }
}
