import 'package:flutter/foundation.dart';

import '../../models/aggregated_item.dart';
import 'for_you_ranker.dart';
import 'seerr_api_models.dart';

/// Builds the For You row: the viewer's history goes in, titles to request
/// come out.
///
/// The result is kept for a while per server, since every load costs one
/// Seerr call per seed and the home screen reloads often.
class ForYouService {
  ForYouService._();

  static final ForYouService instance = ForYouService._();

  static const cacheLifetime = Duration(minutes: 30);

  /// Seerr calls running at once while gathering recommendations.
  static const _concurrency = 4;

  final Map<String, _Snapshot> _cache = {};

  /// Loads under way, so the For You and Because rows loading side by side
  /// share one round of Seerr calls.
  final Map<String, Future<_Snapshot>> _inflight = {};

  /// Titles requested from the row this session. Seerr reports them as
  /// requested soon enough, but until the next fetch they'd come back.
  final Set<String> _requested = {};

  /// Remembers a request made from the row so it stays gone.
  void markRequested(String mediaType, int tmdbId) {
    _requested.add(forYouKey(mediaType, tmdbId));
  }

  void clearCache() => _cache.clear();

  @visibleForTesting
  void reset() {
    _cache.clear();
    _inflight.clear();
    _requested.clear();
  }

  Future<List<ForYouPick>> load({
    required String serverId,
    required Future<({List<AggregatedItem> recent, List<AggregatedItem> favorites})>
    Function()
    loadHistory,
    required Future<SeerrDiscoverPage> Function(TasteSeed seed)
    fetchRecommendations,
    bool blockAdult = true,
    bool forceRefresh = false,
    int limit = 30,
  }) async {
    final snapshot = await _snapshot(
      serverId: serverId,
      loadHistory: loadHistory,
      fetchRecommendations: fetchRecommendations,
      forceRefresh: forceRefresh,
    );
    if (snapshot.seeds.isEmpty) return const [];
    return ForYouRanker.rank(
      seeds: snapshot.seeds,
      recommendationsBySeed: snapshot.recommendations,
      excludeKeys: _requested,
      blockAdult: blockAdult,
      limit: limit,
    );
  }

  /// "Because you watched" rows from the same history and recommendations
  /// as [load], without asking Seerr again.
  Future<List<BecauseRow>> loadBecauseRows({
    required String serverId,
    required Future<({List<AggregatedItem> recent, List<AggregatedItem> favorites})>
    Function()
    loadHistory,
    required Future<SeerrDiscoverPage> Function(TasteSeed seed)
    fetchRecommendations,
    bool blockAdult = true,
    bool forceRefresh = false,
    int rows = 2,
  }) async {
    final snapshot = await _snapshot(
      serverId: serverId,
      loadHistory: loadHistory,
      fetchRecommendations: fetchRecommendations,
      forceRefresh: forceRefresh,
    );
    if (snapshot.seeds.isEmpty) return const [];
    return ForYouRanker.becauseRows(
      seeds: snapshot.seeds,
      recommendationsBySeed: snapshot.recommendations,
      excludeKeys: _requested,
      blockAdult: blockAdult,
      rows: rows,
    );
  }

  Future<_Snapshot> _snapshot({
    required String serverId,
    required Future<({List<AggregatedItem> recent, List<AggregatedItem> favorites})>
    Function()
    loadHistory,
    required Future<SeerrDiscoverPage> Function(TasteSeed seed)
    fetchRecommendations,
    required bool forceRefresh,
  }) {
    final cached = _cache[serverId];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < cacheLifetime) {
      return Future.value(cached);
    }
    final running = _inflight[serverId];
    if (running != null) return running;
    final future = _gather(loadHistory, fetchRecommendations).then((snapshot) {
      _cache[serverId] = snapshot;
      return snapshot;
    });
    _inflight[serverId] = future;
    return future.whenComplete(() => _inflight.remove(serverId));
  }

  Future<_Snapshot> _gather(
    Future<({List<AggregatedItem> recent, List<AggregatedItem> favorites})>
    Function()
    loadHistory,
    Future<SeerrDiscoverPage> Function(TasteSeed seed) fetchRecommendations,
  ) async {
    final history = await loadHistory();
    final seeds = ForYouRanker.buildSeeds(
      recent: signalsFrom(history.recent),
      favorites: signalsFrom(history.favorites),
    );

    final recommendations = <String, List<SeerrDiscoverItem>>{};
    for (var start = 0; start < seeds.length; start += _concurrency) {
      final batch = seeds.skip(start).take(_concurrency);
      await Future.wait(
        batch.map((seed) async {
          try {
            final page = await fetchRecommendations(seed);
            recommendations[seed.key] = page.results;
          } catch (e) {
            // One title TMDB doesn't know shouldn't sink the whole row.
            debugPrint('[ForYou] No recommendations for ${seed.title}: $e');
          }
        }),
      );
    }
    return _Snapshot(
      at: DateTime.now(),
      seeds: seeds,
      recommendations: recommendations,
    );
  }

  /// Library items that carry a TMDB id, as signals Seerr can look up.
  @visibleForTesting
  static List<TasteSignal> signalsFrom(List<AggregatedItem> items) => [
    for (final item in items)
      if (_signalFrom(item) case final signal?) signal,
  ];

  static TasteSignal? _signalFrom(AggregatedItem item) {
    final tmdbId = int.tryParse(item.tmdbId ?? '');
    if (tmdbId == null || tmdbId <= 0) return null;
    final mediaType = switch (item.type) {
      'Movie' => 'movie',
      'Series' => 'tv',
      _ => null,
    };
    if (mediaType == null) return null;
    return TasteSignal(tmdbId: tmdbId, mediaType: mediaType, title: item.name);
  }
}

/// What one round of Seerr calls brought back, for every row built on it.
class _Snapshot {
  final DateTime at;
  final List<TasteSeed> seeds;
  final Map<String, List<SeerrDiscoverItem>> recommendations;

  const _Snapshot({
    required this.at,
    required this.seeds,
    required this.recommendations,
  });
}
