import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('Support parsers', () {
    test('supportTickets reads {tickets:[...]} + maps status', () {
      final t = Parse.supportTickets({
        'tickets': [
          {'id': 't1', 'subject': 'Login issue', 'status': 'open', 'created_at': '2026-07-01'}
        ],
      });
      expect(t.single.subject, 'Login issue');
      expect(t.single.status, TicketStatus.open);
    });

    test('ticketDetail reads message + replies with sender side', () {
      final d = Parse.ticketDetail({
        'id': 't1',
        'subject': 'X',
        'status': 'replied',
        'message': 'help me',
        'replies': [
          {'id': 'r1', 'message': 'looking into it', 'sender_role': 'admin', 'created_at': '2026-07-02'},
          {'id': 'r2', 'message': 'thanks', 'sender_role': 'candidate', 'created_at': '2026-07-02'},
        ],
      });
      expect(d.status, TicketStatus.replied);
      expect(d.message, 'help me');
      expect(d.replies, hasLength(2));
      expect(d.replies[0].fromCandidate, isFalse);
      expect(d.replies[1].fromCandidate, isTrue);
    });
  });

  test('companies parser reads {companies:[...]} + verified from approval_status', () {
    final c = Parse.companies({
      'companies': [
        {'id': 'c1', 'name': 'Acme', 'industry': 'Aerospace', 'city': 'Pune', 'approval_status': 'approved'}
      ],
    });
    expect(c.single.name, 'Acme');
    expect(c.single.industry, 'Aerospace');
    expect(c.single.location, 'Pune');
    expect(c.single.verified, isTrue);
  });
}
