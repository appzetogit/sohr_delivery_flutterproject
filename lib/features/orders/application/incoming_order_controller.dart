import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/new_order_overlay_bridge.dart';
import '../../../core/services/order_alert.dart';
import '../../../core/services/socket_service.dart';
import '../data/models/delivery_order.dart';
import '../data/orders_repository.dart';
import 'orders_controller.dart';
import 'orders_state.dart';

/// Single source of truth for the full-screen incoming-order alert.
/// `null` means no active alert; non-null means "show it now" — regardless
/// of whether the order arrived via Socket.IO (app open) or FCM (app
/// backgrounded/foregrounded), both transports funnel into this state.
class IncomingOrderController extends Notifier<DeliveryOrder?> {
  StreamSubscription<Map<String, dynamic>>? _socketSub;
  StreamSubscription<Map<String, dynamic>>? _fcmReceivedSub;
  StreamSubscription<Map<String, dynamic>>? _fcmTapSub;
  StreamSubscription<Map<String, dynamic>>? _orderClaimedSub;
  StreamSubscription<Map<String, dynamic>>? _orderDeassignedSub;
  StreamSubscription<Map<String, dynamic>>? _orderDeletedSub;
  StreamSubscription<Map<String, dynamic>>? _orderStatusSub;

  // Backend keeps re-offering an order to this partner across re-offer
  // rounds even after it's been declined/expired here — track what's
  // already been resolved this session so it isn't shown again.
  final Set<String> _dismissedOrderIds = {};

  @override
  DeliveryOrder? build() {
    final socket = ref.read(socketServiceProvider);
    _socketSub = socket.onNewOrderAvailable.listen(_onRealtimePayload);
    _orderClaimedSub = socket.onOrderClaimed.listen(_autoDismissIfMatch);
    _orderDeassignedSub = socket.onOrderDeassigned.listen(_autoDismissIfMatch);
    // Admin deleted the order from the panel while it was being offered here.
    _orderDeletedSub = socket.onOrderDeleted.listen(_autoDismissIfMatch);
    // A customer cancelling arrives as a status update, not as a claim — so
    // without this the alert kept ringing for an order that no longer existed.
    _orderStatusSub = socket.onOrderStatusUpdate.listen((data) {
      final status = (data['orderStatus'] ?? data['status'])?.toString();
      if (status == 'cancelled' || status == 'canceled') _withdraw(data);
    });

    final fcm = ref.read(fcmServiceProvider);
    _fcmReceivedSub = fcm.onNotificationReceived.listen(_onRealtimePayload);
    _fcmTapSub = fcm.onNotificationTap.listen(_onRealtimePayload);

    ref.onDispose(() {
      _socketSub?.cancel();
      _fcmReceivedSub?.cancel();
      _fcmTapSub?.cancel();
      _orderClaimedSub?.cancel();
      _orderDeassignedSub?.cancel();
      _orderDeletedSub?.cancel();
      _orderStatusSub?.cancel();
    });

    return null;
  }

  void _onRealtimePayload(Map<String, dynamic> data) {
    // FCM data always tags {type: 'new_order'}; non-order push types (e.g.
    // referral_bonus) must be ignored here. Socket order events carry no
    // 'type' field, so absence of the key means "treat as an order".
    // Another rider got there first. Arrives here rather than on the socket
    // stream when the app was backgrounded at the moment of the claim.
    if (data['type'] == 'order_taken') {
      _withdraw(data);
      return;
    }
    if (data['type'] != null && data['type'] != 'new_order') return;
    show(DeliveryOrder.fromRealtimePayload(data));
  }

  void _withdraw(Map<String, dynamic> data) {
    final orderId =
        (data['orderMongoId'] ?? data['orderId'] ?? data['_id'] ?? data['id'])
            ?.toString();
    if (orderId == null || orderId.isEmpty) return;

    // Recorded even when the alert is not currently up. The withdrawal can beat
    // the offer here — FCM makes no ordering guarantee and a queued push is
    // delivered on reconnect — and without this the alert would be raised for an
    // order that is already gone.
    _resolve(orderId);
    if (state?.id == orderId) state = null;
  }

  /// Marks [orderId] finished with, wherever it is showing.
  ///
  /// Every way an offer ends funnels through here — accept, decline, expiry,
  /// and withdrawal — because the alert can be up in three places at once: this
  /// in-app card, the overlay bubble, and the tray/full-screen notification the
  /// background isolate posted. Resolving it in-app used to clear only the
  /// card, leaving the push notification behind; it is posted `ongoing`, so the
  /// partner could not even swipe it away.
  void _resolve(String orderId) {
    offerLog('resolved $orderId');
    _dismissedOrderIds.add(orderId);
    // Unconditional, and deliberately here rather than only in the card's own
    // handlers: this is the single point every ending routes through — accept,
    // decline, expiry, withdrawal, and the overlay hand-off that accepts with
    // no card on screen at all. Once an order is resolved, nothing may still be
    // ringing for it.
    unawaited(OrderAlert.stop(source: 'IncomingOrderController.resolve'));
    unawaited(dismissIncomingOrderAlert(orderId));
  }

  void _autoDismissIfMatch(Map<String, dynamic> data) => _withdraw(data);

  /// Raises the alert, unless this order is already on screen or already
  /// resolved.
  ///
  /// The guard lives here rather than in the transport handler because there
  /// are three ways in — Socket.IO, FCM, and the overlay payload the app
  /// consumes on resume — and only the first two were checked. The same order
  /// arriving over two transports (the normal case: socket and push both fire)
  /// re-entered through this path and restarted the alert, and the resume path
  /// could re-raise an order the rider had already declined.
  void show(DeliveryOrder order) {
    // Each rejection says which one it was. "The push arrived and no alert
    // appeared" has four different causes and they are not distinguishable
    // from the outside.
    if (order.id.isEmpty) {
      offerLog('DROPPED: payload carried no order id');
      return;
    }
    if (_dismissedOrderIds.contains(order.id)) {
      offerLog('DROPPED ${order.id}: already resolved this session');
      return;
    }
    if (state?.id == order.id) {
      offerLog('DROPPED ${order.id}: already on screen');
      return;
    }
    offerLog('SHOWING ${order.id} — ${order.orderCode} '
        'earning=${order.riderEarning} items=${order.items.length}');
    // The in-app card is taking over; the floating one must not linger behind
    // it showing the same offer twice.
    unawaited(NewOrderOverlayBridge.dismiss());
    state = order;
    unawaited(_refreshFromBackend(order.id));
  }

  /// Replaces the push-derived order with the backend's current version.
  ///
  /// The push is a snapshot taken when the offer was made, and it is the only
  /// thing available on a cold start from a notification tap — good enough to
  /// draw the card immediately, but it cannot know that the order was claimed,
  /// cancelled or expired in the seconds since. So the card goes up straight
  /// away and this corrects it: richer detail on success, and the alert
  /// withdrawn entirely if the offer is already gone.
  Future<void> _refreshFromBackend(String orderId) async {
    final result =
        await ref.read(ordersRepositoryProvider).getOrderDetails(orderId);
    if (state?.id != orderId) return; // Resolved or replaced while in flight.

    result.when(
      success: (fresh) {
        const gone = {'cancelled', 'canceled', 'delivered', 'completed'};
        final claimed = fresh.orderStatus.isNotEmpty &&
            gone.contains(fresh.orderStatus.toLowerCase());
        if (claimed) {
          offerLog('WITHDRAWN $orderId: backend says ${fresh.orderStatus}');
          _dismissedOrderIds.add(orderId);
          state = null;
          return;
        }
        offerLog('refreshed $orderId from backend — ${fresh.orderStatus}');
        state = fresh;
      },
      // A failure here is not proof the order is gone — it is far more often
      // a flaky connection on a phone that just woke up. The push-derived card
      // stays up; accept is what finds out for certain.
      failure: (e) => offerLog('refresh failed for $orderId: ${e.message}'),
    );
  }

  /// Accepts the offer on screen.
  ///
  /// Returns the repository result so the caller can report a failure — an
  /// accept that loses the race to another rider must say so, not just make
  /// the alert vanish with no order to show for it.
  Future<Result<DeliveryOrder, AppError>?> accept() async {
    final order = state;
    if (order == null) return null;
    _resolve(order.id);
    // Don't clear state yet — IncomingOrderScreen keeps its loader up until
    // the API actually comes back.
    final result = await ref
        .read(ordersControllerProvider.notifier)
        .acceptOrder(order.id);

    // On success ordersController immediately raises ActiveTripScreen, so
    // dropping the alert here is a seamless handover.
    state = null;
    return result;
  }

  Future<void> decline() async {
    final order = state;
    if (order == null) return;
    _resolve(order.id);
    state = null;
    await ref.read(ordersControllerProvider.notifier).rejectOrder(order.id);
  }

  /// Countdown ran out client-side — best-effort notify the backend so it
  /// can reassign sooner. The BullMQ `processDispatchTimeout` job remains
  /// the authoritative fallback if this call never arrives.
  Future<void> expire() => decline();

  void dismiss() {
    state = null;
  }

  /// Raises the alert for an order the partner tapped on the native overlay.
  ///
  /// Only the id crosses over, so the order is fetched fresh — which is the
  /// right thing anyway: by the time they tap, the offer may already be gone.
  Future<void> showById(String orderId, {bool autoAccept = false}) async {
    if (_dismissedOrderIds.contains(orderId)) return;

    // ACCEPT on the overlay is the decision, not a request to be asked again.
    //
    // This used to raise the card and then accept behind it, so the partner
    // watched their own Accept button reappear for a beat — and on a slow
    // network, long enough to tap it twice. The order goes straight to the
    // accept call and the trip screen comes up from ordersController; the card
    // is never built.
    if (autoAccept) {
      offerLog('accepting $orderId from the overlay — skipping the card');
      _resolve(orderId);
      // Clearing state is what actually removes the second Accept prompt.
      //
      // _resolve only records the id, and the card is very often ALREADY up by
      // the time this runs: launching the app reconnects the socket, which
      // re-delivers the same offer and raises the alert before the handoff from
      // the overlay has been read. Marking the order resolved stops it being
      // raised again but does nothing about the copy already on screen — so the
      // partner accepted on the overlay and was then shown the card anyway.
      state = null;
      final result =
          await ref.read(ordersControllerProvider.notifier).acceptOrder(orderId);
      result.when(
        success: (order) => offerLog('accepted $orderId — ${order.currentPhase}'),
        // Almost always "another partner got there first". The alert is already
        // gone; refreshing the list is what puts the partner back on solid
        // ground rather than staring at a trip that never started.
        failure: (e) {
          offerLog('accept from overlay failed for $orderId: ${e.message}');
          ref.read(ordersControllerProvider.notifier).refreshAvailable();
        },
      );
      return;
    }

    final result =
        await ref.read(ordersRepositoryProvider).getOrderDetails(orderId);
    result.when(
      success: show,
      failure: (e) => offerLog('showById($orderId) failed: ${e.message}'),
    );
  }

  /// Reports rejections the partner made on the overlay while the app was not
  /// running. Best effort — the server's dispatch timeout covers any that fail.
  Future<void> flushOverlayRejections() async {
    final pending = await NewOrderOverlayBridge.takePendingRejections();
    for (final orderId in pending) {
      offerLog('flushing overlay rejection for $orderId');
      _dismissedOrderIds.add(orderId);
      await ref.read(ordersControllerProvider.notifier).rejectOrder(orderId);
    }
  }
}

final incomingOrderControllerProvider =
    NotifierProvider<IncomingOrderController, DeliveryOrder?>(
  IncomingOrderController.new,
);
