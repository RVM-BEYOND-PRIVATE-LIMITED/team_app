import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('Parse application', () {
    test('applicationDetail reads the `job` nested key + maps status', () {
      final d = Parse.applicationDetail({
        'id': 'a1',
        'status': 'interview_scheduled',
        'cover_note': 'hi',
        'created_at': '2026-07-01T00:00:00Z',
        'job': {
          'id': 'j1',
          'title': 'CAD Designer',
          'location': 'Pune',
          'salary_min_lpa': 5,
          'salary_max_lpa': 7,
          'company': {'name': 'Acme'},
        },
      });
      expect(d.jobTitle, 'CAD Designer');
      expect(d.companyName, 'Acme');
      expect(d.status, ApplicationStatus.interviewScheduled);
      expect(d.canWithdraw, isFalse); // interview stage — not withdrawable
    });

    test('applicationDetail canWithdraw true for pending/under_review', () {
      for (final s in ['pending', 'under_review']) {
        final d = Parse.applicationDetail({'id': 'a', 'status': s, 'job': {'id': 'j'}});
        expect(d.canWithdraw, isTrue, reason: s);
      }
    });

    test('list parser still reads the `job_postings` key', () {
      final list = Parse.applications([
        {'id': 'a1', 'status': 'pending', 'job_postings': {'id': 'j1', 'title': 'X', 'company': {'name': 'Y'}}}
      ]);
      expect(list.single.jobTitle, 'X');
      expect(list.single.companyName, 'Y');
    });
  });
}
