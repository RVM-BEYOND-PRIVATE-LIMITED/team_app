/// Base URLs per backend, per build flavor. Override via --dart-define at build
/// time; the defaults point at the LIVE servers (no local backend needed).
class ApiEnvironment {
  const ApiEnvironment({
    required this.schedulerBaseUrl,
    required this.jobPortalBaseUrl,
    this.essBaseUrl = 'https://team-api.rvmcad.org/api/ess',
  });

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
        defaultValue: 'https://scheduler.rvmcad.org/api',
      ),
      jobPortalBaseUrl: String.fromEnvironment(
        'JOBPORTAL_BASE_URL',
        defaultValue: 'https://jobs.rvmcad.org/api/v1',
      ),
      essBaseUrl: String.fromEnvironment(
        'ESS_BASE_URL',
        defaultValue: 'https://team-api.rvmcad.org/api/ess',
      ),
    );
  }
}
