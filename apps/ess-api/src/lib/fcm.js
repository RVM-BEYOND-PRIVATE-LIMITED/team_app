const crypto = require('crypto');

/**
 * Firebase Cloud Messaging, HTTP v1, with no SDK (task D7).
 *
 * A service account's JWT buys an OAuth access token (RS256, cached for its hour), and each
 * message goes to `projects/{projectId}/messages:send` with that token. `fetch` is injectable so
 * the tests send nothing; production uses Node's own fetch (Node 20 or later).
 *
 * When the three FIREBASE_* settings are absent the caller never builds this: the push job writes
 * each message to the log instead (ADR-0016). A 404 or an UNREGISTERED/INVALID_ARGUMENT reply
 * means the token belongs to no install any more, and the caller revokes the device row.
 */

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

const base64url = (value) => Buffer.from(value).toString('base64')
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

/**
 * @param {object} settings
 * @param {string} settings.projectId
 * @param {string} settings.clientEmail
 * @param {string} settings.privateKeyB64  the service account's PEM, base64 on one line
 * @param {Function} [settings.fetchImpl]  fetch by default; the tests pass a stub
 * @param {() => Date} [settings.now]
 */
function createFcm({ projectId, clientEmail, privateKeyB64, fetchImpl = fetch, now = () => new Date() }) {
  if (!projectId || !clientEmail || !privateKeyB64) {
    throw new Error('createFcm needs FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL and FIREBASE_PRIVATE_KEY_B64');
  }
  const privateKey = Buffer.from(privateKeyB64, 'base64').toString('utf8');
  /** { token, expiresAt } for the hour the access token lives. */
  let cached = null;

  /** The OAuth access token, from the service account's signed assertion. */
  async function accessToken() {
    const at = now().getTime();
    if (cached && cached.expiresAt - 60 * 1000 > at) return { token: cached.token };
    const iat = Math.floor(at / 1000);
    const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claims = base64url(JSON.stringify({ iss: clientEmail, scope: SCOPE, aud: TOKEN_URL, iat, exp: iat + 3600 }));
    const signingInput = `${header}.${claims}`;
    let signature;
    try {
      signature = base64url(crypto.createSign('RSA-SHA256').update(signingInput).sign(privateKey));
    } catch {
      return { error: 'the service account private key could not sign the token request' };
    }
    const res = await (async () => {
      try {
        return await fetchImpl(TOKEN_URL, {
          method: 'POST',
          headers: { 'content-type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${signingInput}.${signature}` }).toString(),
        });
      } catch (e) {
        return { networkError: e };
      }
    })();
    if (res.networkError) {
      return { error: `the token request failed (${res.networkError && res.networkError.message ? res.networkError.message : res.networkError})` };
    }
    if (!res.ok) return { error: `the token endpoint answered ${res.status}` };
    let body;
    try {
      body = await res.json();
    } catch {
      return { error: 'the token endpoint answered something that is not JSON' };
    }
    if (!body.access_token) return { error: 'the token endpoint answered no access token' };
    cached = { token: body.access_token, expiresAt: at + (Number(body.expires_in) || 3600) * 1000 };
    return { token: cached.token };
  }

  /**
   * Send one message. Answers { ok: true }, or { ok: false, invalidToken, error }: invalidToken
   * is true when the token belongs to no install, which is the caller's signal to revoke it.
   */
  async function send({ token, title, body, data = {} }) {
    const auth = await accessToken();
    if (auth.error) return { ok: false, invalidToken: false, error: auth.error };
    const message = {
      message: {
        token,
        notification: { title, body },
        // FCM wants strings; the ids a tap needs are strings already.
        data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
        android: { priority: 'high' },
      },
    };
    let res;
    try {
      res = await fetchImpl(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`, {
        method: 'POST',
        headers: { authorization: `Bearer ${auth.token}`, 'content-type': 'application/json' },
        body: JSON.stringify(message),
      });
    } catch (e) {
      return { ok: false, invalidToken: false, error: `the FCM request failed (${e && e.message ? e.message : e})` };
    }
    if (res.ok) return { ok: true };
    let detail;
    try {
      detail = JSON.stringify(await res.json());
    } catch {
      detail = '';
    }
    const invalidToken = res.status === 404 || /UNREGISTERED|INVALID_ARGUMENT/.test(detail);
    return { ok: false, invalidToken, error: `FCM answered ${res.status}${detail ? `: ${detail.slice(0, 200)}` : ''}` };
  }

  return { send, accessToken };
}

module.exports = { createFcm, TOKEN_URL, SCOPE };
