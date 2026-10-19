import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants/app_constants.dart';

/// One prefix for every log line on the offer path, so `adb logcat | grep
/// "\[offer\]"` tells the whole story of an incoming order in order.
void offerLog(String message) => debugPrint('[offer] $message');

/// Wraps the Socket.IO connection to the delivery backend and exposes
/// broadcast streams for the events documented in the realtime section
/// of DELIVERY_API_SPEC.md. Polling `/orders/available` remains the
/// required fallback — this is a convenience layer on top, not a
/// replacement for it.
class SocketService {
  io.Socket? _socket;

  final _newOrderController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _orderClaimedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _orderDeassignedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _orderReadyController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _orderStatusUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _locationUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _chatMessageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _chatTypingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  final _orderDeletedController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNewOrderAvailable =>
      _newOrderController.stream;
  Stream<Map<String, dynamic>> get onOrderClaimed =>
      _orderClaimedController.stream;
  Stream<Map<String, dynamic>> get onOrderDeassigned =>
      _orderDeassignedController.stream;
  Stream<Map<String, dynamic>> get onOrderDeleted =>
      _orderDeletedController.stream;
  Stream<Map<String, dynamic>> get onOrderReady => _orderReadyController.stream;
  Stream<Map<String, dynamic>> get onOrderStatusUpdate =>
      _orderStatusUpdateController.stream;
  Stream<Map<String, dynamic>> get onLocationUpdate =>
      _locationUpdateController.stream;
  Stream<Map<String, dynamic>> get onChatMessage =>
      _chatMessageController.stream;
  Stream<Map<String, dynamic>> get onChatTyping =>
      _chatTypingController.stream;
  Stream<bool> get onConnectionChange => _connectionController.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect({required String accessToken, required String partnerId}) {
    disconnect();

    _socket = io.io(
      AppConstants.apiHost,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .enableReconnection()
          .disableAutoConnect()
          .build(),
    );

    final socket = _socket!;

    socket.onConnect((_) {
      _connectionController.add(true);
      socket.emit('join-delivery', partnerId);
    });
    socket.onDisconnect((_) => _connectionController.add(false));
    socket.onConnectError((_) => _connectionController.add(false));

    socket.on(
      'new_order_available',
      (data) => _newOrderController.add(_asMap(data)),
    );
    // Primary dispatch broadcasts use 'new_order'; re-offer rounds use
    // 'new_order_available' — both feed the same incoming-order stream.
    socket.on('new_order', (data) => _newOrderController.add(_asMap(data)));
    socket.on('order_claimed', (data) => _orderClaimedController.add(_asMap(data)));
    socket.on(
      'order_deassigned',
      (data) => _orderDeassignedController.add(_asMap(data)),
    );
    socket.on(
      'order_deleted',
      (data) => _orderDeletedController.add(_asMap(data)),
    );
    socket.on('order_ready', (data) => _orderReadyController.add(_asMap(data)));
    socket.on(
      'order_status_update',
      (data) => _orderStatusUpdateController.add(_asMap(data)),
    );
    socket.on(
      'location-update',
      (data) => _locationUpdateController.add(_asMap(data)),
    );
    socket.on(
      'chat:message',
      (data) => _chatMessageController.add(_asMap(data)),
    );
    socket.on(
      'chat:typing',
      (data) => _chatTypingController.add(_asMap(data)),
    );

    socket.connect();
  }

  void joinTracking(String orderId) => _socket?.emit('join-tracking', orderId);

  void leaveTracking(String orderId) =>
      _socket?.emit('leave-tracking', orderId);

  void sendLocationUpdate({
    required String orderId,
    required double lat,
    required double lng,
    String? userId,
    String? restaurantId,
    double? heading,
    double? speed,
    double? accuracy,
  }) {
    _socket?.emit('update-location', {
      'orderId': orderId,
      'lat': lat,
      'lng': lng,
      if (userId != null) 'userId': userId,
      if (restaurantId != null) 'restaurantId': restaurantId,
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      if (accuracy != null) 'accuracy': accuracy,
    });
  }

  void sendChatTyping({
    required String toRole,
    String? toId,
    required String conversationId,
    required bool typing,
  }) {
    _socket?.emit('chat:typing', {
      'toRole': toRole,
      if (toId != null) 'toId': toId,
      'conversationId': conversationId,
      'typing': typing,
    });
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _newOrderController.close();
    _orderClaimedController.close();
    _orderDeassignedController.close();
    _orderReadyController.close();
    _orderStatusUpdateController.close();
    _locationUpdateController.close();
    _chatMessageController.close();
    _chatTypingController.close();
    _connectionController.close();
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}

final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService();
  ref.onDispose(service.dispose);
  return service;
});
