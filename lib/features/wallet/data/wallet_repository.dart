import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

class WalletRepository {
  WalletRepository(this._dio);

  final Dio _dio;

  Future<Result<Map<String, dynamic>, AppError>> getWallet() =>
      _get(ApiEndpoints.wallet);

  Future<Result<Map<String, dynamic>, AppError>> withdraw(double amount) =>
      _post(ApiEndpoints.walletWithdraw, {'amount': amount});

  /// [type] is `cod_deposit` (handing over collected COD cash, capped at
  /// cash-in-hand by the server) or `wallet_topup` (the rider's own money going
  /// onto their balance, uncapped).
  Future<Result<Map<String, dynamic>, AppError>> createDepositOrder(
    double amount, {
    String type = 'cod_deposit',
  }) => _post(ApiEndpoints.walletDepositOrder, {'amount': amount, 'type': type});

  Future<Result<Map<String, dynamic>, AppError>> verifyDeposit({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    required double amount,
    String type = 'cod_deposit',
  }) => _post(ApiEndpoints.walletDepositVerify, {
    'razorpay_order_id': razorpayOrderId,
    'razorpay_payment_id': razorpayPaymentId,
    'razorpay_signature': razorpaySignature,
    'amount': amount,
    'type': type,
  });

  Future<Result<Map<String, dynamic>, AppError>> getEarnings({
    String? period,
  }) => _get(
    ApiEndpoints.earnings,
    query: period != null ? {'period': period} : null,
  );

  Future<Result<Map<String, dynamic>, AppError>> getTripHistory({
    String period = 'daily',
    String? date,
    String? status,
    int limit = 50,
  }) => _get(
    ApiEndpoints.tripHistory,
    query: {
      'period': period,
      if (date != null) 'date': date,
      if (status != null) 'status': status,
      'limit': limit,
    },
  );

  Future<Result<Map<String, dynamic>, AppError>> getPocketDetails() =>
      _get(ApiEndpoints.pocketDetails);

  Future<Result<Map<String, dynamic>, AppError>> getCashLimit() =>
      _get(ApiEndpoints.cashLimit);

  Future<Result<Map<String, dynamic>, AppError>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      return Result.success(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<Map<String, dynamic>, AppError>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final res = await _dio.post(path, data: data);
      return Result.success(res.data['data'] as Map<String, dynamic>);
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

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return WalletRepository(ref.read(dioProvider));
});
