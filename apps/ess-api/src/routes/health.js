const { asyncRoute } = require('../lib/errors');

/**
 * GET /api/ess/health, with no sign-in (task K2).
 *
 * The app calls it when it starts: is the server there, how far off is my clock, must I
 * update. It answers 200 even when the database is not reachable, with db 'unavailable',
 * because the process is up and the app decides what to show. It is also what the deploy
 * polls after a restart.
 *
 * The database check is one small read with a short deadline, so a slow database cannot make
 * the health check slow too.
 */
function healthRoute({ config, store, now, timeoutMs }) {
  return asyncRoute(async (_req, res) => {
    const db = await checkDatabase(store, timeoutMs);
    res.json({
      ok: true,
      server_time: now().toISOString(),
      version: config.version,
      min_app_version: config.minAppVersion,
      latest_app_version: config.latestAppVersion,
      db,
    });
  });
}

async function checkDatabase(store, timeoutMs) {
  const controller = new AbortController();
  let timer;
  const deadline = new Promise((resolve) => {
    timer = setTimeout(() => {
      controller.abort();
      resolve('unavailable');
    }, timeoutMs);
  });
  const read = Promise.resolve()
    .then(() => store.ping({ signal: controller.signal }))
    .then(() => 'ok', () => 'unavailable');
  try {
    return await Promise.race([read, deadline]);
  } finally {
    clearTimeout(timer);
  }
}

module.exports = { healthRoute, checkDatabase };
