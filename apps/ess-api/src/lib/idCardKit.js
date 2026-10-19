const crypto = require('crypto');
const { HttpError, MESSAGES } = require('./errors');

/**
 * The ID card's verification link (Phase 2C): a small HMAC-signed token that anybody the holder
 * shows the card to can open, with no sign-in of any kind.
 *
 * The token is the payload (base64url JSON: whose card, when it expires) and the HMAC-SHA256 of
 * it, under a key derived from the same JWT_SECRET the sign-ins are minted from — one secret on
 * the server, and a link minted by one ESS process verifies on the same one. A bad signature, a
 * token that is not a token, and an expired one are all the same 401, so nobody learns which
 * part failed.
 *
 * The link is read-only and reveals nothing but what the card itself shows: the holder's name,
 * code, designation and branch. It is rate-limited per address (app.js), as the sign-in is.
 */

/** How long a card's verification link stays good. */
const VERIFY_DAYS = 90;

/** The derive the refresh-hash key uses (lib/accessTokens.js), named for this link. */
const idCardKey = (jwtSecret) =>
  crypto.createHash('sha256').update(`rvm-ess-id-card-v1:${jwtSecret}`).digest();

const b64url = (buffer) => Buffer.from(buffer).toString('base64url');

/** The token for one person's card, good for VERIFY_DAYS from `now`. */
function signVerifyToken({ jwtSecret, employeeId, now }) {
  const exp = now.getTime() + VERIFY_DAYS * 86400000;
  const payload = b64url(JSON.stringify({ employee_id: employeeId, exp }));
  const signature = b64url(crypto.createHmac('sha256', idCardKey(jwtSecret)).update(payload).digest());
  return `${payload}.${signature}`;
}

/** The 401 every bad, forged and expired link gets, in one wording. */
const badToken = () => new HttpError(401, 'ID_CARD_BAD_TOKEN', MESSAGES.ID_CARD_BAD_TOKEN);

/** Whose card the token is, and when it ends — or null when it is not one of ours. */
function readVerifyToken(token, jwtSecret, now) {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const [payload, signature] = parts;
  const expected = crypto.createHmac('sha256', idCardKey(jwtSecret)).update(payload).digest();
  let given;
  try {
    given = Buffer.from(signature, 'base64url');
  } catch {
    return null;
  }
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return null;
  let body;
  try {
    body = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (!body || typeof body.employee_id !== 'string' || !Number.isFinite(body.exp)) return null;
  if (body.exp <= now.getTime()) return null;
  return { employeeId: body.employee_id, exp: body.exp };
}

module.exports = { VERIFY_DAYS, signVerifyToken, readVerifyToken, badToken };
