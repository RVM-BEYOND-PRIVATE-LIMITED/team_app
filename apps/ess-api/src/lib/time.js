/**
 * RVM's days turn over at midnight IST (Asia/Kolkata), whatever zone the server's clock is in.
 *
 * The same arithmetic as the Scheduler's istDay (services/attendancePunch.js:172 at c28b9ca).
 * India has no daylight saving, so a fixed +05:30 is exact and needs no time-zone database.
 */
const IST_OFFSET_MINUTES = 330;

/** The IST calendar day of an instant, as YYYY-MM-DD. */
const istDay = (instant) => new Date(instant.getTime() + IST_OFFSET_MINUTES * 60 * 1000).toISOString().slice(0, 10);

module.exports = { IST_OFFSET_MINUTES, istDay };
