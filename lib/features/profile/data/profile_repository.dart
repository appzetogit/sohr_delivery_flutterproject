import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/data/models/delivery_partner.dart';

class ProfileRepository {
  ProfileRepository(this._dio);

  final Dio _dio;

  Future<Result<DeliveryPartner, AppError>> updateProfile(
    Map<String, dynamic> fields,
  ) => _patch(ApiEndpoints.profile, fields);

  Future<Result<DeliveryPartner, AppError>> updateProfileDetails(
    Map<String, dynamic> fields,
  ) => _patch(ApiEndpoints.profileDetails, fields);

  Future<Result<DeliveryPartner, AppError>> updateBankDetails({
    required String accountHolderName,
    required String accountNumber,
    required String ifscCode,
    required String bankName,
    String? upiId,
  }) => _patch(ApiEndpoints.profileBankDetails, {
    // The backend only reads `documents.bankDetails.*`; flat keys are ignored.
    'documents': {
      'bankDetails': {
        'accountHolderName': accountHolderName,
        'accountNumber': accountNumber,
        'ifscCode': ifscCode,
        'bankName': bankName,
        if (upiId != null) 'upiId': upiId,
      },
    },
  });

  Future<Result<DeliveryPartner, AppError>> uploadProfilePhotoBase64(
    String base64Image,
  ) => _patch(ApiEndpoints.profilePhotoBase64, {'photo': base64Image});

  /// Same endpoint as [updateBankDetails], but the QR file is handled by the
  /// backend independently of the bank text fields -- so it's fine to send
  /// just this one field without touching the rest of the bank details.
  Future<Result<DeliveryPartner, AppError>> uploadUpiQr(File qrImage) async {
    try {
      final formData = FormData.fromMap({
        'upiQrCode': await MultipartFile.fromFile(qrImage.path),
      });
      final res = await _dio.patch(ApiEndpoints.profileBankDetails, data: formData);
      final body = res.data['data'] as Map<String, dynamic>;
      final user = body['user'] ?? body;
      return Result.success(DeliveryPartner.fromJson(user as Map<String, dynamic>));
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  /// Sets availability and reports back what the server actually decided.
  ///
  /// Not [_patch]: going online can be *refused* when the wallet balance is
  /// under the admin's minimum, and the refusal comes back as a normal 200 with
  /// `availabilityStatus: 'offline'` plus a reason. [_patch] would throw that
  /// reason away and the app would keep showing a rider as online while the
  /// backend has them offline and out of dispatch.
  Future<Result<AvailabilityUpdate, AppError>> updateAvailability(
    bool isOnline, {
    double? lat,
    double? lng,
  }) async {
    try {
      final res = await _dio.patch(ApiEndpoints.availability, data: {
        'status': isOnline ? 'online' : 'offline',
        // Backend reads `latitude`/`longitude` (DELIVERY_API_SPEC.md §3) — `lat`/`lng`
        // are silently ignored, leaving lastLat/lastLng unset and the partner
        // invisible to dispatch's nearby-partner radius search.
        if (lat != null) 'latitude': lat,
        if (lng != null) 'longitude': lng,
      });
      final body = (res.data['data'] as Map<String, dynamic>?) ?? const {};
      return Result.success(
        AvailabilityUpdate(
          isOnline: body['availabilityStatus'] == 'online',
          blockedMessage: body['walletBlocked'] == true
              ? body['message'] as String?
              : null,
        ),
      );
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<void, AppError>> deleteAccount() async {
    try {
      await _dio.delete(ApiEndpoints.deleteAccount);
      return const Result.success(null);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<DeliveryPartner, AppError>> reverify(
    FormData formData,
  ) async {
    try {
      final res = await _dio.post(ApiEndpoints.reverify, data: formData);
      final data = res.data['data'] as Map<String, dynamic>;
      return Result.success(DeliveryPartner.fromJson(data));
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<DeliveryPartner, AppError>> _patch(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final res = await _dio.patch(path, data: data);
      final body = res.data['data'] as Map<String, dynamic>;
      final user = body['user'] ?? body;
      return Result.success(DeliveryPartner.fromJson(user as Map<String, dynamic>));
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

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.read(dioProvider));
});

/// What the server did with an availability request.
///
/// [isOnline] is the server's answer, not what was asked for — the wallet-floor
/// rule can send back `false` for a request to go online. [blockedMessage] is
/// set only in that case, and already carries the admin-configured threshold,
/// so nothing in the app needs to know the amount.
class AvailabilityUpdate {
  const AvailabilityUpdate({required this.isOnline, this.blockedMessage});

  final bool isOnline;
  final String? blockedMessage;

  bool get walletBlocked => blockedMessage != null;
}
