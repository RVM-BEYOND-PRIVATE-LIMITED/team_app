import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

String _jwt(Map<String, dynamic> payload) {
  final p =
      base64Url.encode(utf8.encode(json.encode(payload))).replaceAll('=', '');
  return 'header.$p.sig';
}

void main() {
  group('AppRole.salesExecutive (team_app #50, item 4)', () {
    test('parses the Scheduler role string, in any case and spacing', () {
      // Scheduler_Backend config/roles.js: SALES_EXECUTIVE: 'sales_executive'.
      expect(parseAppRole('sales_executive'), AppRole.salesExecutive);
      expect(parseAppRole(' Sales_Executive '), AppRole.salesExecutive);
    });

    test('has a human label and the wire string back', () {
      expect(appRoleLabel(AppRole.salesExecutive), 'Sales Executive');
      expect(appRoleLabelFromWire('sales_executive'), 'Sales Executive');
      expect(appRoleWire(AppRole.salesExecutive), 'sales_executive');
    });

    test('every role survives wire -> parse, and has a label', () {
      for (final role in AppRole.values) {
        expect(parseAppRole(appRoleWire(role)), role, reason: role.name);
        final label = appRoleLabel(role);
        expect(label, isNotEmpty, reason: role.name);
        expect(label.contains('_'), isFalse, reason: '$role shows $label');
      }
    });
  });

  group('StaffIdentity for a sales sign-in', () {
    test('is admitted to Team RVM but stays out of staff_app', () {
      final id = StaffIdentity.fromLoginUser(
          {'userId': 'u-sales', 'role': 'sales_executive'});
      expect(id.role, AppRole.salesExecutive);
      expect(id.isTeamMember, isTrue);
      expect(id.isStaff, isFalse);
      expect(id.isSuperAdmin, isFalse);
      expect(id.attendance, isFalse);
    });

    test('a kept token restores the same role, with no faculty id', () {
      final id = StaffIdentity.fromToken(_jwt({
        'userId': 'u-sales',
        'role': 'sales_executive',
        'id': 'not-a-faculty',
        'locationId': 1,
      }));
      expect(id, isNotNull);
      expect(id!.role, AppRole.salesExecutive);
      expect(id.isTeamMember, isTrue);
      expect(id.facultyId, isNull);
    });

    test('an unknown role is still refused', () {
      final id =
          StaffIdentity.fromLoginUser({'userId': 'u1', 'role': 'not_a_role'});
      expect(id.role, AppRole.unknown);
      expect(id.isTeamMember, isFalse);
    });
  });
}
