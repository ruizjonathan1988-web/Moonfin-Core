import 'dart:math' as math;

import 'seerr_api_models.dart';

/// A title the viewer has shown interest in, used to pull recommendations
/// from Seerr. [weight] says how much it should count: recent and favourite
/// titles count for more than something watched a while ago.
class TasteSeed {
  final int tmdbId;

  /// Seerr's media type, `movie` or `tv`.
  final String mediaType;
  final String title;
  final double weight;

  const TasteSeed({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    required this.weight,
  });

  String get key => forYouKey(mediaType, tmdbId);

  TasteSeed withWeight(double weight) => TasteSeed(
    tmdbId: tmdbId,
    mediaType: mediaType,
    title: title,
    weight: weight,
  );
}

/// A title the viewer could have, with why it is suggested.
class ForYouPick {
  final SeerrDiscoverItem item;

  /// Seerr's media type, `movie` or `tv`.
  final String mediaType;
  final double score;

  /// The seed that pushed this pick the most, to say "because you watched".
  final TasteSeed because;

  /// How many seeds independently suggested this pick.
  final int seedCount;

  const ForYouPick({
    required this.item,
    required this.mediaType,
    required this.score,
    required this.because,
    required this.seedCount,
  });

  String get key => forYouKey(mediaType, item.id);
}

/// One card of a "Because you watched" row.
class BecauseItem {
  final SeerrDiscoverItem item;

  /// Seerr's media type, `movie` or `tv`.
  final String mediaType;

  const BecauseItem({required this.item, required this.mediaType});

  String get key => forYouKey(mediaType, item.id);
}

/// A "Because you watched [seed]" row.
class BecauseRow {
  final TasteSeed seed;
  final List<BecauseItem> items;

  const BecauseRow({required this.seed, required this.items});
}

/// One identity per TMDB title, since TMDB reuses ids across movies and tv.
String forYouKey(String mediaType, int tmdbId) => '$mediaType:$tmdbId';

/// A raw signal from the library, before it is weighted into a [TasteSeed].
class TasteSignal {
  final int tmdbId;
  final String mediaType;
  final String title;

  const TasteSignal({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
  });

  String get key => forYouKey(mediaType, tmdbId);
}

/// Turns what the viewer watched and liked into personal recommendations.
///
/// Every seed asks TMDB (through Seerr) what goes with it. A candidate scores
/// by how strongly and how many seeds point at it, then by how well it is
/// rated, so a film three of your recent watches agree on beats a film one
/// of them lists tenth. Anything already in the library, already requested
/// or not released yet is dropped, since the row is for things to request.
abstract final class ForYouRanker {
  /// How many seeds get a Seerr call each. Each seed costs one request.
  static const maxSeeds = 12;

  /// How many picks one seed may claim, so a single franchise can't fill
  /// the row.
  static const maxPerSeed = 4;

  static const _recentWeight = 1.0;
  static const _recentDecay = 0.88;
  static const _favoriteWeight = 1.4;

  /// Weights the viewer's history into seeds.
  ///
  /// [recent] is newest first and fades with age. [favorites] count a fixed
  /// amount on top. A title in both lists counts for both.
  static List<TasteSeed> buildSeeds({
    required List<TasteSignal> recent,
    List<TasteSignal> favorites = const [],
    int limit = maxSeeds,
  }) {
    final seeds = <String, TasteSeed>{};

    void add(TasteSignal signal, double weight) {
      if (signal.tmdbId <= 0) return;
      final existing = seeds[signal.key];
      seeds[signal.key] = existing == null
          ? TasteSeed(
              tmdbId: signal.tmdbId,
              mediaType: signal.mediaType,
              title: signal.title,
              weight: weight,
            )
          : existing.withWeight(existing.weight + weight);
    }

    final seenRecent = <String>{};
    var position = 0;
    for (final signal in recent) {
      // A series shows up once per episode watched. Its first sighting is
      // the one that dates it.
      if (!seenRecent.add(signal.key)) continue;
      add(signal, _recentWeight * math.pow(_recentDecay, position).toDouble());
      position++;
    }
    for (final signal in favorites) {
      add(signal, _favoriteWeight);
    }

    final ordered = seeds.values.toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
    return ordered.take(limit).toList();
  }

  /// Ranks the candidates every seed brought back.
  ///
  /// [recommendationsBySeed] is keyed by [TasteSeed.key], each list in the
  /// order TMDB returned it. [excludeKeys] drops titles by [forYouKey], such
  /// as ones requested during this session that Seerr hasn't caught up with.
  static List<ForYouPick> rank({
    required List<TasteSeed> seeds,
    required Map<String, List<SeerrDiscoverItem>> recommendationsBySeed,
    Set<String> excludeKeys = const {},
    bool blockAdult = true,
    int limit = 30,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final seedKeys = {for (final seed in seeds) seed.key};
    final candidates = <String, _Candidate>{};

    for (final seed in seeds) {
      final recs = recommendationsBySeed[seed.key];
      if (recs == null) continue;
      for (var position = 0; position < recs.length; position++) {
        final item = recs[position];
        final mediaType = _mediaTypeOf(item, seed.mediaType);
        final key = forYouKey(mediaType, item.id);
        if (seedKeys.contains(key) || excludeKeys.contains(key)) continue;
        if (!isRequestable(item, blockAdult: blockAdult, now: today)) {
          continue;
        }
        candidates
            .putIfAbsent(key, () => _Candidate(item, mediaType))
            .add(seed, seed.weight / math.sqrt(position + 1));
      }
    }

    final scored = [
      for (final c in candidates.values)
        ForYouPick(
          item: c.item,
          mediaType: c.mediaType,
          score:
              c.support *
              (1 + 0.35 * (c.seedCount - 1)) *
              qualityFactor(c.item),
          because: c.strongestSeed,
          seedCount: c.seedCount,
        ),
    ]..sort(_byScore);

    // Keep the row varied: past [maxPerSeed] picks owed to one seed, the
    // rest wait until the row is otherwise short.
    final picks = <ForYouPick>[];
    final overflow = <ForYouPick>[];
    final perSeed = <String, int>{};
    for (final pick in scored) {
      if (picks.length >= limit) break;
      final count = perSeed[pick.because.key] ?? 0;
      if (count >= maxPerSeed) {
        overflow.add(pick);
        continue;
      }
      perSeed[pick.because.key] = count + 1;
      picks.add(pick);
    }
    for (final pick in overflow) {
      if (picks.length >= limit) break;
      picks.add(pick);
    }
    return picks;
  }

  /// "Because you watched X" rows: for the strongest seeds, what TMDB lists
  /// next to each, titles the server can already play first.
  ///
  /// Unlike [rank], these rows keep what the library holds, since a row
  /// about one title reads better whole. A seed whose list comes back
  /// shorter than [minItems] once filtered is skipped, and no title shows
  /// in two rows.
  static List<BecauseRow> becauseRows({
    required List<TasteSeed> seeds,
    required Map<String, List<SeerrDiscoverItem>> recommendationsBySeed,
    Set<String> excludeKeys = const {},
    bool blockAdult = true,
    int rows = 2,
    int minItems = 5,
    int perRow = 15,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final seedKeys = {for (final seed in seeds) seed.key};
    final used = <String>{};
    final result = <BecauseRow>[];

    for (final seed in seeds) {
      if (result.length >= rows) break;
      final recs = recommendationsBySeed[seed.key];
      if (recs == null) continue;
      final playable = <BecauseItem>[];
      final others = <BecauseItem>[];
      final keys = <String>{};
      for (final item in recs) {
        final mediaType = _mediaTypeOf(item, seed.mediaType);
        final key = forYouKey(mediaType, item.id);
        if (seedKeys.contains(key) ||
            excludeKeys.contains(key) ||
            used.contains(key) ||
            !keys.add(key)) {
          continue;
        }
        if (!_isShowable(item, blockAdult: blockAdult, now: today)) continue;
        final status = item.mediaInfo?.status;
        final entry = BecauseItem(item: item, mediaType: mediaType);
        if (status == SeerrMediaStatus.available ||
            status == SeerrMediaStatus.partiallyAvailable) {
          playable.add(entry);
        } else {
          others.add(entry);
        }
      }
      final items = [...playable, ...others].take(perRow).toList();
      if (items.length < minItems) continue;
      used.addAll(items.map((i) => i.key));
      result.add(BecauseRow(seed: seed, items: items));
    }
    return result;
  }

  /// Fit for a card at all: a poster, out already, not blocked.
  static bool _isShowable(
    SeerrDiscoverItem item, {
    required bool blockAdult,
    required DateTime now,
  }) {
    if (blockAdult && item.adult) return false;
    final poster = item.posterPath;
    if (poster == null || poster.isEmpty) return false;
    if (item.mediaInfo?.status == SeerrMediaStatus.blocklisted) return false;
    final released = _parseDate(item.releaseDate ?? item.firstAirDate);
    if (released == null || released.isAfter(now)) return false;
    return true;
  }

  /// Whether a title is worth offering as something to request.
  static bool isRequestable(
    SeerrDiscoverItem item, {
    bool blockAdult = true,
    DateTime? now,
  }) {
    if (blockAdult && item.adult) return false;
    final poster = item.posterPath;
    if (poster == null || poster.isEmpty) return false;
    if (_isTaken(item.mediaInfo?.status)) return false;
    final released = _parseDate(item.releaseDate ?? item.firstAirDate);
    // No date at all usually means an announced title with nothing to grab.
    if (released == null) return false;
    if (released.isAfter(now ?? DateTime.now())) return false;
    return true;
  }

  /// Requested, downloading, in the library or blocked: nothing to ask for.
  /// A title deleted from the library can be asked for again.
  static bool _isTaken(int? status) =>
      status == SeerrMediaStatus.pending ||
      status == SeerrMediaStatus.processing ||
      status == SeerrMediaStatus.partiallyAvailable ||
      status == SeerrMediaStatus.available ||
      status == SeerrMediaStatus.blocklisted;

  /// Between 0.45 and 1. Shrinks the TMDB average towards a neutral 6.4
  /// until enough people voted, so a 9/10 from twelve voters doesn't beat
  /// a 7.8 from twenty thousand.
  static double qualityFactor(SeerrDiscoverItem item) {
    final votes = (item.voteCount ?? 0).toDouble();
    final average = item.voteAverage ?? 0;
    const prior = 6.4;
    const priorVotes = 150.0;
    final shrunk = (average * votes + prior * priorVotes) / (votes + priorVotes);
    final normalized = ((shrunk - 5.0) / 3.0).clamp(0.0, 1.0);
    var factor = 0.55 + 0.45 * normalized;
    if (votes < 30) factor *= 0.8;
    return factor;
  }

  static int _byScore(ForYouPick a, ForYouPick b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return (b.item.popularity ?? 0).compareTo(a.item.popularity ?? 0);
  }

  static String _mediaTypeOf(SeerrDiscoverItem item, String fallback) =>
      switch (item.mediaType) {
        'movie' => 'movie',
        'tv' => 'tv',
        _ => fallback,
      };

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

class _Candidate {
  final SeerrDiscoverItem item;
  final String mediaType;
  double support = 0;
  final Map<String, (TasteSeed, double)> _bySeed = {};

  _Candidate(this.item, this.mediaType);

  void add(TasteSeed seed, double contribution) {
    // A seed listing the same title twice still only vouches for it once.
    final previous = _bySeed[seed.key];
    if (previous != null && previous.$2 >= contribution) return;
    support += contribution - (previous?.$2 ?? 0);
    _bySeed[seed.key] = (seed, contribution);
  }

  int get seedCount => _bySeed.length;

  TasteSeed get strongestSeed => _bySeed.values
      .reduce((a, b) => b.$2 > a.$2 ? b : a)
      .$1;
}
