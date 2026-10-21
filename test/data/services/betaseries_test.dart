import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/betaseries/betaseries_client.dart';

void main() {
  group('parseBetaSeriesRanking', () {
    test('keeps the series ids in rank order', () {
      final ids = parseBetaSeriesRanking({
        'day': '2026-10-20',
        'country': 'fr',
        'shows': [
          {'show_id': 36263, 'title': "Cat's Eyes", 'rank': 1, 'users': 2067},
          {'show_id': 41186, 'title': 'MobLand', 'rank': 2, 'users': 1657},
        ],
        'errors': [],
      });
      expect(ids, [36263, 41186]);
    });

    test('an empty or broken answer gives an empty chart', () {
      expect(parseBetaSeriesRanking({'shows': []}), isEmpty);
      expect(parseBetaSeriesRanking({'errors': [{'code': 3001}]}), isEmpty);
      expect(parseBetaSeriesRanking(null), isEmpty);
      expect(parseBetaSeriesRanking({'shows': [{'title': 'No id'}]}), isEmpty);
    });
  });

  group('parseBetaSeriesMovies', () {
    test('keeps the TMDB ids in order', () {
      final ids = parseBetaSeriesMovies({
        'movies': [
          {'id': 106011, 'title': 'Spider-Man', 'tmdb_id': 969681},
          {'id': 137169, 'title': "L'Odyssée", 'tmdb_id': 1368337},
        ],
      });
      expect(ids, [969681, 1368337]);
    });

    test('skips a film with no TMDB id', () {
      final ids = parseBetaSeriesMovies({
        'movies': [
          {'id': 1, 'tmdb_id': 0},
          {'id': 2, 'tmdb_id': null},
          {'id': 3, 'tmdb_id': 42},
        ],
      });
      expect(ids, [42]);
    });

    test('a broken answer gives an empty chart', () {
      expect(parseBetaSeriesMovies('oops'), isEmpty);
    });
  });

  group('parseBetaSeriesShowTmdbId', () {
    test('reads the TMDB id of a series', () {
      expect(
        parseBetaSeriesShowTmdbId({
          'show': {'id': 36263, 'thetvdb_id': 433161, 'themoviedb_id': 222176},
        }),
        222176,
      );
    });

    test('a series without one has none', () {
      expect(parseBetaSeriesShowTmdbId({'show': {'id': 1}}), isNull);
      expect(
        parseBetaSeriesShowTmdbId({'show': {'themoviedb_id': 0}}),
        isNull,
      );
      expect(parseBetaSeriesShowTmdbId(null), isNull);
    });
  });

  group('parseBetaSeriesSimilars', () {
    Map<String, Object?> similar(String key, String idField, int id, int followers) =>
        {
          'id': 1,
          'login': 'member',
          key: {idField: id, 'followers': followers},
        };

    test('puts the most followed series first', () {
      final ids = parseBetaSeriesSimilars({
        'similars': [
          similar('show', 'themoviedb_id', 100, 500),
          similar('show', 'themoviedb_id', 200, 60000),
          similar('show', 'themoviedb_id', 300, 500),
        ],
      }, mediaType: 'tv');
      // Ties keep the order the members added them in.
      expect(ids, [200, 100, 300]);
    });

    test('reads films by their own key and id field', () {
      final ids = parseBetaSeriesSimilars({
        'similars': [
          similar('movie', 'tmdb_id', 6479, 10),
          similar('show', 'themoviedb_id', 1, 99),
        ],
      }, mediaType: 'movie');
      expect(ids, [6479]);
    });

    test('skips a title twice or without a TMDB id', () {
      final ids = parseBetaSeriesSimilars({
        'similars': [
          similar('show', 'themoviedb_id', 0, 10),
          similar('show', 'themoviedb_id', 7, 10),
          similar('show', 'themoviedb_id', 7, 10),
          {'show_title': 'No details'},
        ],
      }, mediaType: 'tv');
      expect(ids, [7]);
    });

    test('an error gives nothing', () {
      expect(
        parseBetaSeriesSimilars({
          'errors': [{'code': 4001}],
        }, mediaType: 'movie'),
        isEmpty,
      );
    });
  });

  test('parseBetaSeriesMovieId reads BetaSeries own id', () {
    expect(parseBetaSeriesMovieId({'movie': {'id': 130330}}), 130330);
    expect(parseBetaSeriesMovieId({'movie': {'id': null}}), isNull);
    expect(parseBetaSeriesMovieId('oops'), isNull);
  });
}
