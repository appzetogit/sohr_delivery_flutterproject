import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Streams GPS positions while the partner is online. On Android this runs
/// as a foreground service with a persistent notification (via geolocator's
/// `foregroundNotificationConfig`) so pings keep flowing when the app is
/// backgrounded; on iOS it relies on the `location` background mode.
class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  final _positionController = StreamController<Position>.broadcast();
  Position? lastPosition;

  Stream<Position> get positionStream => _positionController.stream;
  bool get isTracking => _positionSubscription != null;

  Future<bool> ensurePermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return false;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return false;
      }
    }

    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return false;
    }

    if (Platform.isAndroid) {
      final backgroundStatus = await Permission.locationAlways.status;
      if (!backgroundStatus.isGranted) {
        await Permission.locationAlways.request();
      }
      final notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        await Permission.notification.request();
      }
    }

    return true;
  }

  void startTracking() {
    if (isTracking) return;

    final locationSettings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
            intervalDuration: const Duration(seconds: 5),
            // Deliberately no foregroundNotificationConfig.
            //
            // Setting one makes geolocator start a SECOND foreground service
            // with a SECOND permanent notification, so the rider saw two
            // "you're online" entries for one state and could dismiss neither —
            // Android forbids dismissing a foreground service's notification.
            // RiderOnlineService is already running, is already declared
            // foregroundServiceType="location" with FOREGROUND_SERVICE_LOCATION,
            // and starts before this stream does, so background fixes keep
            // arriving under it. One service, one notification.
          )
        : AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((pos) {
              lastPosition = pos;
              _positionController.add(pos);
            });
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Injects a synthetic fix into the same stream real GPS updates flow
  /// through, so the map marker, the socket `update-location` broadcast, and
  /// the backend availability ping all react exactly as they would to a real
  /// movement. Backs the debug route simulator on [ActiveTripScreen], which
  /// lets testers exercise customer-side live tracking without physically
  /// travelling the route.
  void emitSimulatedPosition({
    required double latitude,
    required double longitude,
    double heading = 0,
    double speed = 0,
  }) {
    final pos = Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: heading,
      headingAccuracy: 1,
      speed: speed,
      speedAccuracy: 0,
      isMocked: true,
    );
    lastPosition = pos;
    _positionController.add(pos);
  }

  void dispose() {
    stopTracking();
    _positionController.close();
  }
}

final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(service.dispose);
  return service;
});
