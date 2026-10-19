const path = require('path');

// The deploy writes apps/ess-api/.env. A value already in the environment wins, which is how
// pm2's PORT (ecosystem.config.cjs) takes effect.
require('dotenv').config({ path: path.join(__dirname, '..', '.env'), quiet: true });

const { loadConfig } = require('./config');
const { createSupabaseStore } = require('./lib/store');
const { createApp } = require('./app');
const { startOnDutyJob } = require('./jobs/onDuty');
const { startPushJob } = require('./jobs/push');
const { startWallJob } = require('./jobs/wall');
const { startHelpdeskJob } = require('./jobs/helpdesk');
const { startDocumentsJob } = require('./jobs/documents');

let config;
try {
  config = loadConfig(process.env);
} catch (e) {
  // Names only, never values (config.js), so this is safe in the pm2 log.
  console.error(`[ess] ${e.message}`);
  process.exit(1);
}

const store = createSupabaseStore(config);
const app = createApp({ config, store });

app.listen(config.port, config.host, () => {
  console.log(`[ess] Team RVM ESS ${config.version} listening on ${config.host} port ${config.port}`);
  if (!config.essEnabled) {
    console.log('[ess] ESS_ENABLED=false: every endpoint except /api/ess/health answers 503 MODULE_DISABLED.');
    return;
  }
  if (!config.push.enabled) console.log('[ess] Push is log-only: the FIREBASE_* settings are not all set.');
  // The on-duty morning job (C3, C7): once at boot, then hourly. Off with the ESS switch.
  startOnDutyJob({ store });
  // Notifications and push (D2, D7, D8): priority tasks in, pushes out; log-only without Firebase.
  startPushJob({ store, config });
  // The Wall's own clock (F4, F5): scheduled announcements, acknowledgement reminders, poll closes.
  startWallJob({ store });
  // The Helpdesk's escalations (G3): first response, resolution and the CEO's stage, hourly.
  startHelpdeskJob({ store });
  // The weekly missing-documents reminder (KP 1): identity, offer and joining papers, at boot
  // and then weekly.
  startDocumentsJob({ store });
});
