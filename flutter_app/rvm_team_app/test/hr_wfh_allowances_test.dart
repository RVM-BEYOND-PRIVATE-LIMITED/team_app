import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/hr/bloc/wfh_allowances_bloc.dart';
import 'package:rvm_team_app/features/hr/hr_wfh_allowances_screen.dart';
import 'package:rvm_team_app/injection.dart';

/// KP's WFH allowances (`GET/PUT /hr/wfh-allowances`, 22 Oct) had no Flutter
/// screen. This holds the screen to the endpoint: list, switch, save.
class _MockEssRepository extends Mock implements EssRepository {}

const _employee = OrgCard(
  id: 'e1',
  fullName: 'Suresh Yadav',
  employeeCode: 'RVM-0217',
  branch: BranchRef(id: 'b1', name: 'Faridabad'),
  department: BranchRef(id: 'd1', name: 'Technical Training'),
  noticePeriod: false,
);

const _allowance = HrWfhAllowance(
  employeeId: 'e1',
  employee: _employee,
  enabled: true,
  monthlyLimitDays: 4,
);

const _page = HrWfhAllowancePage(rows: [_allowance], truncated: false);

void main() {
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  testWidgets('lists the allowances and saves a switch-off', (tester) async {
    final repo = _MockEssRepository();
    when(() => repo.wfhAllowances(query: any(named: 'query')))
        .thenAnswer((_) async => _page);
    when(() => repo.setWfhAllowance(
          employeeId: any(named: 'employeeId'),
          enabled: any(named: 'enabled'),
          monthlyLimitDays: any(named: 'monthlyLimitDays'),
          note: any(named: 'note'),
        )).thenAnswer((_) async => _allowance);
    getIt.registerFactory<WfhAllowancesBloc>(() => WfhAllowancesBloc(repo));

    await tester.pumpWidget(const MaterialApp(home: HrWfhAllowancesScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('WFH allowances'), findsOneWidget);
    expect(find.text('Suresh Yadav'), findsOneWidget);
    expect(find.text('WFH on'), findsOneWidget);
    expect(find.text('4 days/month'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    verify(() => repo.setWfhAllowance(
          employeeId: 'e1',
          enabled: false,
          monthlyLimitDays: 4,
          note: null,
        )).called(1);
  });

  testWidgets('the card opens the editor with the day count', (tester) async {
    final repo = _MockEssRepository();
    when(() => repo.wfhAllowances(query: any(named: 'query')))
        .thenAnswer((_) async => _page);
    getIt.registerFactory<WfhAllowancesBloc>(() => WfhAllowancesBloc(repo));

    await tester.pumpWidget(const MaterialApp(home: HrWfhAllowancesScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suresh Yadav'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Work from home · Suresh Yadav'), findsOneWidget);
    expect(find.text('Days a month'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Save allowance'), findsOneWidget);
    expect(find.text('Work from home enabled'), findsOneWidget);
  });

  test('parses the allowance list exactly as the contract documents it', () {
    final page = HrWfhAllowancePage.fromJson(const {
      'allowances': [
        {
          'employee_id': 'e1',
          'employee': {
            'id': 'e1',
            'full_name': 'Suresh Yadav',
            'employee_code': 'RVM-0217',
            'branch': {'id': 'b1', 'name': 'Faridabad'},
            'department': {'id': 'd1', 'name': 'Technical Training'},
          },
          'enabled': true,
          'monthly_limit_days': 4,
          'note': 'Two days a week while the centre is painted.',
          'set_by_name': 'Priya Sharma',
          'updated_at': '2026-10-22T06:30:00+00:00',
        }
      ],
      'truncated': false,
    });
    expect(page.rows, hasLength(1));
    final row = page.rows.single;
    expect(row.employeeId, 'e1');
    expect(row.employee.fullName, 'Suresh Yadav');
    expect(row.enabled, isTrue);
    expect(row.monthlyLimitDays, 4);
    expect(row.note, contains('Two days a week'));
    expect(row.setByName, 'Priya Sharma');
    expect(page.truncated, isFalse);
  });
}
