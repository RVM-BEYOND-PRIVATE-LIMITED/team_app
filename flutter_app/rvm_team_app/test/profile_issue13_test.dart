import 'dart:io';

import 'package:core_bloc/core_bloc.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/me/profile_screen.dart';
import 'package:rvm_team_app/injection.dart';

/// Regression tests for issues_image/issue13: Me -> Work profile must never
/// crash when the refresh fails (offline DNS, dead avatar host). The fetch
/// throws the same raw DioException the stack produces for a failed host
/// lookup, so the typed-failure mapping is exercised for real.
MyProfile _profile({String? photoUrl}) => MyProfile(
      employee: MyProfileEmployee(
        id: '1',
        fullName: 'Test Faculty',
        noticePeriod: false,
        photoUrl: photoUrl,
      ),
      personal: const PersonalDetails(),
      timeline: const [],
    );

DioException _dnsFailure() => DioException(
      requestOptions: RequestOptions(path: '/me/profile'),
      type: DioExceptionType.unknown,
      error: const SocketException(
        "Failed host lookup: 'gzgkhrqdiphx.supabase.co'",
        osError: OSError('No address associated with hostname', 7),
      ),
    );

const _emptyPraise = PraisePage(praise: [], badges: []);

Future<void> _pumpProfile(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // ProfileScreen builds its loaders from the global service locator.
    // Singletons (not factories) so the test drives the screen's own blocs.
    getIt.reset();
  });

  tearDown(() => getIt.reset());

  testWidgets('offline first load shows retry, throws nothing',
      (tester) async {
    getIt
      ..registerSingleton<LoadBloc<MyProfile>>(
          LoadBloc<MyProfile>(() async => throw _dnsFailure()))
      ..registerSingleton<LoadBloc<PraisePage>>(
          LoadBloc<PraisePage>(() async => throw _dnsFailure()));
    await _pumpProfile(tester);

    // The typed mapping turns the DNS failure into a friendly line, and the
    // screen offers a retry instead of crashing.
    expect(tester.takeException(), isNull);
    expect(find.text('No internet connection'), findsOneWidget);
  });

  testWidgets('failed refresh keeps the loaded profile', (tester) async {
    var fail = false;
    final profileBloc = LoadBloc<MyProfile>(() async {
      if (fail) throw _dnsFailure();
      return _profile();
    });
    getIt
      ..registerSingleton<LoadBloc<MyProfile>>(profileBloc)
      ..registerSingleton<LoadBloc<PraisePage>>(
          LoadBloc<PraisePage>(() async => _emptyPraise));
    await _pumpProfile(tester);
    expect(find.text('Test Faculty'), findsOneWidget);

    fail = true;
    profileBloc.add(const LoadRefreshed());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Test Faculty'), findsOneWidget);
    expect(find.text('No internet connection'), findsNothing);
  });

  testWidgets('dead avatar URL falls back to the initial', (tester) async {
    getIt
      ..registerSingleton<LoadBloc<MyProfile>>(LoadBloc<MyProfile>(
          () async => _profile(photoUrl: 'https://unresolvable.invalid/x.png')))
      ..registerSingleton<LoadBloc<PraisePage>>(
          LoadBloc<PraisePage>(() async => _emptyPraise));
    await _pumpProfile(tester);

    expect(tester.takeException(), isNull);
    // The initial is shown both in the avatar fallback and nowhere else twice.
    expect(find.text('T'), findsOneWidget);
  });
}
