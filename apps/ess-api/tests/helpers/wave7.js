const { buildApp, tokens } = require('./app');
const { call, get, post, shared } = require('./wave6a');
const H = require('./helpdeskFixtures');

/**
 * Wave 7 (Phase 2B): the Helpdesk's scenario table, one entry per documented status of every
 * route the Helpdesk adds (G1 to G5). tests/contract.test.js merges it with the earlier waves:
 * the routes covered must be exactly the routes the app serves, and every documented status must
 * be provoked here.
 *
 * The scenarios run on the same in-memory app and the same fixtures as the other waves
 * (tests/helpers/app.js buildApp, tests/helpers/helpdeskFixtures.js), so a Helpdesk request here
 * is the real route, the real store and the real contract check.
 */

/**
 * One ticket of any state, with the thread the views read: the seed's `opened` event and a
 * comment by the team (an admin — the IT and lab queue's own role), raised by the faculty
 * fixture in IT and lab equipment unless the scenario says otherwise.
 */
const TICKET = (change = {}) => (w) => {
  H.seedCategories(w);
  w.tables.hr_ess_helpdesk_tickets = [H.ticketRow(w.people.faculty.employee.id, 1, change)];
  w.tables.hr_ess_helpdesk_messages = [
    H.messageRow(H.TICKET_ID(1), 1, null),
    H.messageRow(H.TICKET_ID(1), 2, w.people.admin.employee.id),
  ];
};

/** A payroll ticket instead: the queue that does not hold tickets, for the hold refusal. */
const PAYROLL = (change = {}) => (w) => {
  TICKET({ category_id: H.CAT('payroll'), priority: 'high', ...change })(w);
};

/** A settled ticket inside the 7-day reopen window (resolved at 11:00 IST today). */
const SETTLED = { status: 'resolved', resolved_at: '2026-10-16T06:00:00+00:00' };

/** A ticket settled 8 days ago: the reopen window has gone. */
const CLOSED_LONG_AGO = {
  status: 'closed', resolved_at: '2026-10-08T05:00:00+00:00', closed_at: '2026-10-08T05:30:00+00:00',
};

const raise = (body) => post('/api/ess/helpdesk/tickets', body);
const raiseBody = () => ({
  category: 'it_lab', subject: 'The lab PCs will not start.', body: 'Six machines in Lab 2 stay on the boot screen.',
});

/** The one-ticket address the scenario tables repeat. */
const at = (suffix) => `/api/ess/helpdesk/tickets/${H.TICKET_ID(1)}${suffix || ''}`;

const WAVE_7 = {
  'GET /api/ess/helpdesk/categories': [
    ['200, the rules', call('faculty', get('/api/ess/helpdesk/categories'), { setup: H.seedCategories })],
    ...shared('faculty', 'get', '/api/ess/helpdesk/categories', { table: 'hr_ess_helpdesk_categories' }),
  ],
  'POST /api/ess/helpdesk/tickets': [
    ['201, a raise', call('faculty', raise(raiseBody()), { setup: H.seedCategories })],
    ['400 VALIDATION_FAILED, no category', call('faculty', raise({ subject: 'The lab PCs will not start.', body: 'Six machines in Lab 2 stay on the boot screen.' }), { setup: H.seedCategories })],
    ['404 NOT_FOUND, a slug that is not one', call('faculty', raise({ ...raiseBody(), category: 'roof' }), { setup: H.seedCategories })],
    ['429 RATE_LIMITED, the Helpdesk\'s own bucket', async () => {
      const world = buildApp({ limits: { helpdeskTickets: { windowMs: 60 * 60 * 1000, limit: 1 } } });
      const token = tokens.portal(world.people.faculty);
      const send = () => post('/api/ess/helpdesk/tickets', raiseBody())(world.app, token);
      await send();
      return send();
    }],
    ...shared('faculty', 'post', '/api/ess/helpdesk/tickets', { body: raiseBody(), table: 'hr_ess_helpdesk_tickets', seed: H.seedCategories }),
  ],
  'GET /api/ess/helpdesk/tickets': [
    ['200, mine', call('faculty', get('/api/ess/helpdesk/tickets'), { setup: TICKET() })],
    ['400 VALIDATION_FAILED, a status it does not take', call('faculty', get('/api/ess/helpdesk/tickets?status=roof'))],
    ...shared('faculty', 'get', '/api/ess/helpdesk/tickets', { table: 'hr_ess_helpdesk_tickets' }),
  ],
  'GET /api/ess/helpdesk/tickets/{id}': [
    ['200, the thread', call('faculty', get(at()), { setup: TICKET() })],
    ['400 VALIDATION_FAILED, not an id', call('faculty', get('/api/ess/helpdesk/tickets/not-an-id'))],
    ['404 NOT_FOUND, somebody else\'s ticket', call('faculty', get(at()), { setup: (w) => { TICKET({ created_by: w.people.hod.employee.id })(w); } })],
    ...shared('faculty', 'get', at(), { table: 'hr_ess_helpdesk_messages', seed: TICKET() }),
  ],
  'POST /api/ess/helpdesk/tickets/{id}/comments': [
    ['201, the team answers', call('admin', post(at('/comments'), { body: 'Replacing the switch today.' }), { setup: TICKET() })],
    ['400 VALIDATION_FAILED, an empty comment', call('admin', post(at('/comments'), { body: '   ' }), { setup: TICKET() })],
    ['403 HELPDESK_AGENT_ONLY, oversight reads but does not act', call('hr', post(at('/comments'), { body: 'Noted.' }), { setup: TICKET() })],
    ['404 NOT_FOUND, no such ticket', call('admin', post(`/api/ess/helpdesk/tickets/${H.TICKET_ID(9)}/comments`, { body: 'Hello.' }), { setup: TICKET() })],
    ...shared('admin', 'post', at('/comments'), { body: { body: 'Hello.' }, table: 'hr_ess_helpdesk_messages', seed: TICKET() }),
  ],
  'POST /api/ess/helpdesk/tickets/{id}/withdraw': [
    ['200, mine, still open', call('faculty', post(at('/withdraw')), { setup: TICKET() })],
    ['403 HELPDESK_AGENT_ONLY, the team cannot withdraw it', call('admin', post(at('/withdraw')), { setup: TICKET() })],
    ['404 NOT_FOUND, no such ticket', call('faculty', post(`/api/ess/helpdesk/tickets/${H.TICKET_ID(9)}/withdraw`), { setup: TICKET() })],
    ['409 HELPDESK_NOT_OPEN, already in progress', call('faculty', post(at('/withdraw')), { setup: TICKET({ status: 'in_progress' }) })],
    ...shared('faculty', 'post', at('/withdraw'), { table: 'hr_ess_helpdesk_tickets', seed: TICKET() }),
  ],
  'POST /api/ess/helpdesk/tickets/{id}/reopen': [
    ['200, mine, settled this week', call('faculty', post(at('/reopen')), { setup: TICKET(SETTLED) })],
    ['403 HELPDESK_AGENT_ONLY, the team cannot reopen it', call('admin', post(at('/reopen')), { setup: TICKET(SETTLED) })],
    ['404 NOT_FOUND, no such ticket', call('faculty', post(`/api/ess/helpdesk/tickets/${H.TICKET_ID(9)}/reopen`), { setup: TICKET(SETTLED) })],
    ['409 HELPDESK_NOT_CLOSED, still open', call('faculty', post(at('/reopen')), { setup: TICKET() })],
    ['409 HELPDESK_REOPEN_WINDOW, settled 8 days ago', call('faculty', post(at('/reopen')), { setup: TICKET(CLOSED_LONG_AGO) })],
    ...shared('faculty', 'post', at('/reopen'), { table: 'hr_ess_helpdesk_tickets', seed: TICKET(SETTLED) }),
  ],
  'POST /api/ess/helpdesk/tickets/{id}/close': [
    ['200, mine, with a rating', call('faculty', post(at('/close'), { closing_reason: 'Fixed it myself: the UPS plug had come loose.', rating: 4 }), { setup: TICKET() })],
    ['400 VALIDATION_FAILED, no reason', call('faculty', post(at('/close'), { closing_reason: '  ', rating: 4 }), { setup: TICKET() })],
    ['403 HELPDESK_AGENT_ONLY, the team cannot close it', call('admin', post(at('/close'), { closing_reason: 'Done.' }), { setup: TICKET() })],
    ['404 NOT_FOUND, no such ticket', call('faculty', post(`/api/ess/helpdesk/tickets/${H.TICKET_ID(9)}/close`, { closing_reason: 'Done.' }), { setup: TICKET() })],
    ['409 HELPDESK_TRANSITION, already closed', call('faculty', post(at('/close'), { closing_reason: 'Done.' }), { setup: TICKET(CLOSED_LONG_AGO) })],
    ...shared('faculty', 'post', at('/close'), { body: { closing_reason: 'Done.' }, table: 'hr_ess_helpdesk_tickets', seed: TICKET() }),
  ],
  'POST /api/ess/helpdesk/tickets/{id}/claim': [
    ['200, the team takes it', call('admin', post(at('/claim')), { setup: TICKET() })],
    ['403 HELPDESK_AGENT_ONLY, the raiser cannot claim their own', call('faculty', post(at('/claim')), { setup: TICKET() })],
    ['404 NOT_FOUND, no such ticket', call('admin', post(`/api/ess/helpdesk/tickets/${H.TICKET_ID(9)}/claim`), { setup: TICKET() })],
    ['409 HELPDESK_NOT_LIVE, settled', call('admin', post(at('/claim')), { setup: TICKET(SETTLED) })],
    ['409 HELPDESK_ALREADY_CLAIMED, taken by a colleague', call('admin', post(at('/claim')), {
      setup: (w) => {
        TICKET({ status: 'in_progress', assignee_id: w.people.admin_manager.employee.id, claimed_at: H.AT })(w);
      },
    })],
    ...shared('admin', 'post', at('/claim'), { table: 'hr_ess_helpdesk_tickets', seed: TICKET() }),
  ],
  'POST /api/ess/helpdesk/tickets/{id}/status': [
    ['200, resolved', call('admin', post(at('/status'), { status: 'resolved' }), { setup: TICKET() })],
    ['400 VALIDATION_FAILED, a status it does not take', call('admin', post(at('/status'), { status: 'roof' }), { setup: TICKET() })],
    ['400 VALIDATION_FAILED, a category that does not hold', call('accounts_admin', post(at('/status'), { status: 'on_hold' }), { setup: PAYROLL() })],
    ['403 HELPDESK_AGENT_ONLY, oversight reads but does not act', call('hr', post(at('/status'), { status: 'in_progress' }), { setup: TICKET() })],
    ['404 NOT_FOUND, no such ticket', call('admin', post(`/api/ess/helpdesk/tickets/${H.TICKET_ID(9)}/status`, { status: 'resolved' }), { setup: TICKET() })],
    ['409 HELPDESK_TRANSITION, back from resolved', call('admin', post(at('/status'), { status: 'in_progress' }), { setup: TICKET(SETTLED) })],
    ...shared('admin', 'post', at('/status'), { body: { status: 'resolved' }, table: 'hr_ess_helpdesk_tickets', seed: TICKET() }),
  ],
  'GET /api/ess/helpdesk/queue': [
    ['200, the live work', call('admin', get('/api/ess/helpdesk/queue'), { setup: TICKET() })],
    ['200, empty for a role no category serves', call('faculty', get('/api/ess/helpdesk/queue'), { setup: TICKET() })],
    ['400 VALIDATION_FAILED, a status it does not take', call('admin', get('/api/ess/helpdesk/queue?status=roof'))],
    ['400 VALIDATION_FAILED, a category that is not theirs', call('admin', get('/api/ess/helpdesk/queue?category=payroll'), { setup: H.seedCategories })],
    ['403 PORTAL_LOGIN_REQUIRED, an attendance session', call('attendance', get('/api/ess/helpdesk/queue'), { setup: TICKET() })],
    ...shared('admin', 'get', '/api/ess/helpdesk/queue', { table: 'hr_ess_helpdesk_categories', seed: TICKET() }),
  ],
};

module.exports = { WAVE_7, TICKET, PAYROLL, SETTLED, raiseBody };