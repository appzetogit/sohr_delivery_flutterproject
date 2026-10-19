import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../network/api_endpoints.dart';
import '../network/dio_client.dart';
import '../theme/app_theme.dart';
import '../storage/token_storage.dart';
import 'socket_service.dart' show offerLog;

/// The channel every new-order alert this app posts goes out on.
///
/// A fresh id, deliberately. Android freezes a channel's importance, sound and
/// vibration at creation and ignores every later edit under the same id, so a
/// device that already holds the old channel would keep whatever it was first
/// created with. A new id is the only way a sound/importance change reaches an
/// existing install without a reinstall.
const _newOrdersChannelId = 'new_orders_v3';

/// The dedicated new-order ringtone,
/// `android/app/src/main/res/raw/neworder_ring.mp4` — the same file the in-app
/// alert and the native order card play. Named without the extension, as
/// Android requires.
///
/// This channel was left pointing at the old `neworder.mp3` when the ringtone
/// was swapped, which is why riders kept hearing the previous tone: the tray
/// leg of a new-order push is rendered by the system on this channel, and the
/// system plays whatever the channel was created with.
///
/// Only this channel uses it. Order status updates and everything else stay on
/// [FcmService._channel] / [_highImportanceChannel] with the device's normal
/// notification sound.
const _newOrderSound = RawResourceAndroidNotificationSound('neworder_ring');

const _newOrdersChannel = AndroidNotificationChannel(
  _newOrdersChannelId,
  'New Orders',
  description: 'Incoming order offers that require immediate action',
  importance: Importance.high,
  playSound: true,
  sound: _newOrderSound,
  // Alarm usage, so the alert is still audible with media volume down — the
  // normal state for someone riding with the phone mounted.
  audioAttributesUsage: AudioAttributesUsage.alarm,
  enableVibration: true,
);

/// Still created, even though nothing in this app posts to it any more.
///
/// `order-dispatch.service.js` sends its own tray copy with
/// `androidChannelId: 'incoming_orders_channel_v3'`, and that copy is the only
/// alert a partner gets on ROMs where the background handler never runs.
/// Android silently demotes a notification whose channel does not exist to a
/// low-importance fallback — no heads-up, no sound — so deleting this would
/// switch off the one path that works when ours doesn't. Retire it once the
/// backend literal is moved to [_newOrdersChannelId].
const _legacyServerChannel = AndroidNotificationChannel(
  'incoming_orders_channel_v3',
  'New Orders (server)',
  description: 'Incoming order offers delivered directly by the server',
  importance: Importance.high,
  playSound: true,
  sound: _newOrderSound,
  audioAttributesUsage: AudioAttributesUsage.alarm,
  enableVibration: true,
);

/// Stable notification id for an order's incoming alert.
///
/// The alert used to be posted under `message.hashCode`, which is derived from the
/// push itself and is therefore unknowable to anything that later wants to take the
/// alert down. Keying on the order id means the withdrawal push can cancel exactly
/// the alert its order raised. Masked positive because Android ids are ints and a
/// negative one is not portable across the plugin.
int incomingOrderNotificationId(String orderId) => orderId.hashCode & 0x7fffffff;

String? _orderIdOf(Map<String, dynamic> data) {
  final id = (data['orderMongoId'] ?? data['orderId'] ?? data['_id'])?.toString();
  return (id == null || id.isEmpty) ? null : id;
}

/// Takes down the incoming-order alert for [orderId] wherever it is showing.
///
/// Safe to call from the background isolate, which is the case that matters: the
/// rider whose app is closed is the one the socket `order_claimed` event cannot
/// reach, so this is the only path that clears their screen.
Future<void> dismissIncomingOrderAlert(String orderId) async {
  final localNotifications = FlutterLocalNotificationsPlugin();
  if (Platform.isAndroid) {
    // The background isolate holds its own plugin instance with nothing
    // registered, and this is what lets `cancel` below reach the notification
    // manager there. Android-only settings — running it on iOS would replace
    // the Darwin configuration FcmService.initialize() installed, and the main
    // isolate's instance is already initialized anyway.
    await localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveBackgroundNotificationResponse:
          backgroundNotificationResponseHandler,
    );
  }
  await localNotifications.cancel(incomingOrderNotificationId(orderId));
  await cancelFcmTrayCopy(orderId);
}

@pragma('vm:entry-point')
void backgroundNotificationResponseHandler(NotificationResponse response) async {
  final payload = response.payload;
  final actionId = response.actionId;

  if (actionId == 'accept' || actionId == 'reject') {
    final orderId = _orderIdOfPayload(payload);
    if (orderId != null) {
      await _respondToOrderFromBackground(orderId: orderId, accept: actionId == 'accept');
    }
  }
}

String? _orderIdOfPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map) {
      final id = (decoded['orderMongoId'] ?? decoded['orderId'] ?? decoded['_id'])?.toString();
      return (id == null || id.isEmpty) ? null : id;
    }
  } catch (_) {}
  return payload;
}

Future<void> _respondToOrderFromBackground({
  required String orderId,
  required bool accept,
}) async {
  try {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'access_token');
    if (token != null && token.isNotEmpty) {
      final dio = Dio(BaseOptions(
        baseUrl: AppConstants.baseUrl,
        headers: {'Authorization': 'Bearer $token'},
      ));
      await dio.patch(
        accept
            ? ApiEndpoints.orderAccept(orderId)
            : ApiEndpoints.orderReject(orderId),
      );
    }
  } catch (e) {
    debugPrint('[FCM Background Action] Error responding to order $orderId: $e');
  } finally {
    try {
      await FlutterLocalNotificationsPlugin()
          .cancel(incomingOrderNotificationId(orderId));
    } catch (_) {}
  }
}

/// Removes the OS-rendered copy of the new-order push.
///
/// The push is hybrid: FCM posts a tray notification itself (tag `order_<id>`,
/// set by the backend — the two must stay in sync) so ROMs that refuse to start
/// the app in the background still ring. Wherever OUR alert does manage to show,
/// this takes the tray copy down so the rider sees one alert, not two. FCM posts
/// tagged notifications under id 0.
Future<void> cancelFcmTrayCopy(String orderId) async {
  try {
    await FlutterLocalNotificationsPlugin().cancel(0, tag: 'order_$orderId');
  } catch (_) {
    // Worst case the tray copy stays — a duplicate, not a lost order.
  }
}

/// Every field the alert needs, read straight off the push.
///
/// This is the whole fix for "the order details have not arrived yet". The
/// payload is already in this isolate's hands the moment the handler runs —
/// it was previously written to SharedPreferences and re-read from a second
/// isolate (the overlay engine), and that handoff arrived empty every time:
/// `key empty after 30 reads, 0 direct messages`. Nothing here crosses an
/// isolate boundary any more.
class NewOrderPush {
  const NewOrderPush._({
    required this.orderId,
    required this.displayId,
    required this.earning,
    required this.data,
  });

  /// The Mongo id — what every API call keys on. Never empty.
  final String orderId;

  /// The readable code the partner sees ("AZ10567"). The push puts the Mongo
  /// id in `orderId` and the readable code in `orderDisplayId`.
  final String displayId;
  final String earning;
  final Map<String, dynamic> data;

  static String _str(Map<String, dynamic> d, List<String> keys) {
    for (final key in keys) {
      final value = d[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  /// Returns null when the push carries no usable order id — without one there
  /// is nothing to accept, fetch or de-duplicate, so posting an alert would
  /// strand the partner on a notification that can't lead anywhere.
  static NewOrderPush? parse(Map<String, dynamic> data) {
    final orderId = _str(data, ['orderMongoId', '_id', 'orderId']);
    if (orderId.isEmpty) return null;
    return NewOrderPush._(
      orderId: orderId,
      displayId: _str(data, ['orderDisplayId', 'orderNumber']),
      earning: _str(data, ['riderEarning', 'earnings', 'price']),
      data: data,
    );
  }

  /// What the partner reads on the notification.
  String get reference => displayId.isNotEmpty
      ? displayId
      : (orderId.length > 6
          ? '#${orderId.substring(orderId.length - 6).toUpperCase()}'
          : orderId);

  String get storeName => _str(data, ['restaurantName', 'storeName']);
  String get orderValue => _str(data, ['total', 'orderValue']);
  String get itemCount => _str(data, ['itemsCount', 'itemCount', 'totalItems']);

  String get notificationBody {
    final headline = [
      'Order $reference',
      if (earning.isNotEmpty) '₹$earning earning',
    ].join(' • ');
    final detail = [
      if (storeName.isNotEmpty) storeName,
      if (itemCount.isNotEmpty) '$itemCount items',
      if (orderValue.isNotEmpty) '₹$orderValue order',
    ].join(' · ');
    return [
      headline,
      'Tap to view and accept the order.',
      if (detail.isNotEmpty) detail,
    ].join('\n');
  }
}

/// Posts the incoming-order notification from [push].
///
/// Shared by the background isolate and the foreground path so both produce an
/// identical alert, on one channel, under one id.
Future<void> showNewOrderNotification(
  FlutterLocalNotificationsPlugin plugin,
  NewOrderPush push,
) async {
  debugPrint('[NEW_ORDER_NOTIFICATION] creating notification');
  debugPrint('[NEW_ORDER_NOTIFICATION] orderId = ${push.orderId}');
  debugPrint('[NEW_ORDER_NOTIFICATION] channel = $_newOrdersChannelId');
  debugPrint('[NEW_ORDER_NOTIFICATION] importance = HIGH');

  final body = push.notificationBody;
  await plugin.show(
    // Keyed on the order, so the same order arriving twice REPLACES its own
    // notification instead of stacking a second one.
    incomingOrderNotificationId(push.orderId),
    '🔔 New Order Received!',
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _newOrdersChannel.id,
        _newOrdersChannel.name,
        channelDescription: _newOrdersChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        playSound: true,
        sound: _newOrderSound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        color: AppTheme.primaryColor,
        ticker: 'New order available',
        styleInformation: BigTextStyleInformation(body),
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction('accept', 'Accept',
              showsUserInterface: true, cancelNotification: true),
          AndroidNotificationAction('reject', 'Reject',
              showsUserInterface: true, cancelNotification: true),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    ),
    // The full payload rides along, so the tap handler has the order id
    // without needing any stored copy.
    payload: jsonEncode(push.data),
  );
}

/// Must stay top-level / static so the Dart VM can invoke it in the
/// background isolate when a push arrives while the app is killed.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  debugPrint('[FCM] MESSAGE RECEIVED');
  debugPrint('[FCM] messageId = ${message.messageId}');
  debugPrint('[FCM] notification = ${message.notification?.title} / '
      '${message.notification?.body}');
  debugPrint('[FCM] data = ${message.data}');

  // Another partner accepted first — pull the alert down instead of leaving it
  // ringing until its own countdown expires.
  if (message.data['type'] == 'order_taken') {
    final orderId = _orderIdOf(message.data);
    if (orderId != null) await dismissIncomingOrderAlert(orderId);
    return;
  }

  debugPrint('[NEW_ORDER] type = ${message.data['type']}');
  if (message.data['type'] != 'new_order') return;

  final push = NewOrderPush.parse(message.data);
  if (push == null) {
    debugPrint('[NEW_ORDER] orderId = MISSING — push carries no order id, '
        'nothing to show');
    return;
  }
  debugPrint('[NEW_ORDER] orderId = ${push.orderId}');
  debugPrint('[NEW_ORDER] earning = ${push.earning}');

  // Android posts this natively — see NewOrderNotifier. It has to be decided
  // there because that is the only place that knows whether the floating card
  // went up, and posting from here as well is what put a notification on top of
  // the card. iOS still renders the APNs alert the server sends.
  if (Platform.isAndroid) {
    debugPrint('[NEW_ORDER_NOTIFICATION] handled natively — Dart posts nothing');
    return;
  }

  // iOS: the APNs alert the server sends is what the partner sees, and tapping
  // it routes through onMessageOpenedApp. Nothing to post here.
}

/// The backend's FCM_DEFAULT_CHANNEL_ID, used for every push that is NOT a
/// new-order alert (order status updates and the like).
///
/// Those arrive WITH a notification block, so the OS renders them against this id
/// directly. Android silently ignores an unknown channel id and drops back to a
/// low-importance default, so never creating this one left every status update
/// without a heads-up — indistinguishable from the push not arriving at all.
const _highImportanceChannel = AndroidNotificationChannel(
  'high_importance_channel',
  'Order updates',
  description: 'Order status updates and alerts',
  importance: Importance.max,
);

class FcmService {
  FcmService(this._dio, this._tokenStorage);

  final Dio _dio;
  final TokenStorage _tokenStorage;

  final _localNotifications = FlutterLocalNotificationsPlugin();
  final _notificationTapController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationReceivedController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNotificationTap =>
      _notificationTapController.stream;
      
  Stream<Map<String, dynamic>> get onNotificationReceived =>
      _notificationReceivedController.stream;

  static const _channel = AndroidNotificationChannel(
    'orders_channel',
    'Order Updates',
    description: 'New order alerts and delivery status updates',
    importance: Importance.max,
  );

  Future<void> initialize() async {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Must name a resource that actually exists: initialize() throws
    // PlatformException(invalid_icon) otherwise, and everything after it —
    // including createNotificationChannel — never runs, so the new-order
    // channel was never created and its ringtone never played. The icon here
    // is `ic_launcher`; there is no `launcher_icon`.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: backgroundNotificationResponseHandler,
    );

    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(_channel);
      await androidPlugin?.createNotificationChannel(_highImportanceChannel);
      await androidPlugin?.createNotificationChannel(_newOrdersChannel);
      await androidPlugin?.createNotificationChannel(_legacyServerChannel);
      debugPrint('[NOTIFICATION_CHANNEL] id = $_newOrdersChannelId');
      debugPrint('[NOTIFICATION_CHANNEL] importance = HIGH');
      debugPrint('[NOTIFICATION_CHANNEL] sound = neworder_ring.mp4 (alarm usage)');
      debugPrint('[NOTIFICATION_CHANNEL] vibration = enabled');
    }

    await ensureAndroidAlertPermissions();

    final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if ((launchDetails?.didNotificationLaunchApp ?? false) && launchResponse != null) {
      debugPrint('[FCM] NOTIFICATION TAPPED (App Launch): ${launchResponse.payload}');
      _handleNotificationResponse(launchResponse);
    }

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] NOTIFICATION TAPPED (Initial Message): ${initialMessage.data}');
      _handleNotificationOpen(initialMessage);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      debugPrint('[FCM] FCM TOKEN REFRESHED: $token');
      _saveToken(token);
    });
  }

  Future<void> ensureAndroidAlertPermissions() async {
    if (!Platform.isAndroid) return;

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestFullScreenIntentPermission();
  }

  void _handleNotificationResponse(NotificationResponse response) async {
    final payload = response.payload;
    final actionId = response.actionId;
    debugPrint('[FCM] NOTIFICATION TAPPED: payload=$payload, actionId=$actionId');

    if (actionId == 'accept') {
      final orderId = _orderIdFromPayload(payload);
      if (orderId != null) {
        await _respondToOrder(orderId: orderId, accept: true);
        await dismissIncomingOrderAlert(orderId);
      }
      if (payload != null) _handleLocalNotificationPayload(payload);
      return;
    }

    if (actionId == 'reject') {
      final orderId = _orderIdFromPayload(payload);
      if (orderId != null) {
        await _respondToOrder(orderId: orderId, accept: false);
        await dismissIncomingOrderAlert(orderId);
      }
      return;
    }

    if (payload != null) _handleLocalNotificationPayload(payload);
  }

  String? _orderIdFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final id = (decoded['orderMongoId'] ?? decoded['orderId'])?.toString();
        return (id == null || id.isEmpty) ? null : id;
      }
    } catch (_) {}
    return payload;
  }

  Future<void> _respondToOrder({
    required String orderId,
    required bool accept,
  }) async {
    try {
      await _dio.patch(
        accept
            ? ApiEndpoints.orderAccept(orderId)
            : ApiEndpoints.orderReject(orderId),
      );
    } catch (_) {}
  }

  void _handleLocalNotificationPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _notificationTapController.add(Map<String, dynamic>.from(decoded));
        return;
      }
    } catch (_) {}
    _notificationTapController.add({'orderId': payload});
  }


  Future<void> registerToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      debugPrint('[FCM] FCM TOKEN GENERATED: none returned');
      return;
    }
    debugPrint('[FCM] FCM TOKEN GENERATED: $token');
    await _saveToken(token);
  }

  Future<void> _saveToken(String token) async {
    await _tokenStorage.saveFcmToken(token);
    // Not logged in yet: the token goes up with verify-otp, so skip the 401.
    final access = await _tokenStorage.getAccessToken();
    if (access == null || access.isEmpty) return;
    debugPrint('[FCM] FCM TOKEN SENT TO BACKEND: $token');
    try {
      await _dio.post(
        ApiEndpoints.fcmTokenSaveMobile,
        data: {'token': token, 'platform': 'mobile'},
      );
      debugPrint('[FCM] FCM TOKEN SAVED SUCCESSFULLY: $token');
    } catch (e) {
      debugPrint('[FCM] FCM TOKEN SAVE FAILED: $token — $e');
    }
  }

  Future<void> removeToken() async {
    String? token = await _tokenStorage.getFcmToken();
    if (token == null || token.isEmpty) {
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {
        token = null;
      }
    }

    try {
      await _dio.delete(
        ApiEndpoints.fcmTokenRemove,
        data: (token != null && token.isNotEmpty) ? {'token': token} : null,
      );
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  void _showForegroundNotification(RemoteMessage message) {
    offerLog('foreground push type=${message.data['type']} '
        'id=${_orderIdOf(message.data)} display=${message.data['orderDisplayId']}');
    debugPrint('[FCM] FCM MESSAGE RECEIVED: ${message.data}');
    _notificationReceivedController.add(message.data);

    if (message.data['type'] == 'order_taken') {
      final orderId = _orderIdOf(message.data);
      if (orderId != null) {
        _localNotifications.cancel(incomingOrderNotificationId(orderId));
      }
      return;
    }

    if (message.data['type'] == 'new_order') return;
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['orderId'] as String?,
    );
    debugPrint('[FCM] NOTIFICATION DISPLAYED: ${notification.title}');
  }

  void _handleNotificationOpen(RemoteMessage message) {
    offerLog('notification tapped type=${message.data['type']} '
        'id=${_orderIdOf(message.data)}');
    debugPrint('[FCM] NOTIFICATION TAPPED: ${message.data}');
    _notificationTapController.add(message.data);
  }

  void dispose() {
    _notificationTapController.close();
    _notificationReceivedController.close();
  }
}

final fcmServiceProvider = Provider<FcmService>((ref) {
  final service = FcmService(
    ref.read(dioProvider),
    ref.read(tokenStorageProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
