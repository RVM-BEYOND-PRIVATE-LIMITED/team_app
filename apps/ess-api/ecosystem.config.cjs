/**
 * pm2's definition of the ESS on the Scheduler's server (ADR-0005), started by the deploy with
 * `pm2 startOrReload apps/ess-api/ecosystem.config.cjs`.
 *
 * Exactly one instance, in fork mode. The rate limits are counted in this process's memory, and
 * the background jobs still to come (the push worker, the helpdesk response-time checks) must
 * run once: a second instance, or cluster mode, would split the limits and run every job twice.
 *
 * The secrets are not here. They are in apps/ess-api/.env, which the deploy writes and
 * src/server.js reads; PORT and HOST are set here so that they win over anything in that file
 * and over anything already in pm2's own environment. HOST keeps the port on loopback, behind
 * the ESS's own nginx file (ADR-0019).
 */
module.exports = {
  apps: [
    {
      name: 'team-rvm-ess',
      cwd: __dirname,
      script: 'src/server.js',
      exec_mode: 'fork',
      instances: 1,
      autorestart: true,
      // Restart the ESS before it can starve the Scheduler on the same server of memory.
      max_memory_restart: '300M',
      time: true,
      env: {
        NODE_ENV: 'production',
        PORT: 3001,
        HOST: '127.0.0.1',
      },
    },
  ],
};
