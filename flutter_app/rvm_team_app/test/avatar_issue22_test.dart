import 'dart:io';

import 'package:core_bloc/core_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/me/profile_screen.dart';
import 'package:rvm_team_app/injection.dart';
import 'package:rvm_team_app/widgets/team_kit.dart';

/// A client whose request fails with the real issue23 exception, i.e. a DNS
/// `SocketException` raised when the connection is attempted.
class _DnsFailClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _DnsFailRequest();

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _DnsFailRequest implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() => Future<HttpClientResponse>.error(
        const SocketException(
          "Failed host lookup: 'gzgkhrqdiphxoopuhayh.supabase.co'",
          osError: OSError('No address associated with hostname', 7),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _DnsFailOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _DnsFailClient();
}

/// Regression for issues_image/issue22 (crash text from issue13).
///
/// The live ESS signs profile photos from Supabase storage
/// (`apps/ess-api/src/lib/store.js` `signedPhotoUrl` → the project in
/// `Scheduler_Backend/.env`, `gzgkhrqdiphxoopuhayh.supabase.co`). When that
/// image load fails with a socket/DNS error the old `NetworkImage` path
/// rethrew it inside Flutter's image pipeline, which stops the debugger and
/// reports a framework error — the "crash" on My profile.
const _supabasePhoto =
    'https://gzgkhrqdiphxoopuhayh.supabase.co/storage/v1/object/sign/documents/x.png?token=abc';

MyProfile _issue22Profile() => MyProfile(
      employee: const MyProfileEmployee(
        id: '1',
        fullName: 'Rishi Ojha',
        employeeCode: 'RVM/F/48',
        designation: 'Mobile App Developer',
        dateOfJoining: '2026-06-22',
        employmentStatus: 'active',
        noticePeriod: false,
        email: 'rishiojha7@gmail.com',
        phone: '8946991002',
        photoUrl: _supabasePhoto,
      ),
      personal: const PersonalDetails(),
      timeline: [
        TimelineEvent(
            id: 't1', title: 'Details updated', at: DateTime(2026, 10, 15)),
        TimelineEvent(
            id: 't2',
            title: 'Increment date recorded',
            at: DateTime(2026, 10, 16)),
      ],
    );

void main() {
  setUp(() => getIt.reset());
  tearDown(() {
    getIt.reset();
    HttpOverrides.global = null;
  });

  testWidgets('issue23: a real DNS SocketException is caught, fallback shown',
      (tester) async {
    // This reproduces the exact failure: the DNS lookup for the Supabase photo
    // host throws SocketException. Before the fix the future was abandoned by
    // `.timeout()`/`close(force: true)`, so the error surfaced as an UNCAUGHT
    // async error and the debugger paused. If it is uncaught again, the test
    // framework fails this test.
    HttpOverrides.global = _DnsFailOverrides();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SafePhoto(url: _supabasePhoto, fallback: Text('fallback')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('issue22 profile with failing Supabase photo shows R, no crash',
      (tester) async {
    HttpOverrides.global = _DnsFailOverrides();
    getIt
      ..registerSingleton<LoadBloc<MyProfile>>(
          LoadBloc<MyProfile>(() async => _issue22Profile()))
      ..registerSingleton<LoadBloc<PraisePage>>(LoadBloc<PraisePage>(
          () async => const PraisePage(praise: [], badges: [])));
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Details updated'), findsNothing);
    expect(find.text('Increment date recorded'), findsOneWidget);
    // Avatar shows the initial, never an empty circle.
    expect(find.text('R'), findsWidgets);
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.textContaining('Failed host lookup'), findsNothing);
  });

  testWidgets('SafePhoto swallows a throwing request and shows the fallback',
      (tester) async {
    // A malformed authority makes HttpClient.getUrl throw synchronously — the
    // same code path a DNS SocketException takes. The widget must catch it.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SafePhoto(
          url: 'http://[::1',
          fallback: Text('fallback'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('TeamAvatar with a dead photo URL shows the initial',
      (tester) async {
    HttpOverrides.global = _DnsFailOverrides();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TeamAvatar(
          name: 'Rishi Ojha',
          photoUrl: _supabasePhoto,
          size: 64,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('R'), findsOneWidget);
  });
}
