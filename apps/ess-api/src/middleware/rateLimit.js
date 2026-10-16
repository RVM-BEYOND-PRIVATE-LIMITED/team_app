const { rateLimit, ipKeyGenerator } = require('express-rate-limit');
const { MESSAGES } = require('../lib/errors');

/**
 * Two limits, because a whole branch shares one office address (task A6).
 *
 *   per address, before sign-in   bounds what one network can send, including requests with no
 *                                 token or a forged one. Generous, because everybody at a branch
 *                                 opening the app at nine o'clock comes from one office Wi-Fi
 *                                 address, and the Scheduler's 300 a minute per address is already
 *                                 shared by the web portal from that same address.
 *   per employee, after sign-in   the real per-person cap, so one person's misbehaving phone
 *                                 cannot use up the office's allowance for everybody else.
 *
 * Both count in this process's memory, as the Scheduler's limiters do: there is exactly one
 * ESS instance (ADR-0005), and a restart starting the counts again is acceptable.
 */
const DEFAULT_LIMITS = Object.freeze({
  perIp: Object.freeze({ windowMs: 60 * 1000, limit: 600 }),
  perEmployee: Object.freeze({ windowMs: 60 * 1000, limit: 120 }),
});

const refuse = (_req, res) => res.status(429).json({ error: MESSAGES.RATE_LIMITED, code: 'RATE_LIMITED' });

const common = ({ windowMs, limit }) => ({
  windowMs,
  limit,
  // RateLimit-* headers and Retry-After, as the Scheduler's limiters send them.
  standardHeaders: true,
  legacyHeaders: false,
  handler: refuse,
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

/** Mounted after employeeAuth, which sets req.auth; one count per person, whichever sign-in they used. */
function createEmployeeLimiter(limits = DEFAULT_LIMITS.perEmployee) {
  return rateLimit({
    ...common(limits),
    keyGenerator: (req) => `employee:${req.auth.employee.id}`,
  });
}

module.exports = { DEFAULT_LIMITS, createIpLimiter, createEmployeeLimiter };
