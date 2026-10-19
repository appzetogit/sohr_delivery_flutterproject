import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sohr_delivery_partner/core/presentation/celebration/confetti.dart';
import 'package:sohr_delivery_partner/core/presentation/celebration/delivery_celebration.dart';

/// Opens the celebration the way the trip screen does and settles the burst.
Future<void> _open(
  WidgetTester tester, {
  required double earning,
  String? vertical,
}) async {
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (context, _) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDeliveryCelebration(
                ctx,
                earning: earning,
                vertical: vertical,
                seed: 7,
              ),
              child: const Text('finish'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('finish'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('leads with the earning and names the vertical', (tester) async {
    await _open(tester, earning: 42, vertical: 'food');

    expect(find.text('Delivery complete'), findsOneWidget);
    expect(find.text('You earned ₹42'), findsOneWidget);
    expect(find.text('🍔  FOOD DELIVERY'), findsOneWidget);
  });

  testWidgets('a Mart trip reads as Mart', (tester) async {
    await _open(tester, earning: 15, vertical: 'quick');
    expect(find.text('🛒  MART DELIVERY'), findsOneWidget);
  });

  testWidgets('keeps the paise when the earning is not whole rupees',
      (tester) async {
    await _open(tester, earning: 42.5, vertical: 'food');
    expect(find.text('You earned ₹42.50'), findsOneWidget);
  });

  testWidgets('the burst never eats a tap meant for Continue', (tester) async {
    await _open(tester, earning: 42, vertical: 'food');

    // The confetti is painted full-screen over the card's own area, so without
    // the IgnorePointer the rider would be stuck on the dialog.
    final burst = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is ConfettiPainter,
    );
    expect(burst, findsOneWidget);
    expect(
      find.ancestor(of: burst, matching: find.byType(IgnorePointer)),
      findsWidgets,
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery complete'), findsNothing);
  });

  test('the burst is on screen while it runs, not flung off instantly', () {
    final chips = ConfettiParticle.burst(count: 44, seed: 7);
    int onScreenAt(double t) => chips.where((c) {
          final p = c.positionAt(t);
          return p.dx >= 0 && p.dx <= 1 && p.dy >= 0 && p.dy <= 1;
        }).length;

    // Cannons start on screen; the top cascade is seeded just above the edge
    // and drifts in, so this is a floor rather than the full count.
    expect(onScreenAt(0.0), greaterThanOrEqualTo(33));
    expect(onScreenAt(0.5), greaterThan(20));
  });
}
