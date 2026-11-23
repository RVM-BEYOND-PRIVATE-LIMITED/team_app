/**
 * #151: in-app feedback. A real 1x1 PNG and a JPEG's first bytes, and rows to seed the list with.
 */

const PNG_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
const JPEG_BASE64 = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(60, 1)]).toString('base64');

const FEEDBACK_ID = (n) => `fb000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const CONTEXT = Object.freeze({
  screen: '/home',
  app_version: '0.1.6',
  build_number: '7',
  platform: 'android',
  os_version: '14',
  device_model: 'Redmi Note 12',
});

/** One stored row; `change` overrides any column. */
const feedbackRow = (employeeId, n, change = {}) => ({
  id: FEEDBACK_ID(n),
  employee_id: employeeId,
  kind: 'bug',
  message: `Feedback number ${n}.`,
  screen: null,
  app_version: null,
  build_number: null,
  platform: null,
  os_version: null,
  device_model: null,
  screenshot_path: null,
  screenshot_content_type: null,
  screenshot_bytes: null,
  created_at: `2026-10-16T06:${String(n % 60).padStart(2, '0')}:00+00:00`,
  ...change,
});

const withScreenshot = (employeeId) => ({
  screenshot_path: `feedback/${employeeId}/6f0a3c1e-8b2d-4c5a-9e7f-1d2b3a4c5d6f.png`,
  screenshot_content_type: 'image/png',
  screenshot_bytes: 68,
});

/** A world setup that seeds the faculty member's two items, the second with a screenshot. */
const SEEDED = (w) => {
  const id = w.people.faculty.employee.id;
  w.tables.hr_ess_feedback = [
    feedbackRow(id, 1, { kind: 'suggestion', ...CONTEXT }),
    feedbackRow(id, 2, withScreenshot(id)),
  ];
};

module.exports = { PNG_BASE64, JPEG_BASE64, FEEDBACK_ID, CONTEXT, feedbackRow, withScreenshot, SEEDED };
