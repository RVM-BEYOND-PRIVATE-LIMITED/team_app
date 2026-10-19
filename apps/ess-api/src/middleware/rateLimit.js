const crypto = require('crypto');
const { rateLimit, ipKeyGenerator } = require('express-rate-limit');
const { MESSAGES } = require('../lib/errors');
const { signInKey } = require('../policy/signIn');

/**
 * Two limits on everything, because a whole branch shares one office address (task A6).
 *
 *   per address, before sign-in   bounds what one network can send, including requests with no
 *                                 token or a forged one. Generous, because everybody at a branch
 *                                 opening the app at nine o'clock comes from one office Wi-Fi
 *                                 address, and the Scheduler's 300 a minute per address is already
 *                                 shared by the web portal from that same address.
 *   per employee, after sign-in   the real per-person cap, so one person's misbehaving phone
 *                                 cannot use up the office's allowance for everybody else.
 *
 * And tighter ones on the endpoints that take no token or create a sign-in:
 *
 *   sessionPerIp         refresh, and sign-out by refresh token: about one refresh an hour per
 *                        phone, so 120 in 15 minutes still lets a whole branch open the app at
 *                        nine on one office address.
 *   exchangePerEmployee  trading a fresh sign-in for a kept one: once per sign-in.
 *   signInPerIp          the one-field resolver: as many as the Scheduler's own attendance
 *                        sign-in allows one address (middleware/punchCodeLimiter.js:19-26), so
 *                        it is no faster a way to try identifiers than the sign-in itself.
 *   signInPerIdentifier  the resolver again, per identifier from any address, so asking about one
 *                        person from many addresses gets no further.
 *   mockReports          mocked-location reports (B14), per employee per day, counted apart
 *                        from the per-employee limit.
 *   wallPosts            Wall posts, praise, wishes and announcements, per employee per day
 *                        (F1, F3, F5).
 *   wallComments         comments and replies, per employee per day (F2).
 *   wallReactions        reactions, per employee per minute: tapping six emoji is normal use.
 *
 * All count in this process's memory, as the Scheduler's limiters do: there is exactly one
 * ESS instance (ADR-0005), and a restart starting the counts again is acceptable.
 */
const FIFTEEN_MINUTES = 15 * 60 * 1000;

const DEFAULT_LIMITS = Object.freeze({
  perIp: Object.freeze({ windowMs: 60 * 1000, limit: 600 }),
  perEmployee: Object.freeze({ windowMs: 60 * 1000, limit: 120 }),
  sessionPerIp: Object.freeze({ windowMs: FIFTEEN_MINUTES, limit: 120 }),
  exchangePerEmployee: Object.freeze({ windowMs: FIFTEEN_MINUTES, limit: 10 }),
  signInPerIp: Object.freeze({ windowMs: FIFTEEN_MINUTES, limit: 40 }),
  signInPerIdentifier: Object.freeze({ windowMs: FIFTEEN_MINUTES, limit: 10 }),
  // Mocked-location reports (B14), per employee per 24 hours. A real person refused for a mocked
  // fix tries a handful of times; a phone stuck in a retry loop must not fill HR's list.
  mockReports: Object.freeze({ windowMs: 24 * 60 * 60 * 1000, limit: 30 }),
  // The Wall (F1, F2): posts and comments per employee per day, so a stuck phone cannot fill the
  // feed; reactions per minute, because tapping six emoji on one post is normal use.
  wallPosts: Object.freeze({ windowMs: 24 * 60 * 60 * 1000, limit: 60 }),
  wallComments: Object.freeze({ windowMs: 24 * 60 * 60 * 1000, limit: 200 }),
  wallReactions: Object.freeze({ windowMs: 60 * 1000, limit: 60 }),
});

const refuseWith = (message) => (_req, res) => res.status(429).json({ error: message, code: 'RATE_LIMITED' });

const common = ({ windowMs, limit }, message = MESSAGES.RATE_LIMITED) => ({
  windowMs,
  limit,
  // RateLimit-* headers and Retry-After, as the Scheduler's limiters send them.
  standardHeaders: true,
  legacyHeaders: false,
  handler: refuseWith(message),
});

function createIpLimiter(limits = DEFAULT_LIMITS.perIp) {
  return rateLimit({
    ...common(limits),
    // req.ip is the address nginx saw, through `trust proxy` 1 (app.js). ipKeyGenerator puts an
    // IPv6 address in its /56, so a phone cannot dodge the limit by stepping through the many
    // addresses its own network hands it.
    keyGenerator: (req) => ipKeyGenerator(req.ip),
  });
}

/**
 * Mounted after employeeAuth, which sets req.auth; one count per person, whichever sign-in they
 * used. Each limiter counts in its own store, so a narrower one (mocked-location reports) adds to
 * the per-employee limit rather than sharing its count.
 */
function createEmployeeLimiter(limits = DEFAULT_LIMITS.perEmployee, message = MESSAGES.RATE_LIMITED) {
  return rateLimit({
    ...common(limits, message),
    keyGenerator: (req) => `employee:${req.auth.employee.id}`,
  });
}

/**
 * Per identifier typed at the one-field sign-in, whatever the address. The key is the identifier
 * in the form the Scheduler compares it (policy/signIn.js signInKey: any spelling of one phone
 * number is one bucket), hashed, so the limiter's memory holds no phone numbers or addresses.
 */
function createIdentifierLimiter(limits = DEFAULT_LIMITS.signInPerIdentifier) {
  return rateLimit({
    ...common(limits),
    keyGenerator: (req) => {
      const typed = req.body && typeof req.body.identifier === 'string' ? req.body.identifier : '';
      return `identifier:${crypto.createHash('sha256').update(signInKey(typed)).digest('hex')}`;
    },
  });
}

module.exports = { DEFAULT_LIMITS, createIpLimiter, createEmployeeLimiter, createIdentifierLimiter };
