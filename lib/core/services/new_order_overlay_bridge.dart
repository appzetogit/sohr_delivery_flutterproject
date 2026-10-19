import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's side of the native incoming-order overlay.
///
/// The overlay itself is Kotlin: it is drawn straight from the FCM
/// `RemoteMessage`, with no Flutter engine involved, because the previous
/// Flutter-rendered version had to be handed its payload across an isolate
/// boundary and that handoff kept arriving empty on device. This class only
/// carries the small amount of state that has to come back the other way —
/// which order the partner tapped, and which ones they rejected.
class NewOrderOverlayBridge {
  NewOrderOverlayBridge._();

  static const _channel = MethodChannel('app.fooddelivery/new_order_overlay');

  static Future<T?> _call<T>(String method) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      // The channel lives on MainActivity, so it does not exist in the FCM
      // background isolate. Calling from there is a no-op, not a crash.
      return null;
    } catch (e) {
      debugPrint('[offer] overlay bridge $method failed: $e');
      return null;
    }
  }

  /// The order the partner tapped on the overlay, or null.
  ///
  /// Cleared natively on read, so a resume or a rotation cannot re-raise an
  /// order that has already been answered. `autoAccept` is true when they hit
  /// ACCEPT rather than tapping the card body.
  static Future<({String orderId, bool autoAccept})?> consumeLaunchOrder() async {
    final result = await _call<Map<Object?, Object?>>('consumeLaunchOrder');
    final orderId = result?['orderId']?.toString();
    if (orderId == null || orderId.isEmpty) return null;
    return (orderId: orderId, autoAccept: result?['autoAccept'] == true);
  }

  /// Orders rejected from the overlay that the server has not been told about.
  ///
  /// The overlay process cannot read the encrypted auth token, so it queues the
  /// id and the app reports it here. The server's own dispatch timeout re-offers
  /// the order anyway — this only makes it happen sooner.
  static Future<List<String>> takePendingRejections() async {
    final result = await _call<List<Object?>>('takePendingRejections');
    return result?.map((e) => e.toString()).toList() ?? const [];
  }

  static Future<bool> hasPermission() async =>
      await _call<bool>('hasOverlayPermission') ?? false;

  static Future<void> requestPermission() => _call<bool>('requestOverlayPermission');

  /// Takes the floating card down — used when the in-app alert takes over, so
  /// the partner is never looking at two copies of the same offer.
  static Future<void> dismiss() => _call<bool>('dismissOverlay');
}
