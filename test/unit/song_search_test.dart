import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/services/song_search.dart';

void main() {
  group('findSongCandidates', () {
    test('returns empty when normalized title is blank', () async {
      final firestore = FakeFirebaseFirestore();
      final result = await findSongCandidates(firestore, '');
      expect(result, isEmpty);
    });

    test('returns token matches first', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('songs').doc('song-1').set({
        'title': '은혜',
        'searchTokens': ['eunhye'],
      });
      await firestore.collection('songs').doc('song-2').set({
        'title': '다른 곡',
        'searchTokens': ['other'],
      });

      final result = await findSongCandidates(firestore, 'eunhye');
      expect(result.length, 1);
      expect(result.first.id, 'song-1');
      expect(result.first.title, '은혜');
    });

    test('falls back to exact title and alias', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('songs').doc('song-a').set({
        'title': '새로운 생명',
        'aliases': ['new life', '새생명'],
        'searchTokens': ['irrelevant'],
      });
      await firestore.collection('songs').doc('song-b').set({
        'title': '다른 제목',
        'aliases': ['etc'],
      });

      final exact = await findSongCandidates(firestore, '새로운 생명');
      expect(exact.map((it) => it.id), contains('song-a'));

      final alias = await findSongCandidates(firestore, 'new life');
      expect(alias.map((it) => it.id), contains('song-a'));
    });
  });
}
