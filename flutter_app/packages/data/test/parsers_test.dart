import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('Parse.jobList', () {
    test('reads the browse envelope { jobs: [...] } into JobSummary', () {
      final jobs = Parse.jobList({
        'jobs': [
          {
            'id': 'j1',
            'title': 'Junior CAD Designer',
            'job_type': 'full_time',
            'company': {'name': 'Lumen Aerospace'},
            'location': 'Pune',
            'salary_min_lpa': 4.5,
            'salary_max_lpa': 6,
            'required_skills': ['AutoCAD', 'GD&T'],
            'openings': 4,
          }
        ],
      });
      expect(jobs, hasLength(1));
      final j = jobs.first;
      expect(j.title, 'Junior CAD Designer');
      expect(j.jobType, JobType.fullTime);
      expect(j.companyName, 'Lumen Aerospace');
      expect(j.salaryMaxLpa, 6);
      expect(j.requiredSkills, ['AutoCAD', 'GD&T']);
      expect(j.openings, 4);
    });

    test('tolerates a bare list and unknown enums', () {
      final jobs = Parse.jobList([
        {'id': 'j2', 'title': 'X', 'job_type': 'weird'}
      ]);
      expect(jobs.single.jobType, JobType.unknown);
    });
  });

  test('Parse.candidate merges skills + cad_software', () {
    final c = Parse.candidate({
      'id': 'c1',
      'full_name': 'Aarav',
      'skills': ['GD&T'],
      'cad_software': ['AutoCAD', 'GD&T'],
      'profile_completion_pct': 82,
    });
    expect(c.fullName, 'Aarav');
    expect(c.profileCompletionPct, 82);
    expect(c.skills.toSet(), {'GD&T', 'AutoCAD'});
  });
}
