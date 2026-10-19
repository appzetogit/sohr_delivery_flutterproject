import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sohr_delivery_partner/features/auth/presentation/screens/registration_screen.dart';

/// Partner registration used to lock the mobile field (`enabled: false`) and
/// paint it from an `initialValue`. When the verified number did not reach the
/// screen — the router redirects here with no `extra`, so it only arrives via
/// auth state — the rider was left staring at a disabled, empty field that the
/// backend then rejected as "must be at least 8 digits", with no way to correct
/// it. The field is now a real controller, seeded from either source.
void main() {
  Widget host(String phone) => ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(home: RegistrationScreen(phone: phone)),
        ),
      );

  Finder phoneField() => find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == '9876543210',
      );

  testWidgets('the verified number is prefilled and stays editable',
      (tester) async {
    await tester.pumpWidget(host('9876543210'));
    await tester.pump();

    expect(phoneField(), findsOneWidget,
        reason: 'the number passed in must reach the field');

    // Editable: a locked field is what left riders stuck.
    final field = tester.widget<TextFormField>(phoneField());
    expect(field.enabled, isNot(false));
  });

  testWidgets('an empty prefill leaves a field the rider can still type into',
      (tester) async {
    await tester.pumpWidget(host(''));
    await tester.pump();

    final blank = find.byWidgetPredicate(
      (w) => w is TextFormField && (w.controller?.text ?? 'x').isEmpty,
    );
    expect(blank, findsWidgets);
    final field = tester.widget<TextFormField>(blank.first);
    expect(field.enabled, isNot(false),
        reason: 'no prefill must not mean no way to enter a number');
  });
}
