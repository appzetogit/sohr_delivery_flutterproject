/// Incentive models.
///
/// Hand-written rather than freezed, unlike the neighbouring refer_earn models.
/// These are read-only DTOs with no copyWith or equality requirements, so
/// codegen buys little here, and keeping them plain means the feature builds
/// without a build_runner step standing between a checkout and an APK.

int _asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
num _asNum(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
String _asString(dynamic v) => v == null ? '' : '$v';

/// One payout the rider has already been granted on an offer.
///
/// `status` is the whole point of showing these: a `credited` row is money
/// already in the wallet, a `pending` one is waiting on an admin to release it.
/// Without the distinction the rider hits the target, sees nothing move, and
/// assumes the incentive is broken.
class IncentiveAward {
  const IncentiveAward({
    this.cycle = 0,
    this.amount = 0,
    this.status = 'pending',
    this.completedAt,
    this.creditedAt,
  });

  factory IncentiveAward.fromJson(Map<String, dynamic> json) => IncentiveAward(
    cycle: _asInt(json['cycle']),
    amount: _asNum(json['amount']),
    status: _asString(json['status']).isEmpty
        ? 'pending'
        : _asString(json['status']),
    completedAt: json['completedAt'] as String?,
    creditedAt: json['creditedAt'] as String?,
  );

  final int cycle;
  final num amount;
  final String status;
  final String? completedAt;
  final String? creditedAt;
}

class IncentiveOffer {
  const IncentiveOffer({
    this.id = '',
    this.title = '',
    this.description = '',
    this.targetAmount = 0,
    this.targetOrders = 0,
    this.currentOrders = 0,
    this.currentEarnings = 0,
    this.repeatable = false,
    this.cyclesEarned = 0,
    this.nextTargetOrders = 0,
    this.remainingRedemptions,
    this.awards = const <IncentiveAward>[],
    this.totalAwarded = 0,
    this.pendingAmount = 0,
    this.validTill,
    this.isLive = true,
  });

  factory IncentiveOffer.fromJson(Map<String, dynamic> json) {
    final rawAwards = json['awards'];
    return IncentiveOffer(
      id: _asString(json['id']),
      title: _asString(json['title']),
      description: _asString(json['description']),
      targetAmount: _asNum(json['targetAmount']),
      targetOrders: _asInt(json['targetOrders']),
      currentOrders: _asInt(json['currentOrders']),
      currentEarnings: _asNum(json['currentEarnings']),
      repeatable: json['repeatable'] == true,
      cyclesEarned: _asInt(json['cyclesEarned']),
      nextTargetOrders: _asInt(json['nextTargetOrders']),
      // Null is meaningful: uncapped, as opposed to a cap of zero.
      remainingRedemptions: json['remainingRedemptions'] == null
          ? null
          : _asInt(json['remainingRedemptions']),
      awards: rawAwards is List
          ? rawAwards
                .whereType<Map<String, dynamic>>()
                .map(IncentiveAward.fromJson)
                .toList()
          : const <IncentiveAward>[],
      totalAwarded: _asNum(json['totalAwarded']),
      pendingAmount: _asNum(json['pendingAmount']),
      validTill: json['validTill'] as String?,
      isLive: json['isLive'] != false,
    );
  }

  final String id;
  final String title;
  final String description;

  /// Reward for completing one cycle of [targetOrders] deliveries.
  final num targetAmount;
  final int targetOrders;
  final int currentOrders;
  final num currentEarnings;

  /// Pays again on every further multiple of [targetOrders].
  final bool repeatable;

  /// How many cycles this rider has already been granted.
  final int cyclesEarned;

  /// The delivery count the rider is working towards *now*. For a repeatable
  /// offer this moves to the next multiple once a cycle is banked, so the bar
  /// does not sit full forever.
  final int nextTargetOrders;

  /// Null means uncapped. A small number is worth surfacing as scarcity.
  final int? remainingRedemptions;

  final List<IncentiveAward> awards;
  final num totalAwarded;
  final num pendingAmount;
  final String? validTill;
  final bool isLive;

  /// The bar being worked towards, falling back to the base target when the
  /// server predates the `nextTargetOrders` field.
  int get activeTarget => nextTargetOrders > 0 ? nextTargetOrders : targetOrders;

  /// Deliveries still needed for the current cycle. Never negative.
  int get remainingOrders =>
      activeTarget <= 0 ? 0 : (activeTarget - currentOrders).clamp(0, activeTarget).toInt();

  /// Progress through the CURRENT cycle only, 0..1.
  ///
  /// Measured from the start of this cycle rather than from zero: on a
  /// repeatable offer at 12 of a 5-delivery target, the rider is 2/5 of the way
  /// to the next reward, not 12/15 of anything.
  double get progress {
    if (activeTarget <= 0 || targetOrders <= 0) return 0;
    final cycleStart = activeTarget - targetOrders;
    final done = (currentOrders - cycleStart).clamp(0, targetOrders).toDouble();
    return done / targetOrders;
  }

  bool get isComplete => activeTarget > 0 && remainingOrders == 0;

  /// Whole days left, or null when the offer has no end date.
  int? get daysLeft {
    final raw = validTill;
    if (raw == null) return null;
    final end = DateTime.tryParse(raw);
    if (end == null) return null;
    final diff = end.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inDays;
  }

  /// Worth nudging the rider about — either time or stock is running out.
  bool get isUrgent {
    final d = daysLeft;
    if (d != null && d <= 2) return true;
    final left = remainingRedemptions;
    return left != null && left > 0 && left <= 5;
  }
}
