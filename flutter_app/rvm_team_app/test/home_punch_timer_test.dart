import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/features/home/home_screen.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 320, child: child),
        ),
      ),
    );

void main() {
  testWidgets('on-duty timer lives inside the Punch Out button',
      (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(_host(HomePunchButton(
      onDuty: true,
      busy: false,
      lastPunchAt: now.subtract(const Duration(minutes: 10)),
      onDutySince: now.subtract(const Duration(minutes: 28, seconds: 30)),
      onPressed: () {},
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Punch Out'), findsOneWidget);
    expect(find.text('28:30'), findsOneWidget);
    expect(find.textContaining('On duty for'), findsNothing);
  });

  testWidgets('the on-duty clock stays in the button during cooldown',
      (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(_host(HomePunchButton(
      onDuty: true,
      busy: false,
      lastPunchAt: now,
      onDutySince: now.subtract(const Duration(minutes: 28, seconds: 30)),
      onPressed: () {},
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Punch Out in'), findsOneWidget);
    expect(find.text('28:30'), findsOneWidget);
  });

  testWidgets('off duty shows only the action label', (tester) async {
    await tester.pumpWidget(_host(HomePunchButton(
      onDuty: false,
      busy: false,
      lastPunchAt: DateTime.now().subtract(const Duration(minutes: 10)),
      onDutySince: null,
      onPressed: () {},
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Punch In'), findsOneWidget);
    expect(find.textContaining('On duty'), findsNothing);
  });
}
