import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/core/roles.dart';

void main() {
  group('teamRoleKey', () {
    test('normalizes admin aliases', () {
      expect(teamRoleKey('admin'), 'admin');
      expect(teamRoleKey('owner'), 'admin');
      expect(teamRoleKey('team_admin'), 'admin');
      expect(teamRoleKey('팀장'), 'admin');
    });

    test('normalizes leader aliases', () {
      expect(teamRoleKey('leader'), 'leader');
      expect(teamRoleKey('speaker'), 'leader');
      expect(teamRoleKey('인도자'), 'leader');
    });

    test('falls back to member for unknown roles', () {
      expect(teamRoleKey('member'), 'member');
      expect(teamRoleKey('random-role'), 'member');
      expect(teamRoleKey(null), 'member');
    });
  });

  group('teamRoleLabel', () {
    test('returns localized labels', () {
      expect(teamRoleLabel('admin'), '팀장');
      expect(teamRoleLabel('leader'), '인도자');
      expect(teamRoleLabel('member'), '팀원');
      expect(teamRoleLabel('unknown'), '팀원');
    });
  });

  group('role predicates', () {
    test('isAdminRole matches canonical and aliases', () {
      expect(isAdminRole('admin'), isTrue);
      expect(isAdminRole('team_admin'), isTrue);
      expect(isAdminRole('owner'), isTrue);
      expect(isAdminRole('leader'), isFalse);
    });

    test('isLeaderRole matches canonical and aliases', () {
      expect(isLeaderRole('leader'), isTrue);
      expect(isLeaderRole('speaker'), isTrue);
      expect(isLeaderRole('인도자'), isTrue);
      expect(isLeaderRole('admin'), isFalse);
    });
  });
}
