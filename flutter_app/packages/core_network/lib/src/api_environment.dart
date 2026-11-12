/// Base URLs per backend, per build flavor. Override via --dart-define at build
/// time; the defaults point at the LIVE servers (no local backend needed).
class ApiEnvironment {
  const ApiEnvironment({
    required this.schedulerBaseUrl,
    required this.jobPortalBaseUrl,
    this.essBaseUrl = liveEssBaseUrl,
  });

  /// The live servers: the only URLs [isProduction] accepts, and the defaults
  /// of [ApiEnvironment.fromDefines]. One constant each, so the two can never
  /// disagree about where production is.
  static const liveSchedulerBaseUrl = 'https://scheduler.rvmcad.org/api';
  static const liveJobPortalBaseUrl = 'https://jobs.rvmcad.org/api/v1';
  static const liveEssBaseUrl = 'https://team-api.rvmcad.org/api/ess';

  /// Scheduler (Express) mounts everything under `/api`.
  final String schedulerBaseUrl;

  /// JobPortal (Next.js) versions its API under `/api/v1`.
  final String jobPortalBaseUrl;

  /// Team RVM ESS (`team_app`), mounted under `/api/ess` on its own host.
  final String essBaseUrl;

  /// Reads `SCHEDULER_BASE_URL` / `JOBPORTAL_BASE_URL` / `ESS_BASE_URL`
  /// dart-defines, falling back to the live servers. For a local backend pass
  /// the defines, e.g. `http://10.0.2.2:3000/api` (emulator) or
  /// `http://127.0.0.1:3000/api` (USB device + adb reverse).
  factory ApiEnvironment.fromDefines() {
    return const ApiEnvironment(
      schedulerBaseUrl: String.fromEnvironment(
        'SCHEDULER_BASE_URL',
        defaultValue: liveSchedulerBaseUrl,
      ),
      jobPortalBaseUrl: String.fromEnvironment(
        'JOBPORTAL_BASE_URL',
        defaultValue: liveJobPortalBaseUrl,
      ),
      essBaseUrl: String.fromEnvironment(
        'ESS_BASE_URL',
        defaultValue: liveEssBaseUrl,
      ),
    );
  }

  /// True only when every backend is its live server. Any other URL (a local
  /// server, a tunnel, a typo) means the build talks to something that is not
  /// production (team_app #60). Scheme and host are compared without case, and
  /// a trailing slash on the path does not count.
  bool get isProduction =>
      _same(schedulerBaseUrl, liveSchedulerBaseUrl) &&
      _same(jobPortalBaseUrl, liveJobPortalBaseUrl) &&
      _same(essBaseUrl, liveEssBaseUrl);

  static bool _same(String url, String live) {
    final a = Uri.tryParse(url.trim());
    final b = Uri.parse(live);
    if (a == null || !a.hasScheme || a.host.isEmpty) return false;
    return a.scheme.toLowerCase() == b.scheme &&
        a.host.toLowerCase() == b.host &&
        a.port == b.port &&
        _path(a.path) == _path(b.path) &&
        !a.hasQuery &&
        !a.hasFragment &&
        a.userInfo.isEmpty;
  }

  static String _path(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}
