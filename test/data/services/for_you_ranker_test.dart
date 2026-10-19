import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/seerr/for_you_ranker.dart';
import 'package:moonfin/data/services/seerr/for_you_service.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';

final _now = DateTime(2026, 10, 19);

SeerrDiscoverItem _item(
  int id, {
  String? mediaType = 'movie',
  int? status,
  bool adult = false,
  String? poster = '/poster.jpg',
  String? releaseDate = '2020-05-01',
  double voteAverage = 7.5,
  int voteCount = 2000,
}) => SeerrDiscoverItem(
  id: id,
  mediaType: mediaType,
  title: 'Title $id',
  posterPath: poster,
  releaseDate: releaseDate,
  adult: adult,
  voteAverage: voteAverage,
  voteCount: voteCount,
  mediaInfo: status == null ? null : SeerrMediaInfo(status: status),
);

TasteSeed _seed(int id, {String type = 'movie', double weight = 1}) =>
    TasteSeed(tmdbId: id, mediaType: type, title: 'Seed $id', weight: weight);

TasteSignal _signal(int id, {String type = 'movie'}) =>
    TasteSignal(tmdbId: id, mediaType: type, title: 'Seen $id');

List<int> _ids(List<ForYouPick> picks) => [for (final p in picks) p.item.id];

void main() {
  group('buildSeeds', () {
    test('newer watches weigh more than older ones', () {
      final seeds = ForYouRanker.buildSeeds(
        recent: [_signal(1), _signal(2), _signal(3)],
      );
      expect(seeds.map((s) => s.tmdbId), [1, 2, 3]);
      expect(seeds[0].weight, greaterThan(seeds[1].weight));
      expect(seeds[1].weight, greaterThan(seeds[2].weight));
    });

    test('a series watched over several episodes counts once', () {
      final seeds = ForYouRanker.buildSeeds(
        recent: [
          _signal(10, type: 'tv'),
          _signal(10, type: 'tv'),
          _signal(20),
        ],
      );
      expect(seeds, hasLength(2));
      expect(seeds.first.weight, 1.0);
    });

    test('favourites add to what was watched', () {
      final seeds = ForYouRanker.buildSeeds(
        recent: [_signal(1), _signal(2)],
        favorites: [_signal(2)],
      );
      expect(seeds.first.tmdbId, 2);
      expect(seeds.first.weight, greaterThan(1.4));
    });

    test('a movie and a series sharing a TMDB id stay apart', () {
      final seeds = ForYouRanker.buildSeeds(
        recent: [_signal(7), _signal(7, type: 'tv')],
      );
      expect(seeds, hasLength(2));
    });

    test('keeps the strongest seeds up to the limit', () {
      final seeds = ForYouRanker.buildSeeds(
        recent: [for (var i = 1; i <= 20; i++) _signal(i)],
        limit: 5,
      );
      expect(seeds.map((s) => s.tmdbId), [1, 2, 3, 4, 5]);
    });
  });

  group('rank', () {
    test('a title several seeds agree on beats a lone suggestion', () {
      final a = _seed(1);
      final b = _seed(2);
      final picks = ForYouRanker.rank(
        seeds: [a, b],
        recommendationsBySeed: {
          a.key: [_item(100), _item(200)],
          b.key: [_item(300), _item(200)],
        },
        now: _now,
      );
      expect(picks.first.item.id, 200);
      expect(picks.first.seedCount, 2);
    });

    test('drops what the server has, is fetching or blocks', () {
      final seed = _seed(1);
      final picks = ForYouRanker.rank(
        seeds: [seed],
        recommendationsBySeed: {
          seed.key: [
            _item(1, status: SeerrMediaStatus.pending),
            _item(2, status: SeerrMediaStatus.processing),
            _item(3, status: SeerrMediaStatus.partiallyAvailable),
            _item(4, status: SeerrMediaStatus.available),
            _item(5, status: SeerrMediaStatus.blocklisted),
            _item(6, status: SeerrMediaStatus.deleted),
            _item(7, status: SeerrMediaStatus.unknown),
            _item(8),
          ],
        },
        now: _now,
      );
      expect(_ids(picks), unorderedEquals([6, 7, 8]));
    });

    test('drops adult, posterless and unreleased titles', () {
      final seed = _seed(1);
      final picks = ForYouRanker.rank(
        seeds: [seed],
        recommendationsBySeed: {
          seed.key: [
            _item(1, adult: true),
            _item(2, poster: null),
            _item(3, releaseDate: '2027-03-01'),
            _item(4, releaseDate: null),
            _item(5),
          ],
        },
        now: _now,
      );
      expect(_ids(picks), [5]);
    });

    test('adult titles stay when the filter is off', () {
      final seed = _seed(1);
      final picks = ForYouRanker.rank(
        seeds: [seed],
        recommendationsBySeed: {
          seed.key: [_item(1, adult: true)],
        },
        blockAdult: false,
        now: _now,
      );
      expect(_ids(picks), [1]);
    });

    test('never suggests a seed or an excluded title', () {
      final a = _seed(1);
      final b = _seed(2);
      final picks = ForYouRanker.rank(
        seeds: [a, b],
        recommendationsBySeed: {
          a.key: [_item(2), _item(3), _item(4)],
        },
        excludeKeys: {forYouKey('movie', 3)},
        now: _now,
      );
      expect(_ids(picks), [4]);
    });

    test('a well-rated title beats a poorly rated one in the same spot', () {
      final a = _seed(1);
      final b = _seed(2);
      final picks = ForYouRanker.rank(
        seeds: [a, b],
        recommendationsBySeed: {
          a.key: [_item(10, voteAverage: 4.5)],
          b.key: [_item(20, voteAverage: 8.2)],
        },
        now: _now,
      );
      expect(_ids(picks), [20, 10]);
    });

    test('a handful of glowing votes does not beat a broad consensus', () {
      final strong = ForYouRanker.qualityFactor(
        _item(1, voteAverage: 7.8, voteCount: 20000),
      );
      final obscure = ForYouRanker.qualityFactor(
        _item(2, voteAverage: 9.5, voteCount: 12),
      );
      expect(strong, greaterThan(obscure));
    });

    test('one seed cannot fill the row while others have picks', () {
      final big = _seed(1, weight: 3);
      final small = _seed(2, weight: 0.5);
      final picks = ForYouRanker.rank(
        seeds: [big, small],
        recommendationsBySeed: {
          big.key: [for (var i = 100; i < 110; i++) _item(i)],
          small.key: [_item(200), _item(201)],
        },
        limit: 6,
        now: _now,
      );
      final fromBig = picks.where((p) => p.because.key == big.key).length;
      expect(fromBig, ForYouRanker.maxPerSeed);
      expect(_ids(picks), containsAll([200, 201]));
    });

    test('the cap gives way when nothing else is left', () {
      final seed = _seed(1);
      final picks = ForYouRanker.rank(
        seeds: [seed],
        recommendationsBySeed: {
          seed.key: [for (var i = 100; i < 110; i++) _item(i)],
        },
        limit: 8,
        now: _now,
      );
      expect(picks, hasLength(8));
    });

    test('an item without a media type takes its seed\'s', () {
      final seed = _seed(1, type: 'tv');
      final picks = ForYouRanker.rank(
        seeds: [seed],
        recommendationsBySeed: {
          seed.key: [_item(50, mediaType: null)],
        },
        now: _now,
      );
      expect(picks.single.mediaType, 'tv');
    });

    test('credits the seed that pushed a pick the most', () {
      final weak = _seed(1, weight: 0.4);
      final strong = _seed(2, weight: 1.5);
      final picks = ForYouRanker.rank(
        seeds: [weak, strong],
        recommendationsBySeed: {
          weak.key: [_item(9)],
          strong.key: [_item(8), _item(9)],
        },
        now: _now,
      );
      final pick = picks.firstWhere((p) => p.item.id == 9);
      expect(pick.because.tmdbId, 2);
    });
  });

  group('ForYouService', () {
    setUp(() => ForYouService.instance.reset());

    AggregatedItem libraryItem(String type, String? tmdb, String name) =>
        AggregatedItem(
          id: name,
          serverId: 'server',
          rawData: {
            'Name': name,
            'Type': type,
            'ProviderIds': ?(tmdb == null ? null : {'Tmdb': tmdb}),
          },
        );

    test('reads TMDB ids off movies and series only', () {
      final signals = ForYouService.signalsFrom([
        libraryItem('Movie', '603', 'The Matrix'),
        libraryItem('Series', '1396', 'Breaking Bad'),
        libraryItem('Episode', '62085', 'Pilot'),
        libraryItem('Movie', null, 'Home video'),
        libraryItem('Movie', 'abc', 'Broken id'),
      ]);
      expect(signals.map((s) => s.key), ['movie:603', 'tv:1396']);
    });

    test('caches per server and forgets requested titles', () async {
      var calls = 0;
      Future<SeerrDiscoverPage> fetch(TasteSeed seed) async {
        calls++;
        return SeerrDiscoverPage(results: [_item(700), _item(701)]);
      }

      Future<({List<AggregatedItem> recent, List<AggregatedItem> favorites})>
      history() async => (
        recent: [libraryItem('Movie', '603', 'The Matrix')],
        favorites: const <AggregatedItem>[],
      );

      final first = await ForYouService.instance.load(
        serverId: 's1',
        loadHistory: history,
        fetchRecommendations: fetch,
      );
      expect(_ids(first), [700, 701]);

      ForYouService.instance.markRequested('movie', 700);
      final second = await ForYouService.instance.load(
        serverId: 's1',
        loadHistory: history,
        fetchRecommendations: fetch,
      );
      expect(calls, 1);
      expect(_ids(second), [701]);

      final refreshed = await ForYouService.instance.load(
        serverId: 's1',
        loadHistory: history,
        fetchRecommendations: fetch,
        forceRefresh: true,
      );
      expect(calls, 2);
      expect(_ids(refreshed), [701]);
    });

    test('a seed TMDB fails on does not empty the row', () async {
      Future<SeerrDiscoverPage> fetch(TasteSeed seed) async {
        if (seed.tmdbId == 1) throw StateError('not found');
        return SeerrDiscoverPage(results: [_item(900)]);
      }

      final picks = await ForYouService.instance.load(
        serverId: 's2',
        loadHistory: () async => (
          recent: [
            libraryItem('Movie', '1', 'Gone'),
            libraryItem('Movie', '2', 'Here'),
          ],
          favorites: const <AggregatedItem>[],
        ),
        fetchRecommendations: fetch,
      );
      expect(_ids(picks), [900]);
    });
  });
}
