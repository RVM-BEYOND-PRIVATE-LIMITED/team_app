import 'package:core_network/core_network.dart';
import 'package:test/test.dart';

/// team_app #60: the TEST SERVER ribbon shows when a build's API is not
/// production, so "production" must be exactly the live servers.
void main() {
  const live = ApiEnvironment(
    schedulerBaseUrl: ApiEnvironment.liveSchedulerBaseUrl,
    jobPortalBaseUrl: ApiEnvironment.liveJobPortalBaseUrl,
  );

  ApiEnvironment envWith({String? scheduler, String? jobPortal, String? ess}) =>
      ApiEnvironment(
        schedulerBaseUrl: scheduler ?? ApiEnvironment.liveSchedulerBaseUrl,
        jobPortalBaseUrl: jobPortal ?? ApiEnvironment.liveJobPortalBaseUrl,
        essBaseUrl: ess ?? ApiEnvironment.liveEssBaseUrl,
      );

  test('a build without defines talks to production', () {
    final env = ApiEnvironment.fromDefines();
    expect(env.schedulerBaseUrl, 'https://scheduler.rvmcad.org/api');
    expect(env.jobPortalBaseUrl, 'https://jobs.rvmcad.org/api/v1');
    expect(env.essBaseUrl, 'https://team-api.rvmcad.org/api/ess');
    expect(env.isProduction, isTrue);
  });

  test('the live servers are production, written either way', () {
    expect(live.isProduction, isTrue);
    expect(
        envWith(
          scheduler: 'HTTPS://Scheduler.RVMCAD.org/api/',
          ess: 'https://team-api.rvmcad.org:443/api/ess',
        ).isProduction,
        isTrue);
  });

  test('any local or other server is not production', () {
    for (final env in [
      envWith(scheduler: 'http://10.0.2.2:3000/api'),
      envWith(scheduler: 'http://127.0.0.1:3000/api'),
      envWith(ess: 'http://10.0.2.2:4100/api/ess'),
      envWith(jobPortal: 'http://localhost:3001/api/v1'),
      // The live host over plain http, on another port or path, with a query.
      envWith(scheduler: 'http://scheduler.rvmcad.org/api'),
      envWith(scheduler: 'https://scheduler.rvmcad.org:8443/api'),
      envWith(scheduler: 'https://scheduler.rvmcad.org/api/v2'),
      envWith(ess: 'https://team-api.rvmcad.org/api/ess?mock=1'),
      // A look-alike host.
      envWith(scheduler: 'https://scheduler.rvmcad.org.example.test/api'),
    ]) {
      expect(env.isProduction, isFalse,
          reason: '${env.schedulerBaseUrl} ${env.essBaseUrl} '
              '${env.jobPortalBaseUrl}');
    }
  });

  test('a URL that cannot be read is not production', () {
    expect(envWith(scheduler: '').isProduction, isFalse);
    expect(envWith(ess: 'not a url').isProduction, isFalse);
    expect(envWith(scheduler: 'scheduler.rvmcad.org/api').isProduction, isFalse);
  });
}
