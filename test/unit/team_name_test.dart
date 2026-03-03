import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/utils/team_name.dart';

void main() {
  group('normalizeTeamName', () {
    test('trims and collapses whitespace', () {
      expect(normalizeTeamName('  금요   기도회  '), '금요 기도회');
    });

    test('replaces slash with space', () {
      expect(normalizeTeamName('2부/찬양팀'), '2부 찬양팀');
    });
  });

  group('buildTeamNameKey', () {
    test('builds lowercase encoded key', () {
      expect(buildTeamNameKey('금요 기도회'), Uri.encodeComponent('금요 기도회'));
    });

    test('returns empty for blank input', () {
      expect(buildTeamNameKey('   '), '');
    });
  });
}
