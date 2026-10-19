const crypto = require('crypto');
const { createFcm, TOKEN_URL, SCOPE } = require('../src/lib/fcm');

/** Task D7: the Firebase Cloud Messaging client — the JWT, the access token, the message. */

const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const PRIVATE_PEM = privateKey.export({ type: 'pkcs8', format: 'pem' });
const PRIVATE_B64 = Buffer.from(PRIVATE_PEM).toString('base64');
const NOW = new Date('2026-10-16T06:30:00.000Z');
const EMAIL = 'push@team-rvm.iam.gserviceaccount.com';

/** A fetch stub that answers the token endpoint and the send endpoint, recording both. */
function stub({ token = true, send = { ok: true, status: 200, body: { name: 'projects/p/messages/1' } } } = {}) {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url, options });
    if (url === TOKEN_URL) {
      return token
        ? { ok: true, status: 200, json: async () => ({ access_token: 'access-1', expires_in: 3600 }) }
        : { ok: false, status: 400, json: async () => ({ error: 'invalid_grant' }) };
    }
    return { ok: send.ok, status: send.status, json: async () => send.body };
  };
  return { fetchImpl, calls };
}

const build = (fetchImpl, now = () => NOW) => createFcm({ projectId: 'team-rvm', clientEmail: EMAIL, privateKeyB64: PRIVATE_B64, fetchImpl, now });

describe('the FCM client', () => {
  it('signs the service-account assertion and sends the message with the access token', async () => {
    const { fetchImpl, calls } = stub();
    const fcm = build(fetchImpl);
    expect(await fcm.send({ token: 'device-token', title: 'Hello', body: 'There', data: { request_id: '41', attempt: 2 } })).toEqual({ ok: true });
    expect(calls).toHaveLength(2);

    const form = new URLSearchParams(calls[0].options.body);
    expect(form.get('grant_type')).toBe('urn:ietf:params:oauth:grant-type:jwt-bearer');
    const [header, claims, signature] = form.get('assertion').split('.');
    expect(JSON.parse(Buffer.from(header, 'base64url').toString('utf8'))).toEqual({ alg: 'RS256', typ: 'JWT' });
    expect(JSON.parse(Buffer.from(claims, 'base64url').toString('utf8'))).toMatchObject({ iss: EMAIL, scope: SCOPE, aud: TOKEN_URL });
    expect(crypto.verify('RSA-SHA256', Buffer.from(`${header}.${claims}`), publicKey, Buffer.from(signature, 'base64url'))).toBe(true);

    expect(calls[1].url).toBe('https://fcm.googleapis.com/v1/projects/team-rvm/messages:send');
    expect(calls[1].options.headers.authorization).toBe('Bearer access-1');
    expect(JSON.parse(calls[1].options.body)).toEqual({
      message: {
        token: 'device-token',
        notification: { title: 'Hello', body: 'There' },
        data: { request_id: '41', attempt: '2' },
        android: { priority: 'high' },
      },
    });
  });

  it('keeps the access token for its hour: one token call for two messages', async () => {
    const { fetchImpl, calls } = stub();
    const fcm = build(fetchImpl);
    await fcm.send({ token: 'a', title: 'One', body: 'One' });
    await fcm.send({ token: 'b', title: 'Two', body: 'Two' });
    expect(calls.filter((c) => c.url === TOKEN_URL)).toHaveLength(1);
    expect(calls.filter((c) => c.url.includes('messages:send'))).toHaveLength(2);
  });

  it('marks a 404 or an UNREGISTERED answer as an invalid token, and a 500 as a plain failure', async () => {
    const gone = build(stub({ send: { ok: false, status: 404, body: { error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } } } }).fetchImpl);
    expect(await gone.send({ token: 'x', title: 'T', body: 'B' })).toMatchObject({ ok: false, invalidToken: true });
    const broken = build(stub({ send: { ok: false, status: 500, body: {} } }).fetchImpl);
    expect(await broken.send({ token: 'x', title: 'T', body: 'B' })).toMatchObject({ ok: false, invalidToken: false });
  });

  it('reports a token-endpoint failure and a network failure, never throwing', async () => {
    const denied = build(stub({ token: false }).fetchImpl);
    expect(await denied.send({ token: 'x', title: 'T', body: 'B' })).toMatchObject({ ok: false, error: expect.stringContaining('400') });
    const offline = build(async () => { throw new TypeError('fetch failed'); });
    expect(await offline.send({ token: 'x', title: 'T', body: 'B' })).toMatchObject({ ok: false, error: expect.stringContaining('fetch failed') });
  });

  it('refuses to start without the three settings', () => {
    expect(() => createFcm({ projectId: 'p', clientEmail: EMAIL })).toThrow(/FIREBASE_PRIVATE_KEY_B64/);
    expect(() => createFcm({ projectId: 'p', clientEmail: EMAIL, privateKeyB64: 'not-a-pem' }).accessToken())
      .not.toThrow();
  });
});
