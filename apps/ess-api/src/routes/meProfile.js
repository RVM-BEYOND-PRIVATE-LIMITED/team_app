const crypto = require('crypto');
const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, invalid } = require('../lib/validate');
const { recordAfter } = require('../lib/audit');
const { isNotice, timelineTitle } = require('../policy/me');

/**
 * Tasks E1, E10 and E12: my profile — Summary, Job and Timeline from the HR record, Personal
 * from the 1B table, and the photo through a short-lived signed link. Never pay, never
 * performance tags, never HR remarks (the timeline's allowlist drops them, and the values are
 * never read at all).
 *
 * The photo change is the one write the ESS makes to `hr_employees`, and only to the photo
 * columns the Scheduler's own setPhoto writes (path, updated stamp and by). The old file is
 * left in the bucket: deleting is irreversible, and cleanup is a job for later.
 */

const CONTENT_TYPES = Object.freeze({ 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' });
const MAX_PHOTO_BYTES = 1024 * 1024; // 1 MB, what the app compresses to
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

const personalView = (p) => ({
  date_of_birth: p?.date_of_birth ?? null,
  blood_group: p?.blood_group ?? null,
  address_line1: p?.address_line1 ?? null,
  address_line2: p?.address_line2 ?? null,
  city: p?.city ?? null,
  state: p?.state ?? null,
  pincode: p?.pincode ?? null,
  emergency_name: p?.emergency_name ?? null,
  emergency_relation: p?.emergency_relation ?? null,
  emergency_phone: p?.emergency_phone ?? null,
});

/** GET /api/ess/me/profile */
function myProfile({ store }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const [profile, personal, timeline, departments] = await Promise.all([
      store.getProfile(employee.id),
      store.getPersonalDetails(employee.id),
      store.listTimeline(employee.id),
      store.listAllDepartments(),
    ]);
    if (!profile) throw new HttpError(404, 'NOT_FOUND', MESSAGES.EMPLOYEE_NOT_FOUND);
    const [manager, branches] = await Promise.all([
      profile.manager_id ? store.getEmployeeById(profile.manager_id) : null,
      profile.branch_id ? store.listBranches([profile.branch_id]) : [],
    ]);
    const department = departments.find((d) => d.id === profile.department_id) || null;
    const branch = branches[0] || null;
    res.json({
      employee: {
        id: profile.id,
        full_name: profile.full_name,
        employee_code: profile.employee_code ?? null,
        designation: profile.designation ?? null,
        department: department ? { id: department.id, name: department.name } : null,
        branch: branch ? { id: branch.id, name: branch.name } : null,
        manager: manager ? { id: manager.id, full_name: manager.full_name, designation: manager.designation ?? null } : null,
        date_of_joining: profile.date_of_joining ?? null,
        employment_status: profile.employment_status ?? null,
        notice_period: isNotice(profile),
        email: profile.email ?? null,
        phone: profile.phone ?? null,
        photo_url: await store.signedPhotoUrl(profile.photo_path),
      },
      personal: personalView(personal),
      timeline: timeline
        .map((e) => ({ id: e.id, title: timelineTitle(e.event_type, e.changed_keys), at: e.occurred_at }))
        .filter((e) => e.title),
    });
  });
}

/** PUT /api/ess/me/photo { photo_base64, content_type } */
function putMyPhoto({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee, userId } = req.auth;
    const body = bodyWith(req, ['photo_base64', 'content_type']);
    const data = requiredText(body.photo_base64, { min: 16, max: 2_100_000, message: MESSAGES.PHOTO_FORMAT });
    if (!BASE64.test(data)) throw invalid(MESSAGES.PHOTO_FORMAT);
    const ext = CONTENT_TYPES[body.content_type];
    if (!ext) throw invalid(MESSAGES.PHOTO_TYPE);
    const buffer = Buffer.from(data, 'base64');
    if (!buffer.length || buffer.length > MAX_PHOTO_BYTES) throw invalid(MESSAGES.PHOTO_SIZE);

    const path = `hr/employee/${employee.id}/photo/${crypto.randomUUID()}_photo.${ext}`;
    const at = now().toISOString();
    await store.uploadProfilePhoto(path, buffer, body.content_type);
    const saved = await store.setEmployeePhoto(employee.id, {
      photo_path: path,
      photo_updated_at: at,
      photo_updated_by: userId ?? null,
      updated_by: userId ?? null,
      updated_at: at,
    });
    if (!saved) {
      // Never leave a file in the bucket with no row pointing at it.
      await store.removeStorageObjects([path]);
      throw new HttpError(404, 'NOT_FOUND', MESSAGES.EMPLOYEE_NOT_FOUND);
    }
    await recordAfter(store, req, { action: 'me.photo.updated', targetEmployeeId: employee.id });
    res.json({ employee: { id: employee.id, photo_url: await store.signedPhotoUrl(path) } });
  });
}

module.exports = { myProfile, putMyPhoto, personalView };
