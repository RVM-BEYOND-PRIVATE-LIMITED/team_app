const { loadConfig, compareVersions } = require('../src/config');
const { TEST_ENV, TEST_JWT_SECRET } = require('./helpers/constants');
const pkg = require('../package.json');

/** config.js: what the ESS starts with, and what stops it starting. */

const load = (overrides = {}) => loadConfig({ ...TEST_ENV, ...overrides });

describe('loadConfig', () => {
  it('fills in the defaults', () => {
    const config = load();
    expect(config).toMatchObject({
      port: 3740,
      host: '127.0.0.1',
      jwtSecret: TEST_JWT_SECRET,
      supabaseUrl: TEST_ENV.SUPABASE_URL,
      supabaseServiceKey: TEST_ENV.SUPABASE_SERVICE_KEY,
      essEnabled: true,
      version: pkg.version,
      minAppVersion: null,
      latestAppVersion: null,
      push: { enabled: false },
    });
    expect(config.firebase).toEqual({ projectId: null, clientEmail: null, privateKeyB64: null });
  });

  it('is frozen, so nothing changes it after start-up', () => {
    const config = load();
    expect(Object.isFrozen(config)).toBe(true);
    expect(Object.isFrozen(config.push)).toBe(true);
    expect(Object.isFrozen(config.firebase)).toBe(true);
  });

  it('reads PORT', () => {
    expect(load({ PORT: '8080' }).port).toBe(8080);
    expect(load({ PORT: '' }).port).toBe(3740);
    expect(() => load({ PORT: 'eighty' })).toThrow(/PORT/);
    expect(() => load({ PORT: '70000' })).toThrow(/PORT/);
  });

  it('listens on loopback unless HOST names another address', () => {
    // nginx on the same server is the only caller; the port is never open to the network.
    expect(load({ HOST: '' }).host).toBe('127.0.0.1');
    for (const host of ['0.0.0.0', '::', '::1', 'localhost']) expect(load({ HOST: host }).host).toBe(host);
    expect(() => load({ HOST: 'team-api.rvmcad.org' })).toThrow(/HOST must be the address to listen on/);
    expect(() => load({ HOST: '999.0.0.1' })).toThrow(/HOST/);
  });

  describe('JWT_SECRET', () => {
    it('is required', () => {
      expect(() => load({ JWT_SECRET: undefined })).toThrow(/JWT_SECRET is required/);
      expect(() => load({ JWT_SECRET: '   ' })).toThrow(/JWT_SECRET is required/);
    });

    it('must be at least 32 characters, and the refusal never prints it', () => {
      const short = 'a-short-secret-of-31-characters';
      expect(short).toHaveLength(31);
      let message = '';
      try { load({ JWT_SECRET: short }); } catch (e) { message = e.message; }
      expect(message).toMatch(/JWT_SECRET must be at least 32 characters/);
      expect(message).not.toContain(short);
      expect(load({ JWT_SECRET: `${short}x` }).jwtSecret).toBe(`${short}x`);
    });

    it('is kept exactly as given, because it must match the Scheduler\'s to the byte', () => {
      const padded = ` ${TEST_JWT_SECRET} `;
      expect(load({ JWT_SECRET: padded }).jwtSecret).toBe(padded);
    });
  });

  it('requires the Supabase project and service key', () => {
    expect(() => load({ SUPABASE_URL: undefined })).toThrow(/SUPABASE_URL/);
    expect(() => load({ SUPABASE_URL: 'not a url' })).toThrow(/SUPABASE_URL/);
    expect(() => load({ SUPABASE_URL: 'ftp://example.test' })).toThrow(/SUPABASE_URL/);
    expect(() => load({ SUPABASE_SERVICE_KEY: '' })).toThrow(/SUPABASE_SERVICE_KEY is required/);
  });

  it('lists every problem at once', () => {
    let message = '';
    try { loadConfig({}); } catch (e) { message = e.message; }
    expect(message).toMatch(/JWT_SECRET/);
    expect(message).toMatch(/SUPABASE_URL/);
    expect(message).toMatch(/SUPABASE_SERVICE_KEY/);
  });

  it('switches the ESS off only for "false", as the Scheduler\'s module switch does', () => {
    for (const off of ['false', 'FALSE', 'False', ' false ']) expect(load({ ESS_ENABLED: off }).essEnabled).toBe(false);
    for (const on of [undefined, '', 'true', 'TRUE', '1', 'no']) expect(load({ ESS_ENABLED: on }).essEnabled).toBe(true);
  });

  describe('the versions', () => {
    it('prefer APP_VERSION, then GIT_SHA, then the package version', () => {
      expect(load({ APP_VERSION: '0.2.0', GIT_SHA: 'abc' }).version).toBe('0.2.0');
      expect(load({ GIT_SHA: 'abc' }).version).toBe('abc');
      expect(load({ APP_VERSION: '', GIT_SHA: '' }).version).toBe(pkg.version);
    });

    it('take the app versions as semver, Flutter build numbers included', () => {
      const config = load({ MIN_APP_VERSION: '1.0.0', LATEST_APP_VERSION: '1.3.2+27' });
      expect(config.minAppVersion).toBe('1.0.0');
      expect(config.latestAppVersion).toBe('1.3.2+27');
      expect(load({ MIN_APP_VERSION: '1.0.0-beta.2' }).minAppVersion).toBe('1.0.0-beta.2');
    });

    it('refuse an app version that is not one', () => {
      expect(() => load({ MIN_APP_VERSION: '1.0' })).toThrow(/MIN_APP_VERSION must be a version/);
      expect(() => load({ LATEST_APP_VERSION: 'v1.2.0' })).toThrow(/LATEST_APP_VERSION must be a version/);
      expect(() => load({ MIN_APP_VERSION: '01.0.0' })).toThrow(/MIN_APP_VERSION/);
    });

    it('refuse a minimum above the latest, which would ask every phone for a version that does not exist', () => {
      expect(() => load({ MIN_APP_VERSION: '1.4.0', LATEST_APP_VERSION: '1.3.9' })).toThrow(/MIN_APP_VERSION must not be above LATEST_APP_VERSION/);
      expect(load({ MIN_APP_VERSION: '1.4.0', LATEST_APP_VERSION: '1.4.0+3' }).minAppVersion).toBe('1.4.0');
    });

    it('are compared on major.minor.patch', () => {
      expect(compareVersions('1.2.3', '1.2.3')).toBe(0);
      expect(compareVersions('1.2.3', '1.10.0')).toBe(-1);
      expect(compareVersions('2.0.0', '1.99.99')).toBe(1);
      expect(compareVersions('1.2.3+9', '1.2.3')).toBe(0);
    });
  });

  describe('push', () => {
    const firebase = {
      FIREBASE_PROJECT_ID: 'rvm-team-test',
      FIREBASE_CLIENT_EMAIL: 'push@rvm-team-test.iam.gserviceaccount.com',
      // A dummy, base64-encoded as the real key will be; spelt so that no secret scanner mistakes it for one.
      FIREBASE_PRIVATE_KEY_B64: Buffer.from('dummy key\nline two\nline three\n').toString('base64'),
    };

    it('is enabled with all three FIREBASE_* settings', () => {
      const config = load(firebase);
      expect(config.push.enabled).toBe(true);
      expect(config.firebase.projectId).toBe('rvm-team-test');
    });

    it('is log-only with any of them missing', () => {
      for (const k of Object.keys(firebase)) expect(load({ ...firebase, [k]: '' }).push.enabled).toBe(false);
    });

    it('refuses a private key that is not base64 on one line, such as a pasted PEM', () => {
      // A PEM's dashes and line breaks are not base64.
      expect(() => load({ ...firebase, FIREBASE_PRIVATE_KEY_B64: '-----DUMMY-----\nabc' })).toThrow(/FIREBASE_PRIVATE_KEY_B64/);
    });
  });
});
