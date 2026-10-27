const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { idParam } = require('../lib/validate');
const { istDay } = require('../lib/time');
const { isActive } = require('../policy/employment');
const { canSeePhone, isNotice } = require('../policy/me');
const { contactContext } = require('../lib/contactCards');
const { workExperienceView, profileDetailsView, earnedBadges } = require('../lib/profileKit');

/**
 * Issue #31: one colleague's profile, read live by any signed-in employee. The employee card
 * follows the same contact rule as the directory (KP's rule A: self, HR's roles, and the manager
 * chain above the person); the phone is null for a report looking at their manager. The photo is
 * an inline data URI, so the sheet does not depend on the storage host being reachable. About,
 * likes and dislikes are free text the owner edits; blood group stays read-only here. Only the
 * visible work-experience entries are returned. Archived and exited people are 404.
 */

const ref = (row) => (row ? { id: row.id, name: row.name } : null);

/** GET /api/ess/directory/{id} */
function colleagueProfile({ store }) {
  return asyncRoute(async (req, res) => {
    const id = idParam(req.params.id);
    const today = istDay(new Date());
    const profile = await store.getProfile(id);
    if (!profile || !isActive(profile, today)) {
      throw new HttpError(404, 'NOT_FOUND', MESSAGES.EMPLOYEE_NOT_FOUND);
    }

    const { employee, role } = req.auth;
    const ctx = await contactContext({ store, viewer: employee, role, today });
    const [personal, details, experience, badges] = await Promise.all([
      store.getPersonalDetails(profile.id),
      store.getProfileDetails(profile.id),
      store.listVisibleWorkExperience(profile.id),
      store.listPraiseBadges(profile.id),
    ]);
    const social = profileDetailsView(details, personal);
    const phone = canSeePhone({
      viewer: employee,
      colleague: profile,
      role,
      byId: ctx.byId,
    }) ? profile.phone : null;

    res.json({
      employee: {
        id: profile.id,
        full_name: profile.full_name,
        employee_code: profile.employee_code ?? null,
        designation: profile.designation ?? null,
        department: ref(ctx.deptById.get(profile.department_id)),
        branch: ref(ctx.branchById.get(profile.branch_id)),
        email: profile.email ?? null,
        phone: phone ?? null,
        employment_status: profile.employment_status ?? null,
        notice_period: isNotice(profile),
        date_of_joining: profile.date_of_joining ?? null,
        date_of_birth: personal?.date_of_birth ?? null,
        photo_url: await store.photoDataUrl(profile.photo_path),
      },
      about: social.about,
      likes: social.likes,
      dislikes: social.dislikes,
      anniversary_date: social.anniversary_date,
      blood_group: social.blood_group,
      earned_badges: earnedBadges(badges),
      work_experience: experience.map(workExperienceView),
    });
  });
}

module.exports = { colleagueProfile };
