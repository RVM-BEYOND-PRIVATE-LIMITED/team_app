const request = require('supertest');
const { buildApp, tokens } = require('./app');
const { call, get, post, drop } = require('./wave6a');
const { PNG_BASE64, FEEDBACK_ID, CONTEXT, SEEDED } = require('./feedbackFixtures');

/**
 * Wave 15 (#151): in-app feedback. One entry per documented status of every route it adds, and
 * `GET /me/capabilities`'s additive `feedback` block is covered by its role-by-role checks.
 */

const SEND = '/api/ess/feedback';
const LIST = '/api/ess/admin/feedback';
const SHOT = (id) => `/api/ess/admin/feedback/${id}/screenshot`;
const BUG = { kind: 'bug', message: 'The punch button stays grey.', context: CONTEXT };

const WAVE_15 = {
  'POST /api/ess/feedback': [
    ['201, a portal login with context', call('faculty', post(SEND, BUG))],
    ['201, an attendance session with a screenshot', call('attendance', post(SEND, {
      kind: 'suggestion', message: 'Show my leave balance on Home.', screenshot: { content_type: 'image/png', data_base64: PNG_BASE64 },
    }))],
    ['400 VALIDATION_FAILED', call('faculty', post(SEND, { kind: 'praise', message: 'Lovely app.' }))],
    ['401, no token', call('faculty', (app) => request(app).post(SEND).send(BUG))],
    ['403 NOT_LINKED', call('desk', post(SEND, BUG))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { feedback: { windowMs: 24 * 60 * 60 * 1000, limit: 1 } } });
      await post(SEND, BUG)(app, tokens.portal(people.faculty));
      return post(SEND, BUG)(app, tokens.portal(people.faculty));
    }],
    ['503 MODULE_NOT_INSTALLED', call('faculty', post(SEND, BUG), { prepare: drop('hr_ess_feedback') })],
  ],
  'GET /api/ess/admin/feedback': [
    ['200, the super admin', call('super_admin', get(LIST), { setup: SEEDED })],
    ['200, one kind, nothing yet', call('super_admin', get(`${LIST}?kind=suggestion`))],
    ['400 VALIDATION_FAILED', call('super_admin', get(`${LIST}?kind=praise`))],
    ['401, no token', call('super_admin', (app) => request(app).get(LIST))],
    ['403 FEEDBACK_ACCESS_DENIED, the CEO', call('ceo', get(LIST))],
    ['403 PORTAL_LOGIN_REQUIRED', call('attendance', get(LIST))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(LIST)(app, tokens.portal(people.super_admin));
      return get(LIST)(app, tokens.portal(people.super_admin));
    }],
    ['503 MODULE_NOT_INSTALLED', call('super_admin', get(LIST), { prepare: drop('hr_ess_feedback') })],
  ],
  'GET /api/ess/admin/feedback/{id}/screenshot': [
    ['200, the super admin', call('super_admin', get(SHOT(FEEDBACK_ID(2))), { setup: SEEDED })],
    ['400 VALIDATION_FAILED', call('super_admin', get(SHOT('nope')))],
    ['401, no token', call('super_admin', (app) => request(app).get(SHOT(FEEDBACK_ID(2))))],
    ['403 FEEDBACK_ACCESS_DENIED', call('hr', get(SHOT(FEEDBACK_ID(2))), { setup: SEEDED })],
    ['404 NOT_FOUND, no screenshot', call('super_admin', get(SHOT(FEEDBACK_ID(1))), { setup: SEEDED })],
    ['404 NOT_FOUND, no such feedback', call('super_admin', get(SHOT(FEEDBACK_ID(9))))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ setup: SEEDED, limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(SHOT(FEEDBACK_ID(2)))(app, tokens.portal(people.super_admin));
      return get(SHOT(FEEDBACK_ID(2)))(app, tokens.portal(people.super_admin));
    }],
    ['503 MODULE_NOT_INSTALLED', call('super_admin', get(SHOT(FEEDBACK_ID(2))), { prepare: drop('hr_ess_feedback') })],
  ],
};

module.exports = { WAVE_15 };
