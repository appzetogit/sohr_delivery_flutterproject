import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../data/incentives_repository.dart';
import '../data/models/incentive_offer.dart';

/// Live incentive offers for the signed-in rider.
///
/// Mirrors ReferralController: an AsyncNotifier the screen watches, with an
/// explicit refresh for pull-to-refresh and for the push that arrives when an
/// incentive is unlocked.
class IncentivesController extends AsyncNotifier<List<IncentiveOffer>> {
  @override
  Future<List<IncentiveOffer>> build() => _fetch();

  Future<List<IncentiveOffer>> _fetch() async {
    final repo = ref.read(incentivesRepositoryProvider);
    final result = await repo.getActiveOffers();
    return result.when(
      success: (offers) => offers,
      failure: (err) => throw Exception(err.message),
    );
  }

  /// Refresh without tearing the list down.
  ///
  /// Deliberately does NOT set AsyncLoading first, unlike ReferralController:
  /// the rider reaches this straight off a completed delivery, and blanking the
  /// progress they just moved -- only to redraw it a moment later -- reads as a
  /// glitch. The previous value stays on screen while this runs.
  Future<void> refresh() async {
    try {
      state = AsyncData(await _fetch());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final incentivesControllerProvider =
    AsyncNotifierProvider<IncentivesController, List<IncentiveOffer>>(
      () => IncentivesController(),
    );

/// The single offer worth surfacing outside this feature -- on the Pocket
/// screen's entry card. Closest to payout, because that is the one that will
/// make a rider tap through.
///
/// Uses `asData` rather than `valueOrNull` so an error or loading state simply
/// yields null and the entry card draws nothing, rather than the Pocket screen
/// inheriting this feature's failure.
final headlineIncentiveProvider = Provider<IncentiveOffer?>((ref) {
  final offers = ref.watch(incentivesControllerProvider).asData?.value;
  if (offers == null || offers.isEmpty) return null;
  return offers.first;
});
