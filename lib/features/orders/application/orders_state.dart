import '../data/models/delivery_order.dart';

sealed class OrdersState {
  const OrdersState();
}

class OrdersInitial extends OrdersState {
  const OrdersInitial();
}

class OrdersLoading extends OrdersState {
  const OrdersLoading();
}

class OrdersLoaded extends OrdersState {
  const OrdersLoaded({
    required this.availableOrders,
    required this.currentOrder,
    this.nextOrders = const [],
  });

  final List<DeliveryOrder> availableOrders;

  /// The order in focus on the map.
  final DeliveryOrder? currentOrder;

  /// Other accepted, unfinished orders (admin batching) — "Next deliveries".
  final List<DeliveryOrder> nextOrders;

  bool get hasActiveOrder => currentOrder != null;

  OrdersLoaded copyWith({
    List<DeliveryOrder>? availableOrders,
    DeliveryOrder? Function()? currentOrder,
    List<DeliveryOrder>? nextOrders,
  }) {
    return OrdersLoaded(
      availableOrders: availableOrders ?? this.availableOrders,
      currentOrder: currentOrder != null ? currentOrder() : this.currentOrder,
      nextOrders: nextOrders ?? this.nextOrders,
    );
  }
}

class OrdersError extends OrdersState {
  const OrdersError(this.message);
  final String message;
}
