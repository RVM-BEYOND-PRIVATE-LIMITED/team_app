import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/widgets/team_header.dart';

void main() {
  test('every role shows its human name, never its wire id', () {
    expect(appRoleLabel(AppRole.superAdmin), 'Super Admin');
    expect(appRoleLabelFromWire('super_admin'), 'Super Admin');
    expect(appRoleLabel(AppRole.adminManager), 'Admin Manager');
    expect(appRoleLabel(AppRole.accountsAdmin), 'Accounts Admin');
    expect(appRoleLabel(AppRole.hoo), 'Head of Operations');
    expect(appRoleLabel(AppRole.hrExecutive), 'HR Executive');
  });

  testWidgets('a tab header collapses to a compact title line on scroll',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            TeamCollapsingHeader(
              contentHeight: 140,
              title: 'Test title',
              actions: const [Icon(Icons.refresh_rounded)],
              expanded: const TeamPageHeader(
                title: 'Test title',
                subtitle: Text('Subtitle'),
              ),
            ),
          ],
          body: ListView.builder(
            itemCount: 40,
            itemBuilder: (context, i) => SizedBox(
              height: 60,
              child: Text('row $i'),
            ),
          ),
        ),
      ),
    ));

    expect(find.byType(TeamPageHeader), findsOneWidget);
    expect(find.text('Test title'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.byType(TeamPageHeader), findsNothing);
    expect(find.text('Test title'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
  });
}
