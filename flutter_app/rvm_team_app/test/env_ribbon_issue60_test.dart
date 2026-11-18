import 'package:core_network/core_network.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/widgets/env_ribbon.dart';

/// team_app #60: a TEST SERVER ribbon when the build's API is not production,
/// switched off unless SHOW_ENV_RIBBON=true is passed at build time.
const _live = ApiEnvironment(
  schedulerBaseUrl: ApiEnvironment.liveSchedulerBaseUrl,
  jobPortalBaseUrl: ApiEnvironment.liveJobPortalBaseUrl,
);

const _local = ApiEnvironment(
  schedulerBaseUrl: 'http://10.0.2.2:3000/api',
  jobPortalBaseUrl: ApiEnvironment.liveJobPortalBaseUrl,
  essBaseUrl: 'http://10.0.2.2:4100/api/ess',
);

Widget _app(Widget ribbon) => MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => ribbon,
      home: const SizedBox.shrink(),
    );

void main() {
  test('is switched off by default', () {
    // No --dart-define=SHOW_ENV_RIBBON=true in a normal build or test run.
    expect(showEnvRibbon, isFalse);
    const ribbon = EnvRibbon(environment: _local, child: SizedBox.shrink());
    expect(ribbon.enabled, isFalse);
  });

  testWidgets('switched on, it marks a build that talks to a test server',
      (tester) async {
    await tester.pumpWidget(_app(const EnvRibbon(
      environment: _local,
      enabled: true,
      child: Text('the app', textDirection: TextDirection.ltr),
    )));
    final banner = tester.widget<Banner>(find.byType(Banner));
    expect(banner.message, 'TEST SERVER');
    expect(banner.location, BannerLocation.topEnd);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('never shows against the live servers', (tester) async {
    await tester.pumpWidget(_app(const EnvRibbon(
      environment: _live,
      enabled: true,
      child: Text('the app', textDirection: TextDirection.ltr),
    )));
    expect(find.byType(Banner), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('switched off, a test server shows no ribbon either',
      (tester) async {
    await tester.pumpWidget(_app(const EnvRibbon(
      environment: _local,
      child: Text('the app', textDirection: TextDirection.ltr),
    )));
    expect(find.byType(Banner), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });
}
