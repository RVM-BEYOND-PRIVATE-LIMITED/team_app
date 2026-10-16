const path = require('path');

// The deploy writes apps/ess-api/.env. A value already in the environment wins, which is how
// pm2's PORT (ecosystem.config.cjs) takes effect.
require('dotenv').config({ path: path.join(__dirname, '..', '.env'), quiet: true });

const { loadConfig } = require('./config');
const { createSupabaseStore } = require('./lib/store');
const { createApp } = require('./app');

let config;
try {
  config = loadConfig(process.env);
} catch (e) {
  // Names only, never values (config.js), so this is safe in the pm2 log.
  console.error(`[ess] ${e.message}`);
  process.exit(1);
}

const app = createApp({ config, store: createSupabaseStore(config) });

app.listen(config.port, config.host, () => {
  console.log(`[ess] Team RVM ESS ${config.version} listening on ${config.host} port ${config.port}`);
  if (!config.essEnabled) console.log('[ess] ESS_ENABLED=false: every endpoint except /api/ess/health answers 503 MODULE_DISABLED.');
  if (!config.push.enabled) console.log('[ess] Push is log-only: the FIREBASE_* settings are not all set.');
});
