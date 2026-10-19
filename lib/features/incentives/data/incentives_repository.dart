import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import 'models/incentive_offer.dart';

/// Reads the rider's live incentive offers.
///
/// The equivalent method on WalletRepository unwrapped the response as a list.
/// The endpoint returns an object -- `{ activeOffer, offers }` -- so that check
/// never matched and it always handed back an empty list. Nothing called it, so
/// the bug sat there unnoticed; this reads `offers` off the object instead.
class IncentivesRepository {
  IncentivesRepository(this._dio);

  final Dio _dio;

  Future<Result<List<IncentiveOffer>, AppError>> getActiveOffers() async {
    try {
      final res = await _dio.get(ApiEndpoints.earningAddonsActive);
      final data = res.data['data'];
      final raw = data is Map<String, dynamic> ? data['offers'] : null;
      final list = raw is List<dynamic> ? raw : const <dynamic>[];

      final offers = list
          .whereType<Map<String, dynamic>>()
          .map(IncentiveOffer.fromJson)
          .toList();

      // Closest to payout first, so the hero card is the one the rider can
      // actually finish today. Completed-but-unpaid cycles sort ahead of
      // everything -- that is the card they are looking for.
      offers.sort((a, b) {
        if (a.isComplete != b.isComplete) return a.isComplete ? -1 : 1;
        return b.progress.compareTo(a.progress);
      });

      return Result.success(offers);
    } on DioException catch (e) {
      final responseData = e.response?.data;
      final message = responseData is Map<String, dynamic>
          ? (responseData['message'] as String? ??
                responseData['error'] as String? ??
                e.message ??
                'Could not load incentives')
          : (e.message ?? 'Could not load incentives');
      return Result.failure(NetworkError(message));
    } catch (e) {
      return Result.failure(UnknownError(e.toString()));
    }
  }
}

final incentivesRepositoryProvider = Provider<IncentivesRepository>((ref) {
  return IncentivesRepository(ref.read(dioProvider));
});
