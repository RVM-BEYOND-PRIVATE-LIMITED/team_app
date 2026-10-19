import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements TicketsRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _FakeUpdate extends Fake implements TicketUpdate {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeUpdate()));

  group('Tickets parser', () {
    test('ticketsPage reads items, counts (incl. "In Progress"), flattened count + nested refs', () {
      final page = Parse.ticketsPage({
        'items': [
          {
            'id': 't1',
            'title': 'Login broken',
            'description': 'Cannot sign in',
            'status': 'In Progress',
            'priority': 'High',
            'category': 'Technical',
            'created_at': '2026-07-01T10:00:00Z',
            'student': {'id': 's1', 'name': 'Asha'},
            'assignee': {'id': 'u9', 'username': 'admin_ravi'},
            'assignee_id': 'u9',
            'student_ticket_count': 3,
          },
        ],
        'total': 7,
        'counts': {'All': 7, 'Open': 4, 'In Progress': 2, 'Resolved': 1},
        'page': 1,
        'limit': 15,
      });
      expect(page.total, 7);
      expect(page.counts.inProgress, 2);
      expect(page.counts.forStatus('Resolved'), 1);
      final t = page.items.single;
      expect(t.status, 'In Progress');
      expect(t.student?.name, 'Asha');
      expect(t.assignee?.name, 'admin_ravi'); // username → name
      expect(t.isAssigned, isTrue);
      expect(t.studentTicketCount, 3);
    });

    test('ticketMessages distinguish staff vs student sender', () {
      final msgs = Parse.ticketMessages([
        {
          'id': 'm1',
          'message': 'Please help',
          'sender_student_id': 's1',
          'student': {'id': 's1', 'name': 'Asha'},
        },
        {
          'id': 'm2',
          'message': 'Looking into it',
          'sender_user_id': 'u9',
          'user': {'id': 'u9', 'username': 'admin_ravi'},
        },
      ]);
      expect(msgs.first.isFromStaff, isFalse);
      expect(msgs.first.senderName, 'Asha');
      expect(msgs.last.isFromStaff, isTrue);
      expect(msgs.last.senderName, 'admin_ravi');
    });

    test('ticketAdmins + ticketCategories', () {
      final admins = Parse.ticketAdmins([
        {'id': 'u9', 'username': 'admin_ravi'},
      ]);
      expect(admins.single.name, 'admin_ravi');
      expect(Parse.ticketCategories(['Fees', 'Technical']), ['Fees', 'Technical']);
    });
  });

  group('TicketUpdate toJson', () {
    test('sends only the provided fields', () {
      expect(const TicketUpdate(status: 'Resolved').toJson(), {'status': 'Resolved'});
      expect(const TicketUpdate(assigneeId: 'u9').toJson(), {'assignee_id': 'u9'});
      expect(const TicketUpdate().toJson(), <String, dynamic>{});
    });
  });

  group('TicketDraft toJson', () {
    test('sends title/description/student_id + optional priority/category', () {
      final j = const TicketDraft(
        title: 'Login broken',
        description: 'cannot sign in',
        studentId: 's1',
        priority: 'High',
        category: 'Technical',
      ).toJson();
      expect(j['student_id'], 's1');
      expect(j['priority'], 'High');
      expect(j['category'], 'Technical');
    });

    test('omits empty category', () {
      final j = const TicketDraft(title: 't', description: 'd', studentId: 's1', category: '').toJson();
      expect(j.containsKey('category'), isFalse);
    });
  });

  group('TicketsRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late TicketsRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = TicketsRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('update forwards id + payload', () async {
      when(() => ds.update(any(), any())).thenAnswer((_) async {});
      await repo.update('t1', const TicketUpdate(status: 'Resolved'));
      verify(() => ds.update('t1', any())).called(1);
    });

    test('reply forwards ticketId + message', () async {
      when(() => ds.reply(ticketId: any(named: 'ticketId'), message: any(named: 'message')))
          .thenAnswer((_) async {});
      await repo.reply(ticketId: 't1', message: 'hello');
      verify(() => ds.reply(ticketId: 't1', message: 'hello')).called(1);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.list(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.list());
    });
  });
}
