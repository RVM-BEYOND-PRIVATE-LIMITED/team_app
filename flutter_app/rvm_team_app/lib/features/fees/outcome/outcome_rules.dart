/// The outcome form's date rule, the Scheduler's own (team_app #53, item 8).
///
/// The Scheduler refuses a next follow-up date on or before IST today
/// (utils/followUpFallback.js, `validateProvidedDate`, applied with
/// `getISTDateString()` in controllers/followUpController.js): a call logged
/// takes the student off Today and Overdue until midnight, so a call set for
/// today never comes up. The form checks the same rule before it saves.
library;

/// The Scheduler's refusal, word for word (utils/followUpFallback.js:76).
const nextFollowUpDateRefused =
    'The next follow-up date must be after today. Pick tomorrow or a later date.';

/// IST is UTC+5:30 all year; the Scheduler adds the same 330 minutes
/// (utils/dateUtils.js, `getISTDateString`).
const _istOffset = Duration(hours: 5, minutes: 30);

/// The IST calendar day at [nowUtc], as a date (midnight, no time).
///
/// [nowUtc] is an instant; a local [DateTime] is read as the same instant.
/// The answer does not depend on the phone's own time zone.
DateTime istToday(DateTime nowUtc) {
  final ist = nowUtc.toUtc().add(_istOffset);
  return DateTime(ist.year, ist.month, ist.day);
}

/// The first day the form offers: the IST day after [istToday].
DateTime istTomorrow(DateTime nowUtc) {
  final today = istToday(nowUtc);
  return DateTime(today.year, today.month, today.day + 1);
}

/// Null when [date] may be the next follow-up date at [nowUtc], otherwise the
/// Scheduler's message ([nextFollowUpDateRefused]).
///
/// No date is allowed, as on the Scheduler (followUpFallback.js: an empty
/// value is `{ ok: true, date: null }`). Only the year, month and day of
/// [date] are read, as the Scheduler compares `YYYY-MM-DD` strings.
String? validateNextFollowUpDate(DateTime? date, {required DateTime nowUtc}) {
  if (date == null) return null;
  return _day(date) <= _day(istToday(nowUtc)) ? nextFollowUpDateRefused : null;
}

/// A calendar day as one comparable number, `YYYYMMDD`.
int _day(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
