import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import 'models/delivery_order.dart';

class OrdersRepository {
  OrdersRepository(this._dio);

  final Dio _dio;

  Future<Result<List<DeliveryOrder>, AppError>> getAvailableOrders({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final res = await _dio.get(
        ApiEndpoints.ordersAvailable,
        queryParameters: {'page': page, 'limit': limit},
      );
      final data = res.data['data'];
      final list = (data is Map<String, dynamic> ? data['data'] : data)
          as List<dynamic>?;
      final orders = (list ?? [])
          .whereType<Map<String, dynamic>>()
          .map(DeliveryOrder.fromJson)
          .toList();
      return Result.success(orders);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  /// Every accepted, unfinished order, most recently updated first. Falls back
  /// to the single `activeOrder` for a backend that predates `activeOrders`.
  Future<Result<List<DeliveryOrder>, AppError>> getCurrentOrders() async {
    try {
      final res = await _dio.get(ApiEndpoints.ordersCurrent);
      final data = res.data['data'] as Map<String, dynamic>?;
      final raw = data?['activeOrders'] ??
          (data?['activeOrder'] != null ? [data!['activeOrder']] : const []);
      final orders = (raw as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(DeliveryOrder.fromJson)
          .toList();
      return Result.success(orders);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<DeliveryOrder, AppError>> getOrderDetails(
    String orderId,
  ) async {
    try {
      final res = await _dio.get(ApiEndpoints.orderDetails(orderId));
      final data = res.data['data'] as Map<String, dynamic>;
      final order = data['order'] ?? data;
      return Result.success(DeliveryOrder.fromJson(order as Map<String, dynamic>));
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<DeliveryOrder, AppError>> accept(String orderId) =>
      _patchOrder(ApiEndpoints.orderAccept(orderId));

  Future<Result<DeliveryOrder, AppError>> reject(String orderId) =>
      _patchOrder(ApiEndpoints.orderReject(orderId));

  Future<Result<DeliveryOrder, AppError>> reachedPickup(String orderId) =>
      _patchOrder(ApiEndpoints.orderReachedPickup(orderId));

  Future<Result<DeliveryOrder, AppError>> confirmPickup(
    String orderId, {
    String? billImageUrl,
  }) => _patchOrder(
    ApiEndpoints.orderConfirmPickup(orderId),
    data: billImageUrl != null ? {'billImageUrl': billImageUrl} : null,
  );

  Future<Result<DeliveryOrder, AppError>> reachedDrop(String orderId) =>
      _patchOrder(ApiEndpoints.orderReachedDrop(orderId));

  Future<Result<DeliveryOrder, AppError>> complete(
    String orderId, {
    String? deliveryImageUrl,
  }) => _patchOrder(
    ApiEndpoints.orderComplete(orderId),
    data: deliveryImageUrl != null ? {'deliveryImageUrl': deliveryImageUrl} : null,
  );

  /// Uploads a proof photo (pickup bill / handover) and returns its URL.
  Future<Result<String, AppError>> uploadProofPhoto(
    String filePath, {
    required String folder,
  }) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.uploadImage,
        queryParameters: {'folder': folder},
        data: FormData.fromMap({'file': await MultipartFile.fromFile(filePath)}),
      );
      final url = (res.data['data'] as Map<String, dynamic>?)?['url'] as String?;
      if (url == null || url.isEmpty) {
        return Result.failure(UnknownError('Photo upload failed. Try again.'));
      }
      return Result.success(url);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<Map<String, dynamic>, AppError>> collectQr(
    String orderId, {
    String? name,
    String? email,
    String? phone,
  }) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.collectQr(orderId),
        data: {
          if (name != null) 'name': name,
          if (email != null) 'email': email,
          if (phone != null) 'phone': phone,
        },
      );
      return Result.success(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<Map<String, dynamic>, AppError>> paymentStatus(
    String orderId,
  ) async {
    try {
      final res = await _dio.get(ApiEndpoints.paymentStatus(orderId));
      return Result.success(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<Map<String, dynamic>, AppError>> getRoute(
    String orderId, {
    required double lat,
    required double lng,
    required String target,
  }) async {
    try {
      final res = await _dio.get(
        ApiEndpoints.orderRoute(orderId),
        queryParameters: {'lat': lat, 'lng': lng, 'target': target},
      );
      return Result.success(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<bool, AppError>> collectCash(String orderId) async {
    try {
      final res = await _dio.post(ApiEndpoints.collectCash(orderId));
      final data = res.data['data'] as Map<String, dynamic>?;
      return Result.success(data?['success'] as bool? ?? true);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<bool, AppError>> rateCustomer(
    String orderId, {
    required int rating,
    String? comment,
  }) async {
    try {
      final res = await _dio.patch(
        ApiEndpoints.orderRateCustomer(orderId),
        data: {
          'rating': rating,
          if (comment != null && comment.isNotEmpty) 'comment': comment,
        },
      );
      return Result.success(res.data['success'] as bool? ?? true);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<DeliveryOrder, AppError>> _patchOrder(
    String path, {
    Object? data,
  }) async {
    try {
      final res = await _dio.patch(path, data: data);
      final body = res.data['data'] as Map<String, dynamic>;
      final order = body['order'] ?? body;
      return Result.success(DeliveryOrder.fromJson(order as Map<String, dynamic>));
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  AppError _mapError(DioException e) {
    final responseData = e.response?.data;
    final message = responseData is Map<String, dynamic>
        ? (responseData['message'] as String? ??
              responseData['error'] as String? ??
              e.message ??
              'Something went wrong')
        : (e.message ?? 'Something went wrong');
    return NetworkError(message);
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return OrdersRepository(ref.read(dioProvider));
});
