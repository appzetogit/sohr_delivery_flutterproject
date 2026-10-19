import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/incentives_controller.dart';
import '../../data/models/incentive_offer.dart';
import '../widgets/incentive_award_tile.dart';
import '../widgets/incentive_offer_card.dart';
import '../widgets/incentive_progress_ring.dart';

class IncentivesScreen extends ConsumerWidget {
  const IncentivesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    final state = ref.watch(incentivesControllerProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Incentives')),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => ref.read(incentivesControllerProvider.notifier).refresh(),
        child: state.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (e, _) => _Message(
            icon: Icons.wifi_off_rounded,
            title: 'Could not load incentives',
            body: 'Pull down to try again.',
          ),
          data: (offers) => offers.isEmpty
              ? const _Message(
                  icon: Icons.emoji_events_outlined,
                  title: 'No incentives running',
                  body:
                      'When a new earning offer starts, it will show up here. '
                      'Keep delivering!',
                )
              : _Content(offers: offers),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.offers});

  final List<IncentiveOffer> offers;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hero = offers.first;
    final rest = offers.skip(1).toList();

    // Every award across every offer, newest first -- the rider thinks in
    // "what have I earned", not "which offer paid it".
    final awards = <({IncentiveAward award, String title})>[
      for (final o in offers)
        for (final a in o.awards) (award: a, title: o.title),
    ]..sort((a, b) => (b.award.completedAt ?? '').compareTo(a.award.completedAt ?? ''));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _HeroCard(offer: hero),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionTitle('More offers'),
          const SizedBox(height: 10),
          for (final o in rest) ...[
            IncentiveOfferCard(offer: o),
            const SizedBox(height: 10),
          ],
        ],
        if (awards.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionTitle('You have earned'),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < awards.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: c.border),
                  IncentiveAwardTile(
                    award: awards[i].award,
                    offerTitle: awards[i].title,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The offer the rider is closest to finishing, given the full-width treatment.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.offer});

  final IncentiveOffer offer;

  @override
  Widget build(BuildContext context) {
    final target = offer.activeTarget;
    final remaining = offer.remainingOrders;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            offer.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.onPrimary,
            ),
          ),
          const SizedBox(height: 18),

          // The ring sits on a light plate: a purple ring on a purple card has
          // nowhere near enough contrast to read at a glance.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.onPrimary,
              shape: BoxShape.circle,
            ),
            child: IncentiveProgressRing(
              progress: offer.progress,
              current: offer.currentOrders,
              target: target,
            ),
          ),

          const SizedBox(height: 18),
          Text(
            '₹${offer.targetAmount.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1,
              color: AppColors.onPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            offer.isComplete
                ? 'Unlocked — check "You have earned" below'
                : remaining == 1
                ? 'Just 1 more delivery to unlock'
                : '$remaining more deliveries to unlock',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.onPrimary.withValues(alpha: 0.92),
            ),
          ),
          if (offer.repeatable && offer.cyclesEarned > 0) ...[
            const SizedBox(height: 12),
            _HeroPill(
              icon: Icons.replay_rounded,
              label: offer.cyclesEarned == 1
                  ? 'Earned once already'
                  : 'Earned ${offer.cyclesEarned} times already',
            ),
          ],
          if (offer.isUrgent) ...[
            const SizedBox(height: 8),
            _HeroPill(
              icon: Icons.schedule_rounded,
              label: _urgencyLabel(offer),
            ),
          ],
        ],
      ),
    );
  }

  static String _urgencyLabel(IncentiveOffer offer) {
    final days = offer.daysLeft;
    if (days != null && days <= 2) {
      return days <= 0 ? 'Ends today' : 'Ends in $days day${days == 1 ? '' : 's'}';
    }
    return 'Only ${offer.remainingRedemptions} left';
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.onPrimary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.onPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.of(context).textPrimary,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // Inside a ListView so pull-to-refresh still works with nothing to show.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
        Icon(icon, size: 56, color: c.textSecondary),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}
