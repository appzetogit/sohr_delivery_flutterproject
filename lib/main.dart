import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sohr_delivery_partner/core/services/device_readiness_service.dart';
import 'package:sohr_delivery_partner/core/constants/app_constants.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:sohr_delivery_partner/core/router/app_router.dart';
import 'package:sohr_delivery_partner/core/services/deep_link_service.dart';
import 'package:sohr_delivery_partner/core/services/fcm_service.dart';
import 'package:sohr_delivery_partner/core/services/location_service.dart';
import 'package:sohr_delivery_partner/core/services/new_order_overlay_bridge.dart';
import 'package:sohr_delivery_partner/core/services/referral_tracking_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sohr_delivery_partner/core/theme/app_theme.dart';
import 'package:sohr_delivery_partner/core/theme/theme_mode_provider.dart';
import 'package:sohr_delivery_partner/features/orders/application/active_trip_visibility_controller.dart';
import 'package:sohr_delivery_partner/features/orders/application/incoming_order_controller.dart';
import 'package:sohr_delivery_partner/features/orders/application/orders_controller.dart';
import 'package:sohr_delivery_partner/features/orders/application/orders_state.dart';
import 'package:sohr_delivery_partner/features/orders/application/pending_customer_rating_controller.dart';
import 'package:sohr_delivery_partner/features/orders/data/models/delivery_order.dart';
import 'package:sohr_delivery_partner/features/orders/presentation/screens/active_trip_screen.dart';
import 'package:sohr_delivery_partner/features/orders/presentation/screens/incoming_order_screen.dart';
import 'package:sohr_delivery_partner/core/presentation/widgets/no_network_overlay.dart';
import 'package:sohr_delivery_partner/core/services/network_controller.dart';
import 'package:sohr_delivery_partner/features/orders/presentation/screens/rate_customer_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only, whatever the phone's auto-rotate setting says. A rider reads
  // this one-handed on a mount; every screen, sheet and dialog is laid out for
  // a tall viewport, and the map screens in particular have no landscape
  // design. The manifest locks Android before the engine even starts (so there
  // is no rotate-then-snap on launch) — this covers iOS and keeps the intent
  // visible from Dart.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const ProviderScope(child: FoodDeliveryApp()));
}

/// Bumped only if a future release needs to re-ask everyone.
const _permissionsAskedKey = 'permissions_requested_v2';

class FoodDeliveryApp extends ConsumerStatefulWidget {
  const FoodDeliveryApp({super.key});

  @override
  ConsumerState<FoodDeliveryApp> createState() => _FoodDeliveryAppState();
}

class _FoodDeliveryAppState extends ConsumerState<FoodDeliveryApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      ref.read(fcmServiceProvider).initialize();
      // Install Referrer covers a rider who arrived via the Play Store;
      // DeepLinkService covers one who tapped an invite with the app already
      // installed. Both write the same stored code, so registration prefills
      // from either without knowing which happened.
      ReferralTrackingService.initialize();
      DeepLinkService.instance.initialize();
      await _requestFirstLaunchPermissions();
      _consumeOverlayHandoff();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Tapping the overlay resumes an already-running app rather than starting
      // it, so the handoff has to be picked up here as well as at launch.
      _consumeOverlayHandoff();
      // Re-checks full-screen-intent / overlay permissions on every resume,
      // not just cold start — catches a rider who dismissed the Settings
      // prompt the first time or toggled it manually while the app was
      // backgrounded (see FcmService.ensureAndroidAlertPermissions).
      ref.read(fcmServiceProvider).ensureAndroidAlertPermissions();

      // Re-register the push token on every resume, for the same reason.
      //
      // Registration only happened at launch and login, so a save that failed
      // — or a token FCM rotated while the app was closed — left the rider
      // silently unreachable until the next relaunch. Five of six online riders
      // were in exactly that state: apps running, GPS fresh, no token on the
      // server, and no order offers reaching them.
      //
      // Idempotent server-side ($addToSet), so repeating it is free.
      unawaited(ref.read(fcmServiceProvider).registerToken());
    }
  }

  /// Asks for everything the app needs as soon as the app opens, so the rider
  /// never meets these prompts for the first time on the "go online" tap.
  ///
  /// Runtime dialogs (location, background location, notifications) are
  /// re-attempted on every cold start until granted — they are no-ops once
  /// granted or permanently denied, and a one-time flag alone was skipping
  /// them whenever it survived a reinstall. The steps that throw the rider
  /// out to a Settings screen (location service, battery, overlay) run once.
  Future<void> _requestFirstLaunchPermissions() async {
    // Wait for the first frame: a permission dialog needs a visible activity.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final prefs = await SharedPreferences.getInstance();
    final firstRun = prefs.getBool(_permissionsAskedKey) != true;
    if (firstRun) await prefs.setBool(_permissionsAskedKey, true);

    Future<PermissionStatus> ask(Permission p) async {
      final status = await p.status;
      if (status.isGranted || status.isPermanentlyDenied) return status;
      return p.request();
    }

    // Foreground location first; Android only offers "Allow all the time"
    // after it is granted.
    final location = await ask(Permission.locationWhenInUse);
    if (location.isGranted) await ask(Permission.locationAlways);
    await ask(Permission.notification);

    if (!firstRun) return;

    await ref.read(fcmServiceProvider).ensureAndroidAlertPermissions();
    await ref.read(locationServiceProvider).ensurePermissions();

    final checks = await DeviceReadinessService.evaluate();
    if (checks.any((c) => c.id == 'battery' && !c.satisfied)) {
      await DeviceReadinessService.fix('battery');
    }

    // "Display over other apps" last, deliberately: it cannot be granted by a
    // dialog, so it throws the rider out to a Settings screen.
    if (!await NewOrderOverlayBridge.hasPermission()) {
      await NewOrderOverlayBridge.requestPermission();
    }
  }

  /// Picks up whatever the native overlay left for us: the order the partner
  /// tapped, and any they rejected while the app was not running.
  Future<void> _consumeOverlayHandoff() async {
    final controller = ref.read(incomingOrderControllerProvider.notifier);
    unawaited(controller.flushOverlayRejections());

    final handoff = await NewOrderOverlayBridge.consumeLaunchOrder();
    if (handoff == null || !mounted) return;
    await controller.showById(handoff.orderId, autoAccept: handoff.autoAccept);
  }

  @override
  Widget build(BuildContext context) {
    final goRouter = ref.watch(goRouterProvider);

    final themeMode = ref.watch(themeModeProvider);

    return ScreenUtilInit(
      designSize: const Size(375, 812), // Standard design size
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: AppConstants.title,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          routerConfig: goRouter,
          builder: (context, routedChild) {
            final isDarkMode = Theme.of(context).brightness == Brightness.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: isDarkMode ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
              child: Stack(
                children: [
                  if (routedChild != null) routedChild,
                Consumer(
                  builder: (context, ref, _) {
                    final ordersState = ref.watch(ordersControllerProvider);
                    final hasActiveOrder =
                        ordersState is OrdersLoaded &&
                        ordersState.currentOrder != null;
                    final showTrip = ref.watch(
                      activeTripVisibilityControllerProvider,
                    );
                    if (!hasActiveOrder || !showTrip)
                      return const SizedBox.shrink();
                    return const ActiveTripScreen();
                  },
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final incomingOrder = ref.watch(
                      incomingOrderControllerProvider,
                    );
                    if (incomingOrder == null) return const SizedBox.shrink();
                    return IncomingOrderScreen(
                      key: ValueKey(incomingOrder.id),
                      order: incomingOrder,
                    );
                  },
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final pendingRating = ref.watch(
                      pendingCustomerRatingControllerProvider,
                    );
                    if (pendingRating == null) return const SizedBox.shrink();
                    return RateCustomerScreen(
                      key: ValueKey(pendingRating.id),
                      order: pendingRating,
                    );
                  },
                ),
                  Consumer(
                    builder: (context, ref, _) {
                      final isOnline = ref.watch(networkControllerProvider);
                      if (isOnline) return const SizedBox.shrink();
                      return const NoNetworkOverlay();
                    },
                  ),
                ],
              )
            );
          },
        );
      },
    );
  }
}
