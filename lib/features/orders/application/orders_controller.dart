import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/services/socket_service.dart';
import '../data/models/delivery_order.dart';
import '../data/orders_repository.dart';
import 'incoming_order_controller.dart';
import 'orders_state.dart';
import 'pending_customer_rating_controller.dart';

class OrdersController extends Notifier<OrdersState> {
  late OrdersRepository _repository;
  Timer? _pollTimer;
  StreamSubscription? _newOrderSub;
  StreamSubscription? _orderClaimedSub;
  StreamSubscription? _orderDeassignedSub;
  StreamSubscription? _orderDeletedSub;
  StreamSubscription? _orderStatusSub;
  StreamSubscription? _orderReadySub;
  StreamSubscription? _connectionSub;

  @override
  OrdersState build() {
    _repository = ref.read(ordersRepositoryProvider);

    final socket = ref.read(socketServiceProvider);
    _newOrderSub = socket.onNewOrderAvailable.listen((_) => refreshAvailable());
    _orderClaimedSub = socket.onOrderClaimed.listen((_) => refreshAvailable());
    _orderDeassignedSub = socket.onOrderDeassigned.listen((data) {
      _leaveTrackingIfCurrent(data);
      refreshAvailable();
    });
    _orderDeletedSub = socket.onOrderDeleted.listen((data) {
      _leaveTrackingIfCurrent(data);
      refreshAll();
    });
    _orderStatusSub = socket.onOrderStatusUpdate.listen(
      (_) => refreshCurrent(),
    );
    _orderReadySub = socket.onOrderReady.listen((_) => refreshCurrent());
    // Resume live-location sharing for the active order after a reconnect.
    _connectionSub = socket.onConnectionChange.listen((connected) {
      if (!connected) return;
      final current = state;
      if (current is OrdersLoaded && current.currentOrder != null) {
        socket.joinTracking(current.currentOrder!.id);
        for (final o in current.nextOrders) {
          socket.joinTracking(o.id);
        }
        // Mobile sockets drop: re-read the trip on reconnect.
        refreshAll();
      }
    });

    ref.onDispose(() {
      _pollTimer?.cancel();
      _newOrderSub?.cancel();
      _orderClaimedSub?.cancel();
      _orderDeassignedSub?.cancel();
      _orderDeletedSub?.cancel();
      _orderStatusSub?.cancel();
      _orderReadySub?.cancel();
      _connectionSub?.cancel();
    });

    return const OrdersInitial();
  }

  /// `GET /orders/current` and `GET /orders/available` don't project
  /// `deliveryVerification`, so a routine refresh always reports OTP as
  /// not-required. Never let that silently clear an OTP requirement we
  /// already learned about from reachedDrop/verifyDropOtp responses —
  /// otherwise a background refresh mid-delivery would let the driver
  /// complete the order without ever verifying it.
  DeliveryOrder _preserveOtpState(DeliveryOrder? previousCurrent, DeliveryOrder fresh) {
    if (previousCurrent == null || previousCurrent.id != fresh.id) return fresh;
    if (previousCurrent.dropOtpRequired && !fresh.dropOtpRequired) {
      return fresh.copyWith(
        dropOtpRequired: true,
        dropOtpVerified: previousCurrent.dropOtpVerified,
      );
    }
    return fresh;
  }

  /// On a fresh app start (or provider rebuild) there's no `previousCurrent`
  /// to fall back on, so `_preserveOtpState` can't protect against
  /// `/orders/current`'s stripped `deliveryVerification`. If the order is
  /// already at the drop step in that situation, hydrate the real OTP state
  /// from `GET /orders/:orderId`, which returns the full document.
  Future<DeliveryOrder> _hydrateOtpState(
    DeliveryOrder? previousCurrent,
    DeliveryOrder fresh,
  ) async {
    if (previousCurrent != null && previousCurrent.id == fresh.id) {
      return _preserveOtpState(previousCurrent, fresh);
    }
    if (fresh.currentPhase == 'at_drop') {
      final detailsResult = await _repository.getOrderDetails(fresh.id);
      return detailsResult.when(
        success: (full) => full,
        failure: (_) => fresh,
      );
    }
    return fresh;
  }

  void _leaveTrackingIfCurrent(Map<String, dynamic> data) {
    final current = state;
    if (current is! OrdersLoaded || current.currentOrder == null) return;
    final orderId = (data['orderId'] ?? data['_id'] ?? data['id'])?.toString();
    if (orderId == null || orderId == current.currentOrder!.id) {
      ref.read(socketServiceProvider).leaveTracking(current.currentOrder!.id);
    }
  }

  void startPolling() {
    _pollTimer?.cancel();
    refreshAll();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => refreshAll(),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Splits [orders] into the order in focus and the rest. Focus stays on the
  /// order the rider was already working on while it is still active.
  Future<OrdersLoaded> _applyActive(
    List<DeliveryOrder> orders,
    OrdersState prev,
  ) async {
    final prevCurrent = prev is OrdersLoaded ? prev.currentOrder : null;
    final available = prev is OrdersLoaded ? prev.availableOrders : const <DeliveryOrder>[];
    if (orders.isEmpty) {
      return OrdersLoaded(availableOrders: available, currentOrder: null);
    }
    final focusIndex = prevCurrent == null
        ? 0
        : orders.indexWhere((o) => o.id == prevCurrent.id).clamp(0, orders.length - 1);
    final focus = await _hydrateOtpState(prevCurrent, orders[focusIndex]);
    return OrdersLoaded(
      availableOrders: available,
      currentOrder: focus,
      nextOrders: [
        for (var i = 0; i < orders.length; i++)
          if (i != focusIndex) orders[i],
      ],
    );
  }

  Future<void> refreshAll() async {
    if (state is OrdersInitial) state = const OrdersLoading();
    final currentResult = await _repository.getCurrentOrders();
    final orders = currentResult.when(
      success: (list) => list,
      failure: (_) => <DeliveryOrder>[],
    );

    if (orders.isNotEmpty) {
      final loaded = await _applyActive(orders, state);
      state = loaded;
      final socket = ref.read(socketServiceProvider);
      socket.joinTracking(loaded.currentOrder!.id);
      for (final o in loaded.nextOrders) {
        socket.joinTracking(o.id);
      }
      // A busy rider can still take more orders: keep the offers list fresh.
      final more = await _repository.getAvailableOrders();
      more.when(
        success: (list) {
          final activeIds = {
            loaded.currentOrder!.id,
            ...loaded.nextOrders.map((o) => o.id),
          };
          final waiting = list.where((o) => !activeIds.contains(o.id)).toList();
          final cur = state;
          if (cur is OrdersLoaded) {
            state = cur.copyWith(availableOrders: waiting);
          }
          // Admin assignments the socket/push missed still ring mid-trip.
          final incoming = ref.read(incomingOrderControllerProvider.notifier);
          for (final o in waiting.where((o) => o.assignedByAdmin)) {
            incoming.show(o);
          }
        },
        failure: (_) {},
      );
      return;
    }

    final availableResult = await _repository.getAvailableOrders();
    availableResult.when(
      success: (orders) {
        state = OrdersLoaded(availableOrders: orders, currentOrder: null);
      },
      failure: (error) {
        if (state is! OrdersLoaded) state = OrdersError(error.message);
      },
    );
  }

  Future<void> refreshAvailable() async {
    final prev = state;
    final result = await _repository.getAvailableOrders();
    result.when(
      success: (orders) {
        if (prev is OrdersLoaded && prev.hasActiveOrder) {
          final activeIds = {
            prev.currentOrder!.id,
            ...prev.nextOrders.map((o) => o.id),
          };
          final cur = state;
          if (cur is OrdersLoaded) {
            state = cur.copyWith(
              availableOrders:
                  orders.where((o) => !activeIds.contains(o.id)).toList(),
            );
          }
          return;
        }
        state = OrdersLoaded(availableOrders: orders, currentOrder: null);
      },
      failure: (_) {},
    );
  }

  Future<void> refreshCurrent() async {
    final result = await _repository.getCurrentOrders();
    await result.when(
      success: (orders) async {
        state = await _applyActive(orders, state);
      },
      failure: (_) async {},
    );
  }

  /// Moves the map focus to another accepted order.
  void focusOrder(String orderId) {
    final prev = state;
    if (prev is! OrdersLoaded || prev.currentOrder == null) return;
    final idx = prev.nextOrders.indexWhere((o) => o.id == orderId);
    if (idx < 0) return;
    final picked = prev.nextOrders[idx];
    state = OrdersLoaded(
      availableOrders: prev.availableOrders,
      currentOrder: picked,
      nextOrders: [
        prev.currentOrder!,
        for (var i = 0; i < prev.nextOrders.length; i++)
          if (i != idx) prev.nextOrders[i],
      ],
    );
  }

  Future<Result<DeliveryOrder, AppError>> acceptOrder(String orderId) async {
    final result = await _repository.accept(orderId);
    result.when(
      success: (order) {
        final prev = state;
        // Accepted mid-trip (admin batching): the order in focus stays put.
        if (prev is OrdersLoaded &&
            prev.currentOrder != null &&
            prev.currentOrder!.id != order.id) {
          state = prev.copyWith(
            availableOrders: const [],
            nextOrders: [...prev.nextOrders, order],
          );
        } else {
          state = OrdersLoaded(availableOrders: const [], currentOrder: order);
        }
        // Start live location sharing for this order (requirement: after accept).
        ref.read(socketServiceProvider).joinTracking(order.id);
      },
      failure: (_) {},
    );
    return result;
  }

  Future<Result<DeliveryOrder, AppError>> rejectOrder(String orderId) async {
    final result = await _repository.reject(orderId);
    result.when(success: (_) => refreshAvailable(), failure: (_) {});
    return result;
  }

  Future<Result<DeliveryOrder, AppError>> reachedPickup(String orderId) =>
      _mutateCurrent(() => _repository.reachedPickup(orderId));

  Future<Result<DeliveryOrder, AppError>> confirmPickup(
    String orderId, {
    String? billImageUrl,
  }) => _mutateCurrent(
    () => _repository.confirmPickup(orderId, billImageUrl: billImageUrl),
  );

  Future<Result<DeliveryOrder, AppError>> reachedDrop(String orderId) =>
      _mutateCurrent(() => _repository.reachedDrop(orderId));

  Future<Result<DeliveryOrder, AppError>> completeOrder(
    String orderId, {
    String? deliveryImageUrl,
  }) async {
    final previousOrder =
        state is OrdersLoaded ? (state as OrdersLoaded).currentOrder : null;
    final result =
        await _repository.complete(orderId, deliveryImageUrl: deliveryImageUrl);
    result.when(
      success: (_) {
        // Stop live location sharing for this order (requirement: after delivered).
        ref.read(socketServiceProvider).leaveTracking(orderId);
        final prev = state;
        final rest = prev is OrdersLoaded
            ? [
                if (prev.currentOrder != null && prev.currentOrder!.id != orderId)
                  prev.currentOrder!,
                ...prev.nextOrders.where((o) => o.id != orderId),
              ]
            : <DeliveryOrder>[];
        // Focus moves to the next accepted order, if any.
        state = rest.isEmpty
            ? const OrdersLoaded(availableOrders: [], currentOrder: null)
            : OrdersLoaded(
                availableOrders: const [],
                currentOrder: rest.first,
                nextOrders: rest.skip(1).toList(),
              );
        if (rest.isEmpty) {
          refreshAvailable();
        } else {
          refreshAll(); // pull the next order's real phase/OTP state
        }
        if (previousOrder != null && previousOrder.id == orderId) {
          ref
              .read(pendingCustomerRatingControllerProvider.notifier)
              .show(previousOrder);
        }
      },
      failure: (_) {},
    );
    return result;
  }

  Future<Result<DeliveryOrder, AppError>> _mutateCurrent(
    Future<Result<DeliveryOrder, AppError>> Function() action,
  ) async {
    final result = await action();
    result.when(
      success: (order) {
        final prev = state;
        if (prev is OrdersLoaded &&
            prev.currentOrder != null &&
            prev.currentOrder!.id != order.id &&
            prev.nextOrders.any((o) => o.id == order.id)) {
          state = prev.copyWith(
            nextOrders: [
              for (final o in prev.nextOrders) o.id == order.id ? order : o,
            ],
          );
          return;
        }
        state = OrdersLoaded(
          availableOrders: prev is OrdersLoaded ? prev.availableOrders : const [],
          currentOrder: order,
          nextOrders: prev is OrdersLoaded ? prev.nextOrders : const [],
        );
      },
      failure: (_) {},
    );
    return result;
  }
}

final ordersControllerProvider =
    NotifierProvider<OrdersController, OrdersState>(OrdersController.new);
