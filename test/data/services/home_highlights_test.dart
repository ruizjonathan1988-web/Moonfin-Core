import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/home_highlights.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/ui/screens/playback/tabletop_layout.dart';

SeerrDiscoverItem _trending(int id, {int? status, String? jellyfinId}) =>
    SeerrDiscoverItem(
      id: id,
      mediaType: 'movie',
      mediaInfo: SeerrMediaInfo(status: status, jellyfinMediaId: jellyfinId),
    );

AggregatedItem _item({
  String type = 'Movie',
  String? created,
  bool played = false,
  double? playedPercentage,
  double? rating,
  String id = 'x',
}) => AggregatedItem(
  id: id,
  serverId: 'server',
  rawData: {
    'Type': type,
    'DateCreated': ?created,
    'CommunityRating': ?rating,
    'UserData': {
      'Played': played,
      'PlayedPercentage': ?playedPercentage,
    },
  },
);

void main() {
  group('playableTrendingIds', () {
    test('keeps only what the library holds, in trending order', () {
      final ids = playableTrendingIds([
        _trending(1, status: SeerrMediaStatus.available, jellyfinId: 'a'),
        _trending(2, status: SeerrMediaStatus.pending, jellyfinId: 'b'),
        _trending(3),
        _trending(4, status: SeerrMediaStatus.partiallyAvailable, jellyfinId: 'd'),
        _trending(5, status: SeerrMediaStatus.available),
        _trending(6, status: SeerrMediaStatus.available, jellyfinId: 'a'),
      ]);
      expect(ids, ['a', 'd']);
    });

    test('stops at the limit', () {
      final ids = playableTrendingIds([
        for (var i = 0; i < 30; i++)
          _trending(i, status: SeerrMediaStatus.available, jellyfinId: 'j$i'),
      ]);
      expect(ids, hasLength(10));
      expect(ids.first, 'j0');
    });
  });

  group('isFreshlyAdded', () {
    final now = DateTime.utc(2026, 10, 19, 20);

    test('a movie added three days ago and never started is new', () {
      expect(
        isFreshlyAdded(_item(created: '2026-10-16T10:00:00Z'), now: now),
        isTrue,
      );
    });

    test('an old, watched, started or undated title is not', () {
      expect(isFreshlyAdded(_item(created: '2026-09-01T10:00:00Z'), now: now),
          isFalse);
      expect(
        isFreshlyAdded(
          _item(created: '2026-10-18T10:00:00Z', played: true),
          now: now,
        ),
        isFalse,
      );
      expect(
        isFreshlyAdded(
          _item(created: '2026-10-18T10:00:00Z', playedPercentage: 12),
          now: now,
        ),
        isFalse,
      );
      expect(isFreshlyAdded(_item(), now: now), isFalse);
    });

    test('series and folders never carry it', () {
      expect(
        isFreshlyAdded(
          _item(type: 'Series', created: '2026-10-18T10:00:00Z'),
          now: now,
        ),
        isFalse,
      );
      expect(
        isFreshlyAdded(
          _item(type: 'Episode', created: '2026-10-18T10:00:00Z'),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('pickSurprise', () {
    test('prefers the first well-rated title', () {
      final pick = pickSurprise([
        _item(id: 'meh', rating: 5.1),
        _item(id: 'good', rating: 7.4),
        _item(id: 'great', rating: 8.9),
      ]);
      expect(pick?.id, 'good');
    });

    test('falls back to the first title, or nothing', () {
      expect(pickSurprise([_item(id: 'only', rating: 4)])?.id, 'only');
      expect(pickSurprise(const []), isNull);
    });
  });

  group('tabletopFold', () {
    MediaQueryData media(List<DisplayFeature> features) => MediaQueryData(
      size: const Size(880, 760),
      displayFeatures: features,
    );

    test('finds a half-open fold across the screen', () {
      final fold = tabletopFold(
        media(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(0, 380, 880, 0),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ]),
      );
      expect(fold?.top, 380);
    });

    test('ignores a flat phone, a book posture and a cutout', () {
      expect(
        tabletopFold(
          media(const [
            DisplayFeature(
              bounds: Rect.fromLTWH(0, 380, 880, 0),
              type: DisplayFeatureType.fold,
              state: DisplayFeatureState.postureFlat,
            ),
          ]),
        ),
        isNull,
      );
      expect(
        tabletopFold(
          media(const [
            DisplayFeature(
              bounds: Rect.fromLTWH(440, 0, 0, 760),
              type: DisplayFeatureType.fold,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ]),
        ),
        isNull,
      );
      expect(
        tabletopFold(
          media(const [
            DisplayFeature(
              bounds: Rect.fromLTWH(400, 0, 80, 30),
              type: DisplayFeatureType.cutout,
              state: DisplayFeatureState.unknown,
            ),
          ]),
        ),
        isNull,
      );
    });
  });
}
