import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/domain/ess_models.dart';

/// G6: a lab/facility ticket's detail carries the Admin Manager's register row.
void main() {
  test('parses the infra link when the register mirror exists', () {
    final ticket = HelpdeskTicket.fromJson(const {
      'id': 't1',
      'ref': 'HD-0007',
      'category': {'slug': 'facility', 'name': 'Facility'},
      'subject': 'AC not working',
      'status': 'open',
      'anonymous': false,
      'mine': true,
      'infra': {'ticket_no': 42, 'status': 'open', 'closed_on': null},
    });
    expect(ticket.infra, isNotNull);
    expect(ticket.infra!.ticketNo, 42);
    expect(ticket.infra!.status, 'open');
  });

  test('leaves infra null for every other category', () {
    final ticket = HelpdeskTicket.fromJson(const {
      'id': 't2',
      'ref': 'HD-0008',
      'category': {'slug': 'it_lab', 'name': 'IT / Lab'},
      'subject': 'Laptop',
      'status': 'open',
      'anonymous': false,
      'mine': true,
      'infra': null,
    });
    expect(ticket.infra, isNull);
  });
}
