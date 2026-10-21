import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/trakt/trakt_chart_cards.dart';
import 'package:moonfin/data/services/trakt/trakt_client.dart';

Map<String, Object?> movieEntry(Object? tmdb) => {
  'watcher_count': 10,
  'movie': {
    'title': 'Film',
    'ids': {'trakt': 1, 'tmdb': tmdb},
  },
};

SeerrDiscoverItem card(int id) =>
    SeerrDiscoverItem(id: id, title: 'tmdb $id', posterPath: '/p$id.jpg');

List<int> ids(List<SeerrDiscoverItem> cards) => [for (final c in cards) c.id];

void main() {
  group('parseTraktChart', () {
    test('keeps the TMDB ids in chart order', () {
      final ids = parseTraktChart([
        movieEntry(603),
        movieEntry(550),
      ], mediaType: 'movie');
      expect(ids, [603, 550]);
    });

    test('reads series under their own key', () {
      final ids = parseTraktChart([
        {
          'watchers': 4,
          'show': {
            'title': 'Serie',
            'ids': {'tmdb': 1396},
          },
        },
      ], mediaType: 'tv');
      expect(ids, [1396]);
    });

    test('skips what Trakt could not match to TMDB', () {
      final ids = parseTraktChart([
        movieEntry(null),
        movieEntry(603),
        {'movie': {'title': 'No ids'}},
        'junk',
      ], mediaType: 'movie');
      expect(ids, [603]);
    });

    test('a film is not read as a series', () {
      expect(parseTraktChart([movieEntry(603)], mediaType: 'tv'), isEmpty);
    });

    test('an answer that is not a list gives an empty chart', () {
      expect(parseTraktChart({'error': 'oops'}, mediaType: 'movie'), isEmpty);
      expect(parseTraktChart(null, mediaType: 'movie'), isEmpty);
    });

    test('a title listed twice counts once', () {
      expect(
        parseTraktChart([movieEntry(7), movieEntry(7)], mediaType: 'movie'),
        [7],
      );
    });
  });

  group('traktChartCards', () {
    test('reuses a card another chart holds and fetches the rest', () async {
      final fetched = <int>[];
      final cards = await traktChartCards(
        [1, 2, 3],
        known: {2: card(2)},
        fetch: (id) async {
          fetched.add(id);
          return card(id);
        },
      );
      expect(ids(cards), [1, 2, 3]);
      expect(fetched, unorderedEquals([1, 3]));
    });

    test('leaves out a title whose card cannot be fetched', () async {
      final cards = await traktChartCards(
        [1, 2, 3],
        known: const {},
        fetch: (id) async => id == 2 ? throw StateError('404') : card(id),
      );
      expect(ids(cards), [1, 3]);
    });

    test('only looks at the first titles', () async {
      final cards = await traktChartCards(
        [for (var i = 1; i <= 20; i++) i],
        known: const {},
        fetch: (id) async => card(id),
        depth: 5,
      );
      expect(ids(cards), [1, 2, 3, 4, 5]);
    });
  });
}
