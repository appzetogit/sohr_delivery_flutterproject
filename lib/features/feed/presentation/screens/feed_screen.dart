import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:sohr_delivery_partner/core/presentation/celebration/delivery_celebration.dart';
import 'package:sohr_delivery_partner/core/presentation/widgets/wallet_gate_sheet.dart';
import 'package:sohr_delivery_partner/core/error/result.dart';
import 'package:sohr_delivery_partner/features/notifications/data/notifications_repository.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sohr_delivery_partner/core/constants/map_styles.dart';
import 'package:sohr_delivery_partner/core/constants/app_constants.dart';
import 'package:sohr_delivery_partner/core/utils/map_launcher.dart';
import 'package:sohr_delivery_partner/core/utils/maps_debug.dart';
import 'package:sohr_delivery_partner/core/utils/polyline_decoder.dart';
import 'package:sohr_delivery_partner/core/services/device_readiness_service.dart';
import 'package:sohr_delivery_partner/core/services/location_service.dart';
import 'package:sohr_delivery_partner/features/profile/presentation/screens/delivery_readiness_screen.dart';
import 'package:sohr_delivery_partner/core/services/haptic_service.dart';
import 'package:sohr_delivery_partner/core/presentation/widgets/bell_shake.dart';
import 'package:sohr_delivery_partner/features/main/presentation/screens/main_screen.dart';
import 'package:sohr_delivery_partner/core/services/sound_service.dart';
import 'package:sohr_delivery_partner/features/auth/application/auth_controller.dart';
import 'package:sohr_delivery_partner/features/auth/application/auth_state.dart';
import 'package:sohr_delivery_partner/features/orders/application/orders_controller.dart';
import 'package:sohr_delivery_partner/features/orders/application/orders_state.dart';
import 'package:sohr_delivery_partner/features/orders/data/models/delivery_order.dart';
import 'package:sohr_delivery_partner/features/orders/data/orders_repository.dart';
import 'package:sohr_delivery_partner/features/orders/presentation/widgets/collect_payment_sheet.dart';
import 'package:sohr_delivery_partner/features/orders/application/active_trip_visibility_controller.dart';
import 'package:sohr_delivery_partner/features/profile/application/availability_controller.dart';
import 'package:sohr_delivery_partner/features/support/data/support_repository.dart';
import 'package:sohr_delivery_partner/features/wallet/data/wallet_repository.dart';
import 'package:sohr_delivery_partner/core/services/fcm_service.dart';
import 'package:sohr_delivery_partner/features/incentives/application/incentives_controller.dart';
import 'package:sohr_delivery_partner/features/incentives/presentation/widgets/incentive_celebration.dart';
import 'package:sohr_delivery_partner/features/refer_earn/application/referral_controller.dart';
import 'package:sohr_delivery_partner/features/chat/presentation/screens/chat_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _isCurrentOrderVisible = true;
  bool _showReferEarn = true;
  bool _isActionLoading = false;

  Map<String, dynamic>? _earningsSummary;
  bool _earningsLoading = true;

  /// Wallet, read only for the new-order gate (`canReceiveOrders`).
  Map<String, dynamic>? _wallet;

  static const Color _onlineGreen = Color(0xFF1EBE5D);

  BitmapDescriptor? _bikeMarkerIcon;
  GoogleMapController? _mapController;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSub;

  List<LatLng> _routePoints = [];
  LatLng? _routeDestination;
  String? _routeKey;
  Timer? _pulseTimer;
  double _pulsePhase = 0.0;
  int _unreadNotificationCount = 0;

  /// Bumped every time an order offer lands, to ring the header bell. See
  /// [BellShake] for why this is a counter and not a flag.
  int _bellShakeTrigger = 0;

  @override
  void initState() {
    super.initState();

    _loadEarnings();
    _loadMarkerIcon();
    _initMapPosition();
    _loadUnreadCount();
    _listenForFcmNotifications();
    _positionSub = ref.read(locationServiceProvider).positionStream.listen((pos) {
      if (mounted) setState(() => _currentPosition = pos);
    });
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      // The pulse ring only exists on the online map. Ticking while offline
      // rebuilt the whole screen ten times a second for something nobody can
      // see — and kept re-evaluating the static map preview with it.
      if (!ref.read(availabilityControllerProvider)) return;
      setState(() => _pulsePhase = (_pulsePhase + 0.05) % 1.0);
    });
  }

  /// Offered when going online with something outstanding that will cost the
  /// rider orders.
  ///
  /// Self-limiting rather than gated on a "seen" flag: the checks report their
  /// real state, so once they are fixed this stops appearing on its own. Autostart
  /// is excluded from the blocking set precisely because no ROM lets us read it
  /// back — including it would make this prompt permanent and train riders to
  /// dismiss it without reading.
  Future<void> _promptDeviceReadiness() async {
    if (!Platform.isAndroid) return;
    if (!await DeviceReadinessService.hasBlockingIssues()) return;
    if (!mounted) return;

    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('You may miss orders'),
        content: const Text(
          'Your phone is set to stop this app running in the background. '
          'Orders can stop reaching you without any warning.\n\n'
          'It takes about a minute to fix.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Fix now'),
          ),
        ],
      ),
    );

    if (open == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DeliveryReadinessScreen()),
      );
    }
  }

  Future<void> _loadUnreadCount() async {
    final result = await ref.read(notificationsRepositoryProvider).getInbox(limit: 1);
    if (!mounted) return;
    result.when(
      success: (data) => setState(() {
        _unreadNotificationCount = (data['unreadCount'] as num?)?.toInt() ?? 0;
      }),
      failure: (_) {},
    );
  }

  /// Rings the header bell. Safe to call repeatedly — each call restarts the
  /// swing rather than queueing another one.
  void _ringBell() {
    if (!mounted) return;
    setState(() => _bellShakeTrigger++);
  }

  void _listenForFcmNotifications() {
    final fcmService = ref.read(fcmServiceProvider);
    fcmService.onNotificationReceived.listen((data) {
      _loadUnreadCount();
      if (data['type'] == 'new_order') _ringBell();
      if (data['type'] == 'referral_bonus') {
        _showReferralBonusCelebration(data['amount']?.toString() ?? '');
        ref.read(referralControllerProvider.notifier).refreshStats();
        _loadEarnings(); // Refresh wallet/earnings
      }
      // Fired by the backend the moment a rider clears an incentive target.
      // `incentive_unlocked` still needs an admin to release the money;
      // `incentive_credited` is already in the wallet.
      final type = data['type'];
      if (type == 'incentive_unlocked' || type == 'incentive_credited') {
        _showIncentiveCelebration(
          data['amount']?.toString() ?? '',
          pending: type == 'incentive_unlocked',
        );
        ref.read(incentivesControllerProvider.notifier).refresh();
        _loadEarnings();
      }
    });
  }

  void _showIncentiveCelebration(String amount, {required bool pending}) {
    if (!mounted) return;
    SoundService.playEffect('refferticketcomeout.mp3');
    showIncentiveCelebration(
      context,
      amount: amount,
      pending: pending,
      seed: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _showReferralBonusCelebration(String amount) {
    if (!mounted) return;
    
    // Play sound and haptic
    SoundService.playEffect('refferticketcomeout.mp3');
    HapticService.heavy();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        title: Column(
          children: [
            Icon(Icons.celebration, color: Colors.amber, size: 48.sp),
            SizedBox(height: 12.h),
            Text(
              'Referral Bonus!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24.sp),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: Text(
          'You just earned ₹$amount for a successful referral!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16.sp, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Awesome!', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  Future<void> _loadMarkerIcon() async {
    try {
      final Uint8List markerIcon = await _getBytesFromAsset('assets/image/bike.webp', 80);
      _bikeMarkerIcon = BitmapDescriptor.fromBytes(markerIcon);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Failed to load map marker: $e');
    }
  }

  /// Seeds the map preview with a fix even when the rider is offline (and
  /// therefore [LocationService.startTracking] hasn't run yet), so the
  /// preview never gets stuck on the placeholder icon.
  Future<void> _initMapPosition() async {
    final locationService = ref.read(locationServiceProvider);
    if (locationService.lastPosition != null) {
      if (mounted) setState(() => _currentPosition = locationService.lastPosition);
      return;
    }
    if (locationService.isTracking) return;

    final permission = await Geolocator.checkPermission();
    final isGranted = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
    if (!isGranted || !mounted) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      locationService.lastPosition = pos;
      if (mounted) setState(() => _currentPosition = pos);
    } catch (_) {
      // No fix available yet — the placeholder stays until tracking starts.
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _pulseTimer?.cancel();
    super.dispose();
  }

  void _maybeFetchRoute(DeliveryOrder order) {
    final navigateToRestaurant = order.currentPhase == 'en_route_to_pickup' ||
        order.currentPhase == 'at_pickup';
    final target = navigateToRestaurant ? 'restaurant' : 'customer';
    final key = '${order.id}::$target';
    if (key == _routeKey) return;
    _routeKey = key;
    // One-shot per leg (assigned → picked up), not on a clock — the marker
    // itself already moves for free off GPS/socket, and turn-by-turn now
    // routes out to native Google Maps via the "Map" button instead of
    // relying on this line staying fresh.
    _fetchRoute(order, target);
  }

  Future<void> _fetchRoute(DeliveryOrder order, String target) async {
    final pos = ref.read(locationServiceProvider).lastPosition;
    if (pos == null) return;
    mapsDebug('ROUTE REQUEST', 'feed order=${order.id} target=$target');
    final result = await ref.read(ordersRepositoryProvider).getRoute(
          order.id,
          lat: pos.latitude,
          lng: pos.longitude,
          target: target,
        );
    if (!mounted) return;
    result.when(
      success: (data) {
        final encoded = data['polyline'] as String?;
        final points = (encoded != null && encoded.isNotEmpty)
            ? decodePolyline(encoded)
            : <LatLng>[];
        final destLoc = target == 'restaurant'
            ? order.restaurant.location
            : order.deliveryAddress.location;
        final destination = destLoc != null
            ? LatLng(destLoc.lat, destLoc.lng)
            : (points.isNotEmpty ? points.last : null);
        setState(() {
          _routePoints = points;
          _routeDestination = destination;
        });
        if (destination != null && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(
              _boundsFor(LatLng(pos.latitude, pos.longitude), destination),
              80,
            ),
          );
        }
      },
      failure: (_) {},
    );
  }

  LatLngBounds _boundsFor(LatLng a, LatLng b) {
    return LatLngBounds(
      southwest: LatLng(
        a.latitude < b.latitude ? a.latitude : b.latitude,
        a.longitude < b.longitude ? a.longitude : b.longitude,
      ),
      northeast: LatLng(
        a.latitude > b.latitude ? a.latitude : b.latitude,
        a.longitude > b.longitude ? a.longitude : b.longitude,
      ),
    );
  }

  void _clearRoute() {
    _routeKey = null;
    if (_routePoints.isNotEmpty || _routeDestination != null) {
      setState(() {
        _routePoints = [];
        _routeDestination = null;
      });
    }
  }

  Future<void> _loadEarnings() async {
    final result = await ref.read(walletRepositoryProvider).getEarnings(period: 'today');
    if (!mounted) return;
    result.when(
      success: (data) => setState(() {
        _earningsSummary = data['summary'] as Map<String, dynamic>?;
        _earningsLoading = false;
      }),
      failure: (_) => setState(() => _earningsLoading = false),
    );
  }

  /// Fetched only when a go-online attempt is refused, to fill in
  /// [showWalletGateSheet] with the live balance, the admin's threshold and
  /// any COD cash the rider could deposit instead of topping up.
  Future<void> _loadWallet() async {
    final result = await ref.read(walletRepositoryProvider).getWallet();
    if (!mounted) return;
    result.when(
      success: (data) => setState(
        () => _wallet = data['wallet'] as Map<String, dynamic>? ?? data,
      ),
      failure: (_) {},
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runAction(Future<Result<DeliveryOrder, AppError>> Function() call) async {
    if (_isActionLoading) return;
    setState(() => _isActionLoading = true);
    final result = await call();
    if (mounted) setState(() => _isActionLoading = false);
    result.when(success: (_) {}, failure: (error) => _showSnack(error.message));
  }

  ({String label, IconData icon, Future<void> Function() action})? _actionFor(DeliveryOrder order) {
    final controller = ref.read(ordersControllerProvider.notifier);
    switch (order.currentPhase) {
      case 'en_route_to_pickup':
        return (
          label: 'Reached Pickup',
          icon: Icons.storefront_outlined,
          action: () => _runAction(() => controller.reachedPickup(order.id)),
        );
      case 'at_pickup':
        return (
          label: 'Confirm Pickup',
          icon: Icons.check_circle_outline,
          action: () => _runAction(() => controller.confirmPickup(order.id)),
        );
      case 'en_route_to_delivery':
        return (
          label: 'Reached Drop',
          icon: Icons.flag_outlined,
          action: () => _runAction(() => controller.reachedDrop(order.id)),
        );
      case 'at_drop':
        if (!order.isPaid) {
          return (
            label: 'Collect Payment',
            icon: Icons.payments_outlined,
            action: () => _showCollectPaymentSheet(order),
          );
        }
        return (
          label: 'Complete Delivery',
          icon: Icons.done_all_rounded,
          action: () => _completeDelivery(order),
        );
      default:
        return null;
    }
  }

  Future<void> _completeDelivery(DeliveryOrder order) async {
    if (_isActionLoading) return;
    setState(() => _isActionLoading = true);
    final result =
        await ref.read(ordersControllerProvider.notifier).completeOrder(order.id);
    if (mounted) setState(() => _isActionLoading = false);

    await result.when<Future<void>>(
      success: (_) async {
        if (!mounted) return;
        await showDeliveryCelebration(
          context,
          earning: order.riderEarning,
          vertical: order.vertical,
          seed: order.id.hashCode,
        );
      },
      failure: (error) async {
        _showSnack(error.message);
      },
    );
  }

  Future<void> _showCollectPaymentSheet(DeliveryOrder order) async {
    final collected = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CollectPaymentSheet(order: order),
    );
    if (collected == true) {
      await _completeDelivery(order);
    }
  }

  Future<void> _callCustomer(DeliveryOrder order) async {
    if (order.customerPhone.isEmpty) return;
    await _dial(order.customerPhone);
  }

  Future<void> _dial(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1E1E1E);
    final subTextColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    // Push is the fast path, but it is exactly what Chinese ROMs drop, and the
    // 15s poll is the fallback that still finds the offer. Ring on the list
    // growing too, so the bell is not silent on the devices that need it most.
    ref.listen(ordersControllerProvider, (was, now) {
      final before = was is OrdersLoaded ? was.availableOrders.length : 0;
      final after = now is OrdersLoaded ? now.availableOrders.length : 0;
      if (after > before) _ringBell();
    });

    final isOnline = ref.watch(availabilityControllerProvider);
    final ordersState = ref.watch(ordersControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final partnerName = authState is AuthAuthenticated ? authState.user.name : '';

    ref.listen<OrdersState>(ordersControllerProvider, (previous, next) {
      if (previous is OrdersLoaded && next is OrdersLoaded) {
        if (previous.hasActiveOrder && !next.hasActiveOrder) {
          // Order was completed or cancelled
          _loadEarnings();
          _clearRoute();
        } else if (previous.hasActiveOrder && next.hasActiveOrder &&
                   previous.currentOrder!.currentPhase != next.currentOrder!.currentPhase &&
                   next.currentOrder!.currentPhase == 'delivered') {
          // Order was delivered
          _loadEarnings();
        }
      }
      if (next is OrdersLoaded && next.hasActiveOrder) {
        _maybeFetchRoute(next.currentOrder!);
      } else if (next is OrdersLoaded) {
        _clearRoute();
      }
    });

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildMapPreview(isDarkMode, isOnline),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xE6161925) : Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32.r),
                  bottomRight: Radius.circular(32.r),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(textColor, subTextColor, partnerName),
                      SizedBox(height: 20.h),
                      _buildOnlineToggle(isOnline),
                      SizedBox(height: 16.h),
                      _buildEarningsAndOrdersRow(theme),

                      if (isOnline) ...[
                        if (_isCurrentOrderVisible && ordersState is OrdersLoaded && ordersState.hasActiveOrder) ...[
                          SizedBox(height: 24.h),
                          ..._buildOrdersSection(theme, isDarkMode, textColor, subTextColor, ordersState),
                        ]
                      ] else ...[
                        SizedBox(height: 24.h),
                        _buildOfflinePrompt(theme, isDarkMode, textColor, subTextColor),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_showReferEarn) _buildReferEarnFab(),
        ],
      ),
    );
  }

  List<Widget> _buildOrdersSection(
    ThemeData theme,
    bool isDarkMode,
    Color textColor,
    Color? subTextColor,
    OrdersState ordersState,
  ) {
    if (ordersState is OrdersLoading || ordersState is OrdersInitial) {
      return [
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24.h),
            child: CircularProgressIndicator(color: theme.primaryColor),
          ),
        ),
      ];
    }
    if (ordersState is OrdersError) {
      return [_buildOrdersErrorCard(theme, textColor, ordersState.message)];
    }
    if (ordersState is OrdersLoaded) {
      final order = ordersState.currentOrder;
      if (order != null) {
        return [
          _buildCurrentOrderHeader(textColor, order),
          SizedBox(height: 12.h),
          _buildCurrentOrderCard(theme, isDarkMode, textColor, subTextColor, order),
        ];
      }
      return const [];
    }
    return const [];
  }

  Widget _buildOrdersErrorCard(ThemeData theme, Color textColor, String message) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 28.sp),
          SizedBox(height: 10.h),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: textColor, fontSize: 13.sp)),
          SizedBox(height: 12.h),
          TextButton(
            onPressed: () => ref.read(ordersControllerProvider.notifier).refreshAll(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color textColor, Color? subTextColor, String partnerName) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning,' : (hour < 17 ? 'Good Afternoon,' : 'Good Evening,');
    final displayName = partnerName.isNotEmpty ? partnerName : 'Partner';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: TextStyle(fontSize: 13.sp, color: subTextColor),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Text('👋', style: TextStyle(fontSize: 18.sp)),
                ],
              ),
            ],
          ),
        ),
        _buildHeaderIcon(Icons.report_problem_outlined, _showEmergencyHelpBottomSheet),
        _buildHeaderIcon(Icons.assignment_ind_outlined, () => context.push('/driver-id-card')),
        _buildHeaderIcon(
          Icons.notifications_none_rounded,
          () => context.push('/notifications').then((_) => _loadUnreadCount()),
          _unreadNotificationCount,
          _bellShakeTrigger,
        ),
        // _buildHeaderIcon(Icons.headset_mic_outlined, () {
        //    // Do nothing for now or dial support if known
        // }
        // ),
      ],
    );
  }

  /// [shakeTrigger] is only passed for the bell; the other header icons have
  /// nothing to announce, so they are not wrapped at all.
  Widget _buildHeaderIcon(
    IconData icon,
    VoidCallback onTap, [
    int unreadCount = 0,
    int? shakeTrigger,
  ]) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(left: 8.w),
        width: 44.r,
        height: 44.r,
        decoration: BoxDecoration( 
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (shakeTrigger == null)
              Icon(icon, color: Colors.black, size: 22.sp)
            else
              BellShake(
                trigger: shakeTrigger,
                child: Icon(icon, color: Colors.black, size: 22.sp),
              ),
            if (unreadCount > 0)
              Positioned(
                top: 8.h,
                right: 8.w,
                child: Container(
                  padding: EdgeInsets.all(4.r),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8.sp,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineToggle(bool isOnline) {
    return GestureDetector(
      onTap: () async {
        HapticService.light();
        final result = await ref.read(availabilityControllerProvider.notifier).toggle();
        result.when(
          success: (_) {
            if (ref.read(availabilityControllerProvider)) {
              _promptDeviceReadiness();
            }
          },
          failure: (error) async {
            if (error is! WalletBlockedError) {
              _showSnack(error.message);
              return;
            }
            // Refresh first: the dialog quotes the balance, and a stale one
            // would tell a rider who just topped up that they are still short.
            await _loadWallet();
            if (!mounted) return;
            final action = await showWalletGateSheet(
              context,
              wallet: _wallet,
              fallbackMessage: error.message,
            );
            if (action == null || !mounted) return;
            // Both routes live on the Pocket screen; the provider tells it
            // which one to open so the choice actually does something.
            ref.read(walletGateActionProvider.notifier).request(action);
            ref.read(mainTabIndexProvider.notifier).setIndex(1);
          },
        );
      },
      child: Row(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 52.h,
              padding: EdgeInsets.symmetric(horizontal: 6.w),
              decoration: BoxDecoration(
                color: isOnline ? _onlineGreen : Colors.grey[500],
                borderRadius: BorderRadius.circular(26.r),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 250),
                        alignment: isOnline ? Alignment.centerLeft : Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isOnline) ...[
                              Container(
                                width: 6.r,
                                height: 6.r,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: 8.w),
                            ],
                            Text(
                              isOnline ? 'ONLINE' : 'OFFLINE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14.sp,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 250),
                    alignment: isOnline ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: 40.r,
                      height: 40.r,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: Icon(
                        Icons.bolt_rounded,
                        color: isOnline ? _onlineGreen : Colors.grey[500],
                        size: 22.sp,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 10.w),
          GestureDetector(
            onTap: () {
              HapticService.light();
              setState(() => _isCurrentOrderVisible = !_isCurrentOrderVisible);
            },
            child: Container(
              width: 52.h,
              height: 52.h,
              decoration: const BoxDecoration(color: Color(0xFF1C1C1E), shape: BoxShape.circle),
              child: AnimatedRotation(
                turns: _isCurrentOrderVisible ? 0 : 0.5,
                duration: const Duration(milliseconds: 300),
                child: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsAndOrdersRow(ThemeData theme) {
    final totalEarnings = (_earningsSummary?['totalEarnings'] as num?)?.toDouble() ?? 0;
    final totalOrders = (_earningsSummary?['totalOrders'] as num?)?.toInt() ?? 0;

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
                        child: Container(
            padding: EdgeInsets.all(12.r),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F6EF),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(6.r),
                  decoration: const BoxDecoration(color: Color(0xFFC8E6D9), shape: BoxShape.circle),
                  child: Icon(Icons.account_balance_wallet_rounded, color: Colors.green, size: 18.sp),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Today's Earning", style: TextStyle(color: Colors.grey[700], fontSize: 10.sp, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4.h),
                      _earningsLoading 
                          ? SizedBox(height: 20.h, width: 20.h, child: const CircularProgressIndicator(strokeWidth: 2))
                          : Text('₹${totalEarnings.toStringAsFixed(2)}', style: TextStyle(color: Colors.black, fontSize: 16.sp, fontWeight: FontWeight.w900)),
                      //SizedBox(height: 4.h),
                      // Row(
                      //   children: [
                      //     Icon(Icons.arrow_drop_up_rounded, color: Colors.green, size: 14.sp),
                      //     Text('12%', style: TextStyle(color: Colors.green, fontSize: 10.sp, fontWeight: FontWeight.bold)),
                      //   ],
                      // ),
                    //  Text('vs Yesterday', style: TextStyle(color: Colors.grey[500], fontSize: 9.sp)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
          ),
        SizedBox(width: 12.w),
        Expanded(
          child: GestureDetector(
                        child: Container(
            padding: EdgeInsets.all(12.r),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F5FF),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(6.r),
                  decoration: const BoxDecoration(color: Color(0xFFE3D9FF), shape: BoxShape.circle),
                  child: Icon(Icons.shopping_bag_rounded, color: Colors.orange, size: 18.sp),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Today's Orders", style: TextStyle(color: Colors.grey[700], fontSize: 10.sp, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4.h),
                      _earningsLoading 
                          ? SizedBox(height: 20.h, width: 20.h, child: const CircularProgressIndicator(strokeWidth: 2))
                          : Text('$totalOrders', style: TextStyle(color: Colors.black, fontSize: 16.sp, fontWeight: FontWeight.w900)),
                      //SizedBox(height: 4.h),
                      // Row(
                      //   children: [
                      //     Icon(Icons.arrow_drop_up_rounded, color: Colors.orange, size: 14.sp),
                      //     Text('3', style: TextStyle(color: Colors.orange, fontSize: 10.sp, fontWeight: FontWeight.bold)),
                      //   ],
                      // ),
                      // Text('vs Yesterday', style: TextStyle(color: Colors.grey[500], fontSize: 9.sp)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
          ),
      ],
    );
  }

  Widget _buildReferEarnFab() {
    return Positioned(
      right: -10.w,
      bottom: 110.h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 35.r),
            child: GestureDetector(
              onTap: () {
                HapticService.light();
                context.push('/refer-earn');
              },
              child: Image.asset('assets/image/refer.webp', width: 90.r, height: 90.r),
            ),
          ),
          Positioned(
            right: 23,
            top: 5.r,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticService.light();
                setState(() => _showReferEarn = false);
                Future.delayed(const Duration(seconds: 30), () {
                  if (mounted) {
                    setState(() => _showReferEarn = true);
                  }
                });
              },
              child: Container(
                padding: EdgeInsets.all(4.r),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: Icon(Icons.close, color: Colors.white, size: 14.sp),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentOrderHeader(Color textColor, DeliveryOrder order) {
    final distanceLabel =
        order.tripDistanceKm != null ? '${order.tripDistanceKm!.toStringAsFixed(1)} km away' : '';
    return Row(
      children: [
        Text(
          'Current Order',
          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800, color: textColor),
        ),
        const Spacer(),
        if (distanceLabel.isNotEmpty) ...[
          Icon(Icons.place_outlined, size: 14.sp, color: Colors.grey[500]),
          SizedBox(width: 4.w),
          Text(distanceLabel, style: TextStyle(fontSize: 12.sp, color: Colors.grey[500])),
        ],
      ],
    );
  }

  Widget _buildCurrentOrderCard(
    ThemeData theme,
    bool isDarkMode,
    Color textColor,
    Color? subTextColor,
    DeliveryOrder order,
  ) {
    final action = _actionFor(order);
    final paymentLabel = order.isCashOnDelivery
        ? '₹${order.total.toStringAsFixed(0)} COD'
        : '₹${order.total.toStringAsFixed(0)} Paid';

    final bool showNavigate = order.currentPhase == 'en_route_to_pickup' || 
                              order.currentPhase == 'at_pickup' || 
                              order.currentPhase == 'en_route_to_delivery' || 
                              order.currentPhase == 'at_drop';

    final bool navigateToRestaurant = order.currentPhase == 'en_route_to_pickup' || 
                                      order.currentPhase == 'at_pickup';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(activeTripVisibilityControllerProvider.notifier).show(),
      child: Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Icon(Icons.trip_origin, size: 14.sp, color: theme.primaryColor),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 4.h),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(
                            4,
                            (i) => Container(width: 2, height: 4.h, color: Colors.grey[350]),
                          ),
                        ),
                      ),
                    ),
                    Icon(Icons.location_on, size: 16.sp, color: _onlineGreen),
                  ],
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.restaurant.name,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.sp, color: textColor),
                      ),
                      Text(
                        order.restaurant.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.sp, color: subTextColor),
                      ),
                      SizedBox(height: 16.h),
                      Text(
                        order.customerName,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.sp, color: textColor),
                      ),
                      Text(
                        order.deliveryAddress.fullAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.sp, color: subTextColor),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    paymentLabel,
                    style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.w800, fontSize: 11.sp),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          _buildLocationSharingStatus(),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _isActionLoading
                      ? null
                      : () {
                          HapticService.light();
                          action?.action();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: theme.primaryColor.withOpacity(0.5),
                    elevation: 0,
                    minimumSize: Size(double.infinity, 48.h),
                    padding: EdgeInsets.symmetric(horizontal: 4.w),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                  ),
                  child: _isActionLoading
                      ? SizedBox(
                          width: 20.r,
                          height: 20.r,
                          child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text(
                          action?.label ?? 'Processing…',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.sp, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ),
              if (showNavigate) ...[
                SizedBox(width: 8.w),
                GestureDetector(
                  onTap: () {
                    if (navigateToRestaurant && order.restaurant.location != null) {
                      MapLauncher.launchGoogleMaps(order.restaurant.location!.lat, order.restaurant.location!.lng);
                    } else if (!navigateToRestaurant && order.deliveryAddress.location != null) {
                      MapLauncher.launchGoogleMaps(order.deliveryAddress.location!.lat, order.deliveryAddress.location!.lng);
                    } else {
                      _showSnack('Location not available');
                    }
                  },
                  child: Container(
                    height: 48.h,
                    width: 48.h,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Icon(Icons.navigation_rounded, color: Colors.white, size: 18.sp),
                  ),
                ),
              ],
              SizedBox(width: 8.w),
              GestureDetector(
                onTap: () => _callCustomer(order),
                child: Container(
                  height: 48.h,
                  width: 48.h,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Icon(Icons.call_rounded, color: Colors.white, size: 18.sp),
                ),
              ),
              SizedBox(width: 8.w),
              GestureDetector(
                onTap: () {
                  HapticService.light();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(order: order)));
                },
                child: Container(
                  height: 48.h,
                  width: 48.h,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18.sp),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildLocationSharingStatus() {
    final isOnline = ref.watch(availabilityControllerProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8.r,
          height: 8.r,
          decoration: BoxDecoration(
            color: isOnline ? _onlineGreen : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 6.w),
        Text(
          isOnline ? 'Sharing live location' : 'Location sharing paused',
          style: TextStyle(
            fontSize: 11.sp,
            fontWeight: FontWeight.w700,
            color: isOnline ? _onlineGreen : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildOfflinePrompt(
    ThemeData theme,
    bool isDarkMode,
    Color textColor,
    Color? subTextColor,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Column(
        children: [
          Icon(Icons.pause_circle_outline_rounded, color: Colors.grey[400], size: 32.sp),
          SizedBox(height: 12.h),
          Text(
            "You're offline",
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.sp, color: textColor),
          ),
          SizedBox(height: 4.h),
          Text(
            'Go online to start receiving delivery requests',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.sp, color: subTextColor),
          ),
        ],
      ),
    );
  }

  /// Builds the background map.
  /// 
  /// When OFFLINE — shows a cheap Static Maps API PNG so we don't burn
  /// a Dynamic Map load just to display a grey backdrop.
  /// When ONLINE — shows the live, interactive GoogleMap for GPS tracking.
  Widget _buildMapPreview(bool isDarkMode, bool isOnline) {
    final pos = _currentPosition;

    // --- OFFLINE: Static image (costs ~$2/1000 vs $7/1000 for Dynamic map) ---
    if (!isOnline) {
      if (pos == null) {
        // No GPS yet — just show the muted grey placeholder
        return Container(
          color: isDarkMode ? const Color(0xFF242f3e) : const Color(0xFFE8F2ED),
          child: Center(
            child: Icon(
              Icons.two_wheeler_rounded,
              size: 36,
              color: isDarkMode ? Colors.white38 : Colors.black38,
            ),
          ),
        );
      }
      // Use the Static Maps API — a simple image, no SDK map load.
      //
      // Coordinates are quantised to ~110 m before they reach the URL. Image
      // caching is keyed on the exact URL string, so feeding it raw GPS made
      // every 5 s fix a cache miss and a fresh billed Static Maps request —
      // hundreds an hour from a rider standing still. At zoom 15 a shift this
      // small is invisible, so rounding costs nothing on screen.
      final centre = '${pos.latitude.toStringAsFixed(3)},'
          '${pos.longitude.toStringAsFixed(3)}';
      final staticUrl = Uri(
        scheme: 'https',
        host: 'maps.googleapis.com',
        path: '/maps/api/staticmap',
        queryParameters: {
          'center': centre,
          'zoom': '15',
          'size': '640x480',
          'scale': '2', // Retina quality
          'style': [
            'element:geometry|color:0xf5f5f5',
            'element:labels.icon|visibility:off',
            'feature:poi|visibility:off',
            'feature:transit|visibility:off',
            'feature:road|element:geometry|color:0xffffff',
            'feature:water|element:geometry|color:0xc9c9c9',
          ],
          'markers': 'color:blue|$centre',
          'key': AppConstants.mapKey,
        },
      ).toString();

      return Image.network(
        staticUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => Container(
          color: isDarkMode ? const Color(0xFF242f3e) : const Color(0xFFE8F2ED),
        ),
      );
    }

    // --- ONLINE: Full interactive GoogleMap for live GPS tracking ---
    return SizedBox.expand(
      child: Stack(
        children: [
            Builder(
              builder: (context) {
                final pos = _currentPosition;
                if (pos == null) {
                  return Container(
                    color: isDarkMode ? const Color(0xFF242f3e) : const Color(0xFFE8F2ED),
                    child: Center(
                      child: Icon(
                        Icons.two_wheeler_rounded,
                        size: 36.sp,
                        color: isDarkMode ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  );
                }
                final authState = ref.read(authControllerProvider);
                final bool isBike = authState is AuthAuthenticated &&
                                    (authState.user.vehicleType?.toLowerCase() == 'bike' ||
                                     authState.user.vehicleType?.toLowerCase() == 'two_wheeler');
                final bool useCustomMarker = isBike && _bikeMarkerIcon != null;

                return GoogleMap(
                  onMapCreated: (controller) {
                    mapsDebug('MAP INITIALIZED', 'feed_screen');
                    _mapController = controller;
                  },
                  initialCameraPosition: CameraPosition(
                    target: LatLng(pos.latitude, pos.longitude),
                    zoom: 16,
                  ),
                  markers: {
                    if (useCustomMarker)
                      Marker(
                        markerId: const MarkerId('delivery_boy'),
                        position: LatLng(pos.latitude, pos.longitude),
                        icon: _bikeMarkerIcon!,
                        anchor: const Offset(0.5, 0.5),
                        rotation: pos.heading,
                      ),
                    if (_routeDestination != null)
                      Marker(
                        markerId: const MarkerId('route_destination'),
                        position: _routeDestination!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueRed,
                        ),
                      ),
                  },
                  circles: {
                    if (pos != null)
                      Circle(
                        circleId: const CircleId('live_location_pulse'),
                        center: LatLng(pos.latitude, pos.longitude),
                        radius: 50 + (_pulsePhase * 55),
                        fillColor: const ui.Color.fromARGB(255, 250, 131, 57).withOpacity((1 - _pulsePhase)*0.11 ),
                        strokeColor: const ui.Color.fromARGB(255, 41, 190, 30).withOpacity((1 - _pulsePhase) * 0.55),
                        strokeWidth: 3,
                      ),
                  }, 
                  polylines: {
                    if (_routePoints.length > 1)
                      Polyline(
                        polylineId: const PolylineId('active_route'),
                        points: _routePoints,
                        color: Theme.of(context).primaryColor,
                        width: 5,
                      ),
                  },
                  myLocationEnabled: !useCustomMarker,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: false,
                  mapToolbarEnabled: false,
                  style: MapStyles.mutedGrey,
                );
              },
            ),
            Positioned(
              right: 16.w,
              bottom: 260.h,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticService.light();
                      final pos = ref.read(locationServiceProvider).lastPosition;
                      if (pos != null && _mapController != null) {
                        _mapController!.animateCamera(
                          // Zoom in fully to 18.0 for a close-up view
                          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 18.0),
                        );
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.all(10.r),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Icon(Icons.my_location_rounded, color: Colors.black87, size: 22.sp),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  GestureDetector(
                    onTap: () {
                      HapticService.light();
                      final ordersState = ref.read(ordersControllerProvider);
                      if (ordersState is OrdersLoaded && ordersState.hasActiveOrder) {
                        final order = ordersState.currentOrder!;
                        final navigateToRestaurant = order.currentPhase == 'en_route_to_pickup' || order.currentPhase == 'at_pickup';
                        final lat = navigateToRestaurant ? order.restaurant.location?.lat : order.deliveryAddress.location?.lat;
                        final lng = navigateToRestaurant ? order.restaurant.location?.lng : order.deliveryAddress.location?.lng;
                        if (lat != null && lng != null) {
                          MapLauncher.launchGoogleMaps(lat, lng);
                          return;
                        }
                      }
                      
                      final pos = ref.read(locationServiceProvider).lastPosition;
                      if (pos != null && _mapController != null) {
                        _mapController!.animateCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(
                              target: LatLng(pos.latitude, pos.longitude),
                              zoom: 17,
                              bearing: pos.heading,
                              tilt: 45,
                            ),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.all(10.r),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Icon(Icons.navigation_rounded, color: Colors.blueAccent, size: 22.sp),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Future<void> _showEmergencyHelpBottomSheet() async {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1E1E1E);

    final result = await ref.read(supportRepositoryProvider).getEmergencyHelp();
    if (!mounted) return;
    final data = result.when(
      success: (d) => d,
      failure: (error) {
        _showSnack(error.message);
        return null;
      },
    );
    if (data == null || !mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24.r))),
      builder: (sheetContext) {
        return Container(
          padding: EdgeInsets.all(20.w),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40.w,
                    height: 4.h,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2.r)),
                  ),
                ),
                SizedBox(height: 20.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'EMERGENCY HELP',
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w900, color: textColor),
                    ),
                    Icon(Icons.report_problem_outlined, color: Colors.grey, size: 20.sp),
                  ],
                ),
                SizedBox(height: 20.h),
                _buildEmergencyOption(
                  icon: Icons.local_hospital_outlined,
                  iconColor: Colors.red,
                  title: 'Medical Emergency',
                  subtitle: 'Call an ambulance',
                  phone: data['medicalEmergency'] as String?,
                  textColor: textColor,
                  theme: theme,
                ),
                _buildEmergencyOption(
                  icon: Icons.warning_amber_rounded,
                  iconColor: Colors.orange,
                  title: 'Accident Helpline',
                  subtitle: 'Report an accident',
                  phone: data['accidentHelpline'] as String?,
                  textColor: textColor,
                  theme: theme,
                ),
                _buildEmergencyOption(
                  icon: Icons.shield_outlined,
                  iconColor: Colors.blue,
                  title: 'Contact Police',
                  subtitle: 'Nearest police support',
                  phone: data['contactPolice'] as String?,
                  textColor: textColor,
                  theme: theme,
                ),
                _buildEmergencyOption(
                  icon: Icons.verified_user_outlined,
                  iconColor: Colors.green,
                  title: 'Insurance',
                  subtitle: 'Policy & claim help',
                  phone: data['insurance'] as String?,
                  textColor: textColor,
                  theme: theme,
                ),
                SizedBox(height: 20.h),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmergencyOption({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color textColor,
    required ThemeData theme,
    String? phone,
  }) {
    final hasPhone = phone != null && phone.isNotEmpty;
    return GestureDetector(
      onTap: hasPhone ? () => _dial(phone) : null,
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10.r),
              decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 20.sp),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, color: textColor)),
                  SizedBox(height: 2.h),
                  Text(hasPhone ? phone : subtitle, style: TextStyle(fontSize: 12.sp, color: Colors.grey[500])),
                ],
              ),
            ),
            if (hasPhone) Icon(Icons.call_outlined, color: Colors.grey[400], size: 18.sp),
          ],
        ),
      ),
    );
  }
}
