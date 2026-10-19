import 'package:data/data.dart';
import 'package:test/test.dart';

void main() {
  test('Parse.savedJobs reads {saved_jobs:[{id, job}]} → savedId + nested job', () {
    final saved = Parse.savedJobs({
      'saved_jobs': [
        {
          'id': 'saved-rec-1',
          'saved_at': '2026-07-01',
          'job': {
            'id': 'job-1',
            'title': 'CAD Designer',
            'job_type': 'full_time',
            'company': {'name': 'Acme'},
          },
        }
      ],
    });
    expect(saved, hasLength(1));
    expect(saved.single.savedId, 'saved-rec-1');
    expect(saved.single.job.id, 'job-1');
    expect(saved.single.job.title, 'CAD Designer');
    expect(saved.single.job.companyName, 'Acme');
  });
}
