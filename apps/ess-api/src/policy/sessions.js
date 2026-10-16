/**
 * Staying signed in (task A3): KP's decisions of 16 Oct 2026 (docs/03-decisions.md) and the
 * rules the session endpoints share. The flow is in docs/04-build-plan.md, Wave 2.
 *
 * A sign-in the app keeps is a family of rows in hr_ess_sessions, one per refresh token. The
 * family is the sign-in; each refresh retires the row it was given and adds the next one.
 */

/** Access tokens last one hour (KP, 16 Oct). */
const ACCESS_TOKEN_SECONDS = 60 * 60;

/** A sign-in lasts 90 days from its last use, and every refresh is a use (KP, 16 Oct). */
const SESSION_MS = 90 * 24 * 60 * 60 * 1000;

/**
 * Only a sign-in made in the last ten minutes may be kept. Without this, a 64-hour portal token
 * or a 30-day attendance session found on a lost phone could be traded for 90 days.
 */
const FRESH_SIGN_IN_MS = 10 * 60 * 1000;

/**
 * Both services read the same server clock (ADR-0019), so a sign-in "from the future" is a
 * clock that was set wrong; a minute of grace and no more.
 */
const CLOCK_SKEW_MS = 60 * 1000;

/**
 * A refresh token already traded in, presented again from the same install within this long, is
 * the app retrying a refresh it lost track of (two screens refreshing at once): it is told to use
 * its newest token, and nothing is revoked. Later, or from another install, it is reuse.
 */
const REFRESH_RETRY_MS = 60 * 1000;

/** What the app names its install with: random, chosen once per install, kept with its tokens. */
const INSTALL_ID_RE = /^[A-Za-z0-9._-]{16,128}$/;

/** 32 random bytes, base64url without padding (lib/accessTokens.js newRefreshToken). */
const REFRESH_TOKEN_RE = /^[A-Za-z0-9_-]{43}$/;

const DEVICE_LABEL_MAX = 80;

/** Why a sign-in ended: the CHECK on hr_ess_sessions.revoked_reason, in the migration. */
const REVOKE_REASONS = Object.freeze(['rotated', 'signed_out', 'reuse', 'password_changed', 'login_off', 'left', 'unlinked', 'expired']);

/**
 * What a refused refresh tells the app in `reason`: every way a refresh token stops working, and
 * 'unknown' for one the ESS never issued. 'rotated' is never a reason on its own: a traded-in token
 * is either a retry (409) or reuse.
 */
const REFUSAL_REASONS = Object.freeze(['unknown', 'expired', 'signed_out', 'reuse', 'password_changed', 'login_off', 'left', 'unlinked']);

const readInstallId = (value) => (typeof value === 'string' && INSTALL_ID_RE.test(value) ? value : null);

const readRefreshToken = (value) => (typeof value === 'string' && REFRESH_TOKEN_RE.test(value) ? value : null);

/**
 * The phone's name for the session list ("Pixel 7"), shown back to its owner only. Optional, so
 * absent, null and blank all mean "none". At most 80 characters and no control characters, so a
 * label cannot break the list it is shown in.
 *
 * @returns {{ value: string|null } | { error: true }}
 */
function readDeviceLabel(value) {
  if (value === undefined || value === null) return { value: null };
  if (typeof value !== 'string') return { error: true };
  const label = value.trim();
  if (!label) return { value: null };
  if (Array.from(label).length > DEVICE_LABEL_MAX || /\p{Cc}/u.test(label)) return { error: true };
  return { value: label };
}

/** Whether a Scheduler token issued at `issuedAtMs` may still be traded for a kept sign-in. */
const isFreshSignIn = (issuedAtMs, nowMs) =>
  issuedAtMs > 0 && nowMs - issuedAtMs <= FRESH_SIGN_IN_MS && issuedAtMs - nowMs <= CLOCK_SKEW_MS;

/**
 * Has the portal password changed since this sign-in? users.password_changed_at is stamped by the
 * Scheduler's own password change and forgot-password reset (profileController.js:271-274,
 * authSecurityController.js:176-179). The Scheduler never checks it, so its 64-hour tokens outlive
 * a change; a kept sign-in renewed for 90 days must not, or a password somebody else learned would
 * stay good after its owner changed it. Whole seconds on both sides, as for the attendance cut-off
 * (services/attendanceAccounts.js:46-48): a token's iat is whole seconds.
 *
 * @returns {boolean|'unreadable'}
 */
function passwordChangedSince(changedAt, signedInAtMs) {
  if (!changedAt) return false;
  const parsed = Date.parse(changedAt);
  if (Number.isNaN(parsed)) return 'unreadable';
  return signedInAtMs < Math.floor(parsed / 1000) * 1000;
}

module.exports = {
  ACCESS_TOKEN_SECONDS,
  SESSION_MS,
  FRESH_SIGN_IN_MS,
  CLOCK_SKEW_MS,
  REFRESH_RETRY_MS,
  INSTALL_ID_RE,
  REFRESH_TOKEN_RE,
  DEVICE_LABEL_MAX,
  REVOKE_REASONS,
  REFUSAL_REASONS,
  readInstallId,
  readRefreshToken,
  readDeviceLabel,
  isFreshSignIn,
  passwordChangedSince,
};
