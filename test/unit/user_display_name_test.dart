import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/utils/user_display_name.dart';

void main() {
  group('memberDisplayName', () {
    test('prefers nickname over displayName and email', () {
      final value = memberDisplayName({
        'nickname': '찬양팀장',
        'displayName': '홍길동',
        'email': 'hello@example.com',
      });
      expect(value, '찬양팀장');
    });

    test('falls back to displayName', () {
      final value = memberDisplayName({
        'displayName': '홍길동',
        'email': 'hello@example.com',
      });
      expect(value, '홍길동');
    });

    test('falls back to email', () {
      final value = memberDisplayName({'email': 'hello@example.com'});
      expect(value, 'hello@example.com');
    });
  });

  group('memberDisplayNameWithFallback', () {
    test('never returns raw uid for missing profile', () {
      final value = memberDisplayNameWithFallback(
        'some-uid',
        null,
        fallback: '이름 확인 중',
      );
      expect(value, '이름 확인 중');
    });
  });
}
