const { z } = require('zod');
const pkg = require('../package.json');

/**
 * The ESS's settings, read from the environment once at start-up and checked before the
 * server listens. A bad value stops the process with a list of what is wrong, naming each
 * variable and never printing its value, rather than starting and failing request by request.
 *
 * The deploy writes these from the team_app repository secrets and variables
 * (.github/workflows/deploy-ess.yml); .env.example lists them for local work.
 */

/** An empty line in .env (KEY=) means "not set", not "set to nothing". */
const blank = (v) => (typeof v === 'string' && v.trim() === '' ? undefined : v);
const optional = (schema) => z.preprocess(blank, schema.optional());

// x.y.z with an optional -pre-release and +build, as Flutter writes them (1.4.0+12).
const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$/;
const version = () => z.string().trim().regex(SEMVER, 'must be a version such as 1.4.0');

const schema = z.object({
  PORT: z.preprocess(blank, z.coerce.number().int().min(1).max(65535).default(3740)),
  // Loopback unless told otherwise: nginx on the same server is the only caller. A port open to
  // the outside would take tokens over plain HTTP, and would let a caller write its own
  // X-Forwarded-For and choose its rate-limit bucket (trust proxy, app.js).
  HOST: z.preprocess(blank, z.union([z.ipv4(), z.ipv6(), z.literal('localhost')], {
    error: 'must be the address to listen on, such as 127.0.0.1',
  }).default('127.0.0.1')),
  // Not trimmed, and the same value as the Scheduler's: the two services must agree on it to the
  // byte, or the ESS refuses every token the Scheduler issues.
  JWT_SECRET: z.preprocess(blank, z.string({ error: 'is required' }).min(32, 'must be at least 32 characters')),
  SUPABASE_URL: z.preprocess(blank, z.url({ protocol: /^https?$/, error: 'must be the project URL, such as https://<project>.supabase.co' })),
  SUPABASE_SERVICE_KEY: z.preprocess(blank, z.string({ error: 'is required' })),
  ESS_ENABLED: optional(z.string()),
  APP_VERSION: optional(z.string().trim().max(100)),
  GIT_SHA: optional(z.string().trim().max(100)),
  MIN_APP_VERSION: optional(version()),
  LATEST_APP_VERSION: optional(version()),
  FIREBASE_PROJECT_ID: optional(z.string().trim()),
  FIREBASE_CLIENT_EMAIL: optional(z.string().trim()),
  // Base64 on one line, because a PEM's line breaks do not survive a .env line (ADR-0005).
  FIREBASE_PRIVATE_KEY_B64: optional(z.string().trim().regex(/^[A-Za-z0-9+/]+={0,2}$/, 'must be the private key base64-encoded on one line')),
}).superRefine((env, ctx) => {
  // A minimum above the latest would tell every phone to install a version that does not exist.
  if (env.MIN_APP_VERSION && env.LATEST_APP_VERSION && compareVersions(env.MIN_APP_VERSION, env.LATEST_APP_VERSION) > 0) {
    ctx.addIssue({ code: 'custom', path: ['MIN_APP_VERSION'], message: 'must not be above LATEST_APP_VERSION' });
  }
});

/** Compares x.y.z only; a pre-release or build suffix does not move a version past the next one. */
function compareVersions(a, b) {
  const core = (v) => v.split(/[-+]/)[0].split('.').map(Number);
  const [x, y] = [core(a), core(b)];
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1;
  return 0;
}

/**
 * @param {NodeJS.ProcessEnv | Record<string, string|undefined>} env
 * @returns the settings, frozen
 * @throws Error listing every invalid variable by name
 */
function loadConfig(env = process.env) {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const problems = parsed.error.issues.map((issue) => `${issue.path.join('.') || 'environment'} ${issue.message}`);
    throw new Error(`The ESS settings are not valid:\n  - ${problems.join('\n  - ')}`);
  }
  const e = parsed.data;
  const firebase = Object.freeze({
    projectId: e.FIREBASE_PROJECT_ID ?? null,
    clientEmail: e.FIREBASE_CLIENT_EMAIL ?? null,
    privateKeyB64: e.FIREBASE_PRIVATE_KEY_B64 ?? null,
  });
  return Object.freeze({
    port: e.PORT,
    host: e.HOST,
    jwtSecret: e.JWT_SECRET,
    supabaseUrl: e.SUPABASE_URL,
    supabaseServiceKey: e.SUPABASE_SERVICE_KEY,
    // The Scheduler's module-switch convention (config/hrPolicy.js HR_ENABLED): on unless the
    // value is "false", so a missing or mistyped value never takes the service down.
    essEnabled: String(e.ESS_ENABLED ?? 'true').trim().toLowerCase() !== 'false',
    version: e.APP_VERSION ?? e.GIT_SHA ?? pkg.version,
    minAppVersion: e.MIN_APP_VERSION ?? null,
    latestAppVersion: e.LATEST_APP_VERSION ?? null,
    firebase,
    // Until all three Firebase values exist, push writes each message to the log instead of
    // sending it (ADR-0016).
    push: Object.freeze({ enabled: Boolean(firebase.projectId && firebase.clientEmail && firebase.privateKeyB64) }),
  });
}

module.exports = { loadConfig, compareVersions };
