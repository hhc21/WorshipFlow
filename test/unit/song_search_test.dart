import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worshipflow/services/song_search.dart';

void main() {
  setUp(resetSongSearchCaches);

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

  group('resolveSongLookup', () {
    test('prefers team songRefs before canonical title fallback', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('songs').doc('canonical-song').set({
        'title': '주의 집에 거하는 자',
        'defaultKey': 'D',
        'aliases': const <String>[],
        'searchTokens': const <String>['주의', '집에', '거하는', '자'],
      });
      await firestore.collection('songs').doc('team-song').set({
        'title': '주의 집에 거하는 자',
        'defaultKey': 'D',
        'aliases': const <String>[],
        'searchTokens': const <String>['주의', '집에', '거하는', '자'],
      });
      await firestore
          .collection('teams')
          .doc('team-1')
          .collection('songRefs')
          .doc('team-song')
          .set({'songId': 'team-song', 'title': '주의 집에 거하는 자'});

      final result = await resolveSongLookup(
        firestore,
        songId: null,
        rawTitle: '주의 집에 거하는 자',
        keyText: 'D',
        teamId: 'team-1',
      );

      expect(result.primary?.id, 'team-song');
      expect(result.candidates.first.source, 'team_song_ref');
      expect(result.songIds, contains('canonical-song'));
    });

    test('sanitizes decorated display text before resolution', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('songs').doc('song-1').set({
        'title': '주의 집에 거하는 자',
        'defaultKey': 'D',
        'aliases': const <String>[],
        'searchTokens': const <String>['주의', '집에', '거하는', '자'],
      });

      final result = await resolvePrimarySongCandidate(
        firestore,
        songId: null,
        rawTitle: '2 D 주의 집에 거하는 자',
        keyText: 'D',
        teamId: 'team-1',
      );

      expect(result?.id, 'song-1');
      expect(result?.title, '주의 집에 거하는 자');
    });

    test(
      'prefers canonical title key match before alias or token fallback',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('songs').doc('song-d').set({
          'title': '새로운 생명',
          'defaultKey': 'D',
          'aliases': const <String>['new life'],
          'searchTokens': const <String>['새로운', '생명', 'new', 'life'],
        });
        await firestore.collection('songs').doc('song-eb').set({
          'title': '새로운 생명',
          'defaultKey': 'Eb',
          'aliases': const <String>['new life'],
          'searchTokens': const <String>['새로운', '생명', 'new', 'life'],
        });

        final result = await resolveSongLookup(
          firestore,
          songId: null,
          rawTitle: '새로운 생명',
          keyText: 'D',
          teamId: null,
        );

        expect(result.primary?.id, 'song-d');
        expect(result.candidates.first.source, 'canonical_title_key');
        expect(result.songIds, isNot(contains('song-eb')));
      },
    );
  });
}
