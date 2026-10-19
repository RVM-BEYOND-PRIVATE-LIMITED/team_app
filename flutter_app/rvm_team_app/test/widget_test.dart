import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/domain/models.dart';

void main() {
  group('PriorityTask.fromJson', () {
    test('parses the inbox row shape and flags', () {
      final task = PriorityTask.fromJson({
        'id': 'abc',
        'title': 'Check the lab',
        'priority': 'urgent',
        'status': 'open',
        'task_date': '2026-10-16',
        'read': false,
        'is_today': true,
        'overdue': true,
        'assigned_by_name': 'CEO',
      });
      expect(task.id, 'abc');
      expect(task.title, 'Check the lab');
      expect(task.priority, 'urgent');
      expect(task.isDone, isFalse);
      expect(task.isToday, isTrue);
      expect(task.overdue, isTrue);
    });
  });

  group('PriorityInbox.fromJson', () {
    test('reads the counters and maps the task list', () {
      final inbox = PriorityInbox.fromJson({
        'today': '2026-10-16',
        'unread': 2,
        'outstanding': 3,
        'receives_tasks': true,
        'tasks': [
          {'id': 't1', 'title': 'One', 'status': 'open'},
          {'id': 't2', 'title': 'Two', 'status': 'done'},
        ],
      });
      expect(inbox.tasks, hasLength(2));
      expect(inbox.unread, 2);
      expect(inbox.outstanding, 3);
      expect(inbox.receivesTasks, isTrue);
    });
  });

  group('TeamBatch.fromJson', () {
    test('reads the nested faculty/skill names and counts', () {
      final batch = TeamBatch.fromJson({
        'id': 'b1',
        'name': 'CAD Batch A',
        'students': 12,
        'joined_count': 10,
        'status': 'active',
        'isSubstituted': true,
        'faculty': {'id': 'f1', 'name': 'Asha'},
        'skill': {'id': 's1', 'name': 'AutoCAD'},
      });
      expect(batch.name, 'CAD Batch A');
      expect(batch.students, 12);
      expect(batch.joinedCount, 10);
      expect(batch.facultyName, 'Asha');
      expect(batch.skillName, 'AutoCAD');
      expect(batch.substituted, isTrue);
    });
  });
}
