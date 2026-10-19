import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:sohr_delivery_partner/core/utils/map_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:sohr_delivery_partner/features/orders/presentation/widgets/incoming_order_bottom_sheet.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sohr_delivery_partner/core/error/result.dart';
import 'package:sohr_delivery_partner/core/constants/map_styles.dart';
import 'package:sohr_delivery_partner/core/services/haptic_service.dart';
import 'package:sohr_delivery_partner/core/services/location_service.dart';
import 'package:sohr_delivery_partner/core/services/order_alert.dart';
import 'package:sohr_delivery_partner/core/utils/maps_debug.dart';
import 'package:sohr_delivery_partner/core/utils/polyline_decoder.dart';
import 'package:sohr_delivery_partner/features/auth/application/auth_controller.dart';
import 'package:sohr_delivery_partner/features/auth/application/auth_state.dart';
import 'package:sohr_delivery_partner/features/orders/application/incoming_order_controller.dart';
import 'package:sohr_delivery_partner/features/orders/data/models/delivery_order.dart';
import 'package:sohr_delivery_partner/features/orders/data/orders_repository.dart';
import 'package:sohr_delivery_partner/features/orders/presentation/widgets/slide_to_accept_button.dart';

const _incomingOnlineGreen = Color(0xFF1EBE5D);

/// Full-screen, Rapido/Uber-style incoming-order alert. Stacked over the
/// entire app by [main.dart]'s overlay builder whenever
/// [incomingOrderControllerProvider] is non-null — works regardless of the
/// current GoRouter location, and is the single UI path for orders arriving
/// via Socket.IO (app open) or FCM (backgrounded/locked).
class IncomingOrderScreen extends ConsumerStatefulWidget {
  const IncomingOrderScreen({super.key, required this.order});

  final DeliveryOrder order;

  @override
  ConsumerState<IncomingOrderScreen> createState() => _IncomingOrderScreenState();
}

class _IncomingOrderScreenState extends ConsumerState<IncomingOrderScreen> {
  late int _secondsLeft;
  Timer? _timer;
  bool _resolving = false;

  GoogleMapController? _mapController;
  List<LatLng> _routePoints = [];
  double? _etaMins;
  bool _boundsFitted = false;

  BitmapDescriptor? _bikeMarkerIcon;
  StreamSubscription<Position>? _positionSub;
  bool _routeFetchInFlight = false;
  bool _cameraCentered = false;

  /// An empty route used to be refetched on every GPS tick for as long as this
  /// offer stayed on screen — one billed Directions call each. Capped instead.
  int _routeAttempts = 0;
  static const int _maxRouteAttempts = 3;

  /// Token from [OrderAlert.start]; dispose passes it back so a stale disposal
  /// of a replaced alert cannot silence the ringtone of a newer one.
  late final int _alarmToken;

  @override
  void initState() {
    super.initState();
    HapticService.light();

    final deadline = widget.order.acceptanceDeadlineAt;
    _secondsLeft = deadline != null
        ? deadline.difference(DateTime.now()).inSeconds.clamp(0, 45)
        : 45;
    _alarmToken = OrderAlert.start(
      source: 'IncomingOrderScreen',
      window: Duration(seconds: _secondsLeft),
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        _expire();
        return;
      }
      setState(() => _secondsLeft--);
    });

    _loadMarkerIcon();
    _fetchRoute();
    // GPS often isn't warm yet the instant this screen appears (fresh app
    // launch from a killed-state push, or the fix just hasn't landed) — the
    // one-shot fetch above silently no-ops if `lastPosition` is null, so we
    // also retry as soon as a live position arrives.
    _positionSub =
        ref.read(locationServiceProvider).positionStream.listen(_onPositionUpdate);
  }

  Future<Uint8List> _getBytesFromAsset(String path, int width) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    final frame = await codec.getNextFrame();
    return (await frame.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  }

  Future<void> _loadMarkerIcon() async {
    try {
      final bytes = await _getBytesFromAsset('assets/image/bike.webp', 80);
      if (!mounted) return;
      setState(() => _bikeMarkerIcon = BitmapDescriptor.fromBytes(bytes));
    } catch (_) {
      // Falls back to the native "my location" blue dot.
    }
  }

  void _onPositionUpdate(Position pos) {
    if (_routePoints.isEmpty &&
        !_routeFetchInFlight &&
        _routeAttempts < _maxRouteAttempts) {
      _fetchRoute();
    }
    if (!_boundsFitted && !_cameraCentered && _mapController != null) {
      _cameraCentered = true;
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
    }
  }

  Future<void> _fetchRoute() async {
    final pos = ref.read(locationServiceProvider).lastPosition;
    if (pos == null) return;
    _routeFetchInFlight = true;
    _routeAttempts++;
    mapsDebug('ROUTE REQUEST',
        'incoming_order order=${widget.order.id} attempt=$_routeAttempts');
    final result = await ref.read(ordersRepositoryProvider).getRoute(
          widget.order.id,
          lat: pos.latitude,
          lng: pos.longitude,
          target: 'restaurant',
        );
    _routeFetchInFlight = false;
    if (!mounted) return;
    result.when(
      success: (data) {
        final encoded = data['polyline'] as String?;
        final points = (encoded != null && encoded.isNotEmpty)
            ? decodePolyline(encoded)
            : <LatLng>[];
        setState(() {
          _routePoints = points;
          _etaMins = (data['durationMins'] as num?)?.toDouble();
        });
        _fitBoundsIfReady();
      },
      failure: (_) {},
    );
  }

  void _fitBoundsIfReady() {
    if (_boundsFitted || _routePoints.isEmpty || _mapController == null) return;
    _boundsFitted = true;
    double minLat = _routePoints.first.latitude;
    double maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude;
    double maxLng = _routePoints.first.longitude;
    for (final p in _routePoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        90,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
    // Backstop — accept/decline/expire already stopped it. Covers the screen
    // being torn down some other way (navigation, hot reload).
    OrderAlert.stop(source: 'IncomingOrderScreen.dispose', token: _alarmToken);
    super.dispose();
  }

  // The ringtone is silenced here rather than left to dispose(): dispose only
  // runs once the accept/decline request comes back and this screen is torn
  // down, so on a slow network it would keep ringing for seconds after the tap.
  Future<void> _accept() async {
    if (_resolving) return;
    _resolving = true;
    _timer?.cancel();
    await OrderAlert.stop(source: 'IncomingOrderScreen.accept');
    await ref.read(incomingOrderControllerProvider.notifier).accept();
  }

  Future<void> _decline() async {
    if (_resolving) return;
    _resolving = true;
    _timer?.cancel();
    await OrderAlert.stop(source: 'IncomingOrderScreen.decline');
    await ref.read(incomingOrderControllerProvider.notifier).decline();
  }

  Future<void> _expire() async {
    if (_resolving) return;
    _resolving = true;
    await OrderAlert.stop(source: 'IncomingOrderScreen.expire');
    await ref.read(incomingOrderControllerProvider.notifier).expire();
  }

  Widget _buildMap() {
    return StreamBuilder<Position>(
      stream: ref.read(locationServiceProvider).positionStream,
      initialData: ref.read(locationServiceProvider).lastPosition,
      builder: (context, snapshot) {
        final pos = snapshot.data;
        final initialTarget = pos != null
            ? LatLng(pos.latitude, pos.longitude)
            : (_routePoints.isNotEmpty ? _routePoints.first : const LatLng(0, 0));

        final authState = ref.read(authControllerProvider);
        final isBike = authState is AuthAuthenticated &&
            (authState.user.vehicleType?.toLowerCase() == 'bike' ||
                authState.user.vehicleType?.toLowerCase() == 'two_wheeler');
        final useCustomMarker = isBike && _bikeMarkerIcon != null;

        return GoogleMap(
          onMapCreated: (controller) {
            mapsDebug('MAP INITIALIZED', 'incoming_order');
            _mapController = controller;
            _fitBoundsIfReady();
          },
          initialCameraPosition: CameraPosition(target: initialTarget, zoom: 15),
          markers: {
            if (useCustomMarker && pos != null)
              Marker(
                markerId: const MarkerId('delivery_partner'),
                position: LatLng(pos.latitude, pos.longitude),
                icon: _bikeMarkerIcon!,
                anchor: const Offset(0.5, 0.5),
                rotation: pos.heading,
              ),
            if (_routePoints.isNotEmpty)
              Marker(
                markerId: const MarkerId('restaurant'),
                position: _routePoints.last,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange,
                ),
              ),
          },
          polylines: {
            if (_routePoints.length > 1)
              Polyline(
                polylineId: const PolylineId('pickup_route'),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1E1E1E);
    final subTextColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];
    final order = widget.order;

    final etaLabel = _etaMins != null
        ? '${_etaMins!.round()} mins away'
        : (order.tripDurationMins != null
            ? '${order.tripDurationMins!.toStringAsFixed(0)} mins away'
            : null);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: _buildMap()),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.only(top: 12.h, right: 16.w, left: 16.w),
                child: Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: _decline,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24.r),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.close, size: 16, color: Colors.black87),
                          SizedBox(width: 6.w),
                          Text(
                            'Deny · ${_secondsLeft}s',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black87, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                bottom: false,
                child: IncomingOrderBottomSheet(
                  order: order,
                  secondsLeft: _secondsLeft,
                  onAccept: _accept,
                  onReject: _decline,
                ),
              ),
            ),
          ],
        ), 
      ),
    );
  }


  Widget _buildBottomCard(
    ThemeData theme,
    bool isDarkMode,
    Color textColor,
    Color? subTextColor,
    DeliveryOrder order,
    String? etaLabel,
  ) {
    final tripTimeVal = (order.tripDurationMins != null && order.tripDurationMins! > 0)
        ? order.tripDurationMins!
        : ((order.tripDistanceKm ?? 0) * 3.0);
    final displayTripTime = tripTimeVal > 0 ? tripTimeVal.toStringAsFixed(0) : '--';

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 14.h),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20.w, 26.h, 20.w, 20.h),
              decoration: BoxDecoration(
                color: Colors.white, // Always white
                borderRadius: BorderRadius.circular(28.r),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, -4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Price Header
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      order.riderEarning > 0 ? '₹ ${order.riderEarning.toStringAsFixed(2)}' : '₹ —',
                      style: TextStyle(fontSize: 32.sp, fontWeight: FontWeight.w900, color: Colors.black87),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  
                  // Three blocks row
                  Row(
                    children: [
                      _buildStatBlock(
                        Icons.access_time_filled_rounded, 
                        Colors.amber[600]!, 
                        'TRIP TIME', 
                        '$displayTripTime MINS'
                      ),
                      SizedBox(width: 8.w),
                      _buildStatBlock(
                        Icons.location_on_rounded, 
                        Colors.blue, 
                        'DISTANCE', 
                        '${order.tripDistanceKm?.toStringAsFixed(1) ?? '--'} km'
                      ),
                      SizedBox(width: 8.w),
                      _buildStatBlock(
                        Icons.shopping_bag_rounded, 
                        Colors.amber[600]!, 
                        'TOTAL ITEMS', 
                        '1 Items' // Assumed default if missing
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 16.h),
                  
                  // Timeline container
                  Container(
                    padding: EdgeInsets.all(12.r),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTimelineRow(
                          title: order.isMartOrder
                              ? 'MART PICKUP'
                              : 'RESTAURANT PICKUP',
                          name: order.restaurant.name,
                          address: order.restaurant.address,
                          dotColor: const Color(0xFF9E6512), // Orange
                          phoneColor: const Color(0xFF9E6512),
                        ),
                        // Dashed line placeholder
                        Padding(
                          padding: EdgeInsets.only(left: 3.w, top: 4.h, bottom: 4.h),
                          child: Container(width: 2, height: 16.h, color: Colors.grey[300]),
                        ),
                        _buildTimelineRow(
                          title: 'CUSTOMER DROP',
                          name: order.customerName.isNotEmpty ? order.customerName : 'Customer',
                          address: order.deliveryAddress.fullAddress,
                          dotColor: Colors.blue,
                          phoneColor: Colors.blue,
                        ),
                      ],
                    ),
                  ),

                  if (order.customerLocationLink.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => MapLauncher.openCustomerLocation(
                        link: order.customerLocationLink,
                        address: order.deliveryAddress.fullAddress,
                      ),
                      icon: const Icon(Icons.location_on_outlined, size: 18),
                      label: const Text('View location'),
                    ),

                  SizedBox(height: 24.h),
                  
                  // Slide to accept
                  SlideToAcceptButton(
                    onAccept: _accept,
                    isLoading: _resolving,
                  ),
                  
                  SizedBox(height: 16.h),
                  
                  // Reject text
                  GestureDetector(
                    onTap: _decline,
                    child: Text(
                      'Reject Order',
                      style: TextStyle(
                        color: Colors.red[800],
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // "NEW ORDER" pill
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30.r),
              border: Border.all(color: const Color(0xFF9E6512), width: 1.5),
            ),
            child: Text(
              [
                'NEW ${order.serviceLabel?.toUpperCase() ?? ''} ORDER'
                    .replaceAll('  ', ' '),
                if (order.orderCode.isNotEmpty) '#${order.orderCode}',
              ].join('   ·   '),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.sp, color: const Color(0xFF9E6512)),
            ),
          ),
          
          // Timer Circle (top right)
          Positioned(
            right: 0,
            top: -10.h,
            child: Container(
              width: 48.r,
              height: 48.r,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF9E6512), width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: Center(
                child: Text(
                  '${_secondsLeft}s',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.sp, color: Colors.black87),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatBlock(IconData icon, Color iconColor, String title, String value) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 4.w),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 18.sp),
            SizedBox(height: 8.h),
            Text(
              title,
              style: TextStyle(fontSize: 9.sp, fontWeight: FontWeight.w800, color: Colors.grey[500]),
            ),
            SizedBox(height: 2.h),
            Text(
              value,
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w900, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineRow({
    required String title, 
    required String name, 
    required String address, 
    required Color dotColor,
    required Color phoneColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 4.h),
          child: Container(
            width: 8.r,
            height: 8.r,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 9.sp, fontWeight: FontWeight.w800, color: dotColor)),
              SizedBox(height: 4.h),
              Text(name, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w900, color: Colors.black87)),
              SizedBox(height: 2.h),
              Text(
                address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.sp, color: Colors.grey[500], fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }

}
