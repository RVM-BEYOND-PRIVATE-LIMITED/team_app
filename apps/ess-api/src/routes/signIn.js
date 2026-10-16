const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { istDay } = require('../lib/time');
const { readTyped, employeesOwning, resolveSignIn } = require('../policy/signIn');

/**
 * POST /api/ess/sign-in/resolve { identifier }, with no token (task A5): which Scheduler sign-in
 * this identifier belongs to. The rules are in policy/signIn.js.
 *
 * Rate-limited per address and per identifier on the route (app.js), before anything is read.
 *
 * Every request makes the same reads, in the same two rounds, whatever it finds: the first round
 * is everything that can be asked of the identifier itself, and the second the accounts of the
 * employees it matched, asked even when there are none (store.listUsersByIds). So "nobody" and
 * "more than one person" take as long as each other and come back as the same { kind: 'unknown' }.
 * The identifier is never logged.
 */
function signInResolveRoute({ store, now }) {
  return asyncRoute(async (req, res) => {
    const typed = readTyped(req.body && req.body.identifier);
    if (typed === null) throw new HttpError(400, 'BAD_IDENTIFIER', MESSAGES.BAD_IDENTIFIER);
    const today = istDay(now());

    const [byUsername, byPhoneNumber, byEmail, employees, locations, logins, withPassword] = await Promise.all([
      store.findUsersByUsername(typed),
      store.findUsersByPhoneNumber(typed),
      store.findUsersByEmail(typed.trim().toLowerCase()),
      store.listEmployeesForSignIn(),
      store.listLocations(),
      store.listAttendanceLogins(),
      store.listAttendanceLoginsWithPassword(),
    ]);
    const owning = employeesOwning(employees, typed, today);
    const linkedUsers = await store.listUsersByIds([...new Set(owning.map((e) => e.user_id).filter(Boolean))]);

    res.json(resolveSignIn({
      asTyped: [...byUsername, ...byPhoneNumber], byEmail, owning, linkedUsers, employees, logins, withPassword, locations, today,
    }));
  });
}

module.exports = { signInResolveRoute };
