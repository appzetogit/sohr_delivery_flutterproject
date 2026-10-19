import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/error/result.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/sound_service.dart';
import '../../../core/services/rider_online_service.dart';
import '../../../core/services/socket_service.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/application/auth_controller.dart';
import '../../orders/application/orders_controller.dart';
import '../../orders/application/orders_state.dart';
import '../data/profile_repository.dart';

class AvailabilityController extends Notifier<bool> {
  late ProfileRepository _repository;
  StreamSubscription<Position>? _positionSub;
  Timer? _keepAliveTimer;
  DateTime _lastPing = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastAvailabilityPing = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  bool build() {
    _repository = ref.read(profileRepositoryProvider);
    final authState = ref.read(authControllerProvider);
    final startedOnline = authState is AuthAuthenticated && authState.user.isOnline;

    ref.onDispose(() {
      _positionSub?.cancel();
      _keepAliveTimer?.cancel();
      // Covers logout, which tears this controller down without going through
      // goOffline — otherwise the service and its notification outlive the
      // session, claiming a signed-out rider is online.
      unawaited(RiderOnlineService.stop());
    });

    if (startedOnline) {
      Future.microtask(() {
        _startTracking();
        ref.read(ordersControllerProvider.notifier).startPolling();
      });
    }
    return startedOnline;
  }

  Future<Result<void, AppError>> toggle() async {
    if (state) {
      return goOffline();
    }
    return goOnline();
  }

  Future<Result<void, AppError>> goOnline() async {
    final locationService = ref.read(locationServiceProvider);
    final hasPermission = await locationService.ensurePermissions();
    if (!hasPermission) {
      return Result.failure(
        NetworkError('Location permission is required to go online'),
      );
    }

    // Whatever fix is already to hand, never a fresh one. getCurrentPosition
    // waits on the GPS — seconds on a cold radio — and it sat between the tap
    // and the API call, so the toggle looked frozen. _startTracking below pings
    // a real fix the moment we are online, so dispatch still gets an accurate
    // position; it just no longer happens while the rider watches a dead
    // switch. Time-boxed even in the last-resort branch.
    Position? position = locationService.lastPosition;
    try {
      position ??= await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // No fix available in time — go online anyway. The keep-alive ping fires
      // immediately after and carries the position as soon as there is one.
    }
    if (position != null) locationService.lastPosition = position;

    final result = await _repository.updateAvailability(
      true,
      lat: position?.latitude,
      lng: position?.longitude,
    );
    return result.when(
      success: (update) {
        // The server has the last word. It refuses to bring a rider online
        // while their wallet is under the admin's minimum, and answers with
        // offline + a reason rather than an error — so trusting the request
        // instead of the reply would leave the toggle green on a rider that
        // dispatch is ignoring.
        if (!update.isOnline) {
          state = false;
          _stopTracking();
          ref.read(ordersControllerProvider.notifier).stopPolling();
          return Result.failure(
            update.walletBlocked
                ? WalletBlockedError(update.blockedMessage!)
                : NetworkError('Could not go online. Please try again.'),
          );
        }
        state = true;
        ref.read(ordersControllerProvider.notifier).startPolling();
        _startTracking();
        SoundService.playRefresh();
        return const Result.success(null);
      },
      failure: (error) => Result.failure(error),
    );
  }

  /// Drops the rider offline locally because the server already has.
  ///
  /// The wallet floor is re-evaluated server-side on every keep-alive ping and
  /// after every completed delivery, so a balance that falls mid-shift — a COD
  /// deduction, a withdrawal, an admin adjustment — takes the rider offline
  /// without them touching anything. This mirrors it into the UI.
  void _forceOffline() {
    if (!state) return;
    _stopTracking();
    ref.read(ordersControllerProvider.notifier).stopPolling();
    state = false;
  }

  Future<Result<void, AppError>> goOffline() async {
    // Flip first, tell the server second. The state ends up false either way —
    // it always did — so awaiting the round-trip before moving the switch only
    // ever made going offline feel slow. Stopping tracking and polling right
    // away is also the safer order: nothing keeps claiming the rider is
    // available while the request is in flight.
    _stopTracking();
    ref.read(ordersControllerProvider.notifier).stopPolling();
    state = false;
    SoundService.playRefresh();

    final result = await _repository.updateAvailability(false);
    return result.when(
      success: (_) => const Result.success(null),
      failure: (error) => Result.failure(error),
    );
  }

  void _startTracking() {
    // Ask Android to stop freezing us first. Everything below — the position
    // stream and the keep-alive ping — silently stops running once the process
    // is backgrounded without this, which is what let riders go stale and drop
    // out of dispatch while believing they were online.
    unawaited(RiderOnlineService.start());

    final locationService = ref.read(locationServiceProvider);
    locationService.startTracking();
    _positionSub?.cancel();
    _positionSub = locationService.positionStream.listen(_onPosition);

    // The position stream only emits on movement (distanceFilter), so a
    // stationary rider would otherwise never refresh lastLocationAt and
    // silently drop out of dispatch once the backend's GPS staleness
    // window elapses. Ping on a timer too, independent of movement.
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(minutes: 3), (_) => _pingLocation());
    // Ping immediately as well. build() starts tracking for a rider who was
    // already online without ever taking a fix (unlike goOnline, which calls
    // getCurrentPosition), so without this their first ping is 3 minutes away
    // at best — and never, if they don't move.
    unawaited(_pingLocation());
  }

  /// Refreshes lastLocationAt server-side so dispatch keeps considering this rider.
  ///
  /// Resolving a position here rather than bailing on null is the whole point:
  /// LocationService.lastPosition stays null until the movement-gated stream first
  /// emits, which never happens for a rider who resumed the app already-online and
  /// hasn't moved 15m. Those riders were being dropped from every order offer, so
  /// they never even received the new-order push.
  Future<void> _pingLocation() async {
    final service = ref.read(locationServiceProvider);
    var pos = service.lastPosition ?? await Geolocator.getLastKnownPosition();
    if (pos == null) {
      try {
        pos = await Geolocator.getCurrentPosition();
      } catch (_) {
        return; // No fix available at all — nothing useful to report.
      }
    }
    service.lastPosition = pos;
    _lastPing = DateTime.now();
    _lastAvailabilityPing = _lastPing;
    final result = await _repository.updateAvailability(
      true,
      lat: pos.latitude,
      lng: pos.longitude,
    );
    result.when(
      success: (update) {
        if (!update.isOnline) _forceOffline();
      },
      failure: (_) {},
    );
  }

  void _stopTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    ref.read(locationServiceProvider).stopTracking();

    // The notification must go the moment the rider goes offline. A lingering
    // "You're online" is both a lie and a battery drain, and it is the single
    // fastest way to get uninstalled.
    unawaited(RiderOnlineService.stop());
  }

  void _onPosition(Position position) {
    final now = DateTime.now();
    final ordersState = ref.read(ordersControllerProvider);
    final active = ordersState is OrdersLoaded && ordersState.currentOrder != null;

    // Idle: refresh the stored location every 30s (the server offers orders by
    // it). On a trip the socket carries location, so the PATCH is slowed to 60s.
    final pingEvery = Duration(seconds: active ? 60 : 30);
    if (now.difference(_lastAvailabilityPing) >= pingEvery) {
      _lastAvailabilityPing = now;
      _repository
          .updateAvailability(true, lat: position.latitude, lng: position.longitude)
          .then(
            (result) => result.when(
              success: (update) {
                if (!update.isOnline) _forceOffline();
              },
              failure: (_) {},
            ),
          );
    }

    // Trip: stream over the socket every ~4s (server drops <2s per order).
    if (now.difference(_lastPing) < const Duration(seconds: 4)) return;
    _lastPing = now;
    if (ordersState is! OrdersLoaded || ordersState.currentOrder == null) return;

    final socket = ref.read(socketServiceProvider);
    void send(String orderId) => socket.sendLocationUpdate(
          orderId: orderId,
          lat: position.latitude,
          lng: position.longitude,
          heading: position.heading,
          speed: position.speed,
          accuracy: position.accuracy,
        );
    send(ordersState.currentOrder!.id);
    // Batched orders already picked up but not yet delivered.
    for (final o in ordersState.nextOrders) {
      if (o.currentPhase == 'en_route_to_delivery' || o.currentPhase == 'at_drop') {
        send(o.id);
      }
    }
  }
}

final availabilityControllerProvider =
    NotifierProvider<AvailabilityController, bool>(AvailabilityController.new);
