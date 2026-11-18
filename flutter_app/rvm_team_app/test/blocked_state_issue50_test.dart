import 'package:core_ui/core_ui.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/startup/version_gate.dart';
import 'package:rvm_team_app/injection.dart';
import 'package:rvm_team_app/widgets/blocked_state.dart';

/// team_app #50, item 12: one blocked screen for module off, pilot only, not
/// punched in and update required, used by the existing version gate.
class _MockTeamAuthBloc extends Mock implements TeamAuthBloc {}

class _MockEssRepository extends Mock implements EssRepository {}

Widget _host(Widget child, {Size size = const Size(390, 844)}) => MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: RvmTheme.light(seed: RvmColors.clay),
        home: child,
      ),
    );

void main() {
  group('BlockedState', () {
    testWidgets('each reason has its own icon, title and message',
        (tester) async {
      for (final reason in BlockedReason.values) {
        await tester.pumpWidget(_host(BlockedState(reason: reason)));
        expect(find.byIcon(reason.icon), findsOneWidget, reason: '$reason');
        expect(find.text(reason.title), findsOneWidget, reason: '$reason');
        expect(find.text(reason.message), findsOneWidget, reason: '$reason');
        expect(find.byType(FilledButton), findsNothing, reason: '$reason');
      }
      expect({for (final r in BlockedReason.values) r.title},
          hasLength(BlockedReason.values.length));
    });

    testWidgets('takes its own message and one action', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(BlockedState(
        reason: BlockedReason.notPunchedIn,
        message: 'Punch in at your branch to open this.',
        actionLabel: 'Punch in',
        actionIcon: Icons.fingerprint,
        onAction: () => taps++,
      )));
      expect(
          find.text('Punch in at your branch to open this.'), findsOneWidget);
      expect(find.text(BlockedReason.notPunchedIn.message), findsNothing);
      await tester.tap(find.text('Punch in'));
      expect(taps, 1);
    });

    testWidgets('an action without a handler shows disabled', (tester) async {
      await tester.pumpWidget(_host(const BlockedState(
        reason: BlockedReason.moduleOff,
        actionLabel: 'Check again',
      )));
      final button = tester.widget<ButtonStyleButton>(find.ancestor(
          of: find.text('Check again'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
      expect(button.onPressed, isNull);
    });

    testWidgets('fits a small phone with very large text', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 480), textScaler: TextScaler.linear(2.5)),
        child: MaterialApp(
          theme: RvmTheme.light(seed: RvmColors.clay),
          home: const BlockedState(
            reason: BlockedReason.updateRequired,
            actionLabel: 'Check again',
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsOneWidget);
    });
  });

  group('the version gate', () {
    late _MockTeamAuthBloc auth;
    late _MockEssRepository ess;

    setUp(() async {
      await getIt.reset();
      auth = _MockTeamAuthBloc();
      when(() => auth.state).thenReturn(const TeamAuthState(
        status: TeamAuthStatus.authenticated,
        identity: StaffIdentity(userId: 'u-test', role: AppRole.admin),
      ));
      when(() => auth.stream)
          .thenAnswer((_) => const Stream<TeamAuthState>.empty());
      ess = _MockEssRepository();
      getIt.registerSingleton<EssRepository>(ess);
    });
    tearDown(getIt.reset);

    Future<void> pumpGate(WidgetTester tester) async {
      await tester.pumpWidget(BlocProvider<TeamAuthBloc>.value(
        value: auth,
        child: MaterialApp(
          theme: RvmTheme.light(seed: RvmColors.clay),
          builder: (context, child) =>
              VersionGate(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: Text('the app')),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('an old build gets the shared blocked screen', (tester) async {
      when(() => ess.health()).thenAnswer(
          (_) async => const EssHealth(ok: true, minAppVersion: '9.0.0'));
      await pumpGate(tester);

      expect(find.byType(BlockedState), findsOneWidget);
      expect(find.text('Update required'), findsOneWidget);
      expect(
          find.text('This version of Team RVM is no longer supported. Please '
              'update to continue (v9.0.0 or newer).'),
          findsOneWidget);
      expect(find.byIcon(Icons.system_update_alt), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('the app'), findsNothing);

      // Check again asks the server once more.
      when(() => ess.health()).thenAnswer(
          (_) async => const EssHealth(ok: true, minAppVersion: '0.0.1'));
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(find.byType(BlockedState), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('a current build passes straight through', (tester) async {
      when(() => ess.health()).thenAnswer(
          (_) async => const EssHealth(ok: true, minAppVersion: '0.1.0'));
      await pumpGate(tester);

      expect(find.byType(BlockedState), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });
  });
}
