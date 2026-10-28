import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwt(Map<String, dynamic> payload) {
  final p = base64Url.encode(utf8.encode(json.encode(payload))).replaceAll('=', '');
  return 'header.$p.sig';
}

void main() {
  StaffIdentity login(String role) =>
      StaffIdentity.fromLoginUser({'userId': 'u1', 'role': role, 'locationName': 'Faridabad'});

  group('Team RVM admission (isTeamMember)', () {
    test('admits the roles the ESS serves but staff_app refuses', () {
      for (final r in ['hr', 'hr_executive', 'hod_placement']) {
        final id = login(r);
        expect(id.isTeamMember, isTrue, reason: r);
        expect(id.isStaff, isFalse, reason: '$r is Team-RVM-only');
      }
    });

    test('admits every staff-app role too', () {
      for (final r in [
        'admin',
        'faculty',
        'super_admin',
        'accounts_admin',
        'ceo',
        'hoo',
        'hod',
        'admin_manager',
      ]) {
        expect(login(r).isTeamMember, isTrue, reason: r);
      }
    });

    test('still refuses students and unknown roles', () {
      expect(login('student').isTeamMember, isFalse);
      expect(login('nonsense').isTeamMember, isFalse);
    });

    test('parses hr_executive and hod_placement (regression)', () {
      expect(login('hr_executive').role, AppRole.hrExecutive);
      expect(login('hod_placement').role, AppRole.hodPlacement);
      expect(login('unknown_role').role, AppRole.unknown);
    });

    test('an attendance-only session is admitted (role unknown + attendance)', () {
      final id = StaffIdentity.fromToken(_jwt({'k': 'punch', 'e': 'emp-1'}));
      expect(id, isNotNull);
      expect(id!.isTeamMember, isTrue);
      expect(id.role, AppRole.unknown);
    });

    test('a fresh faculty login carries faculty_id for the faculty screens', () {
      final id = StaffIdentity.fromLoginUser({
        'userId': 'u1',
        'username': 'faculty.login',
        'role': 'faculty',
        'locationName': 'Faridabad',
        'faculty_id': 'f-42',
      });
      expect(id.facultyId, 'f-42');
    });

    test('the login token itself carries faculty_id for a first install', () {
      final id = StaffIdentity.fromToken(_jwt({
        'userId': 'u1',
        'username': 'faculty.login',
        'role': 'faculty',
        'locationId': 1,
        'locationName': 'Faridabad',
        'id': 'f-42',
      }));
      expect(id, isNotNull);
      expect(id!.facultyId, 'f-42');
    });
  });
}
