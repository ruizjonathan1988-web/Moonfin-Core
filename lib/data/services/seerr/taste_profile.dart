import 'dart:convert';
import 'dart:math' as math;

import 'seerr_api_models.dart';

/// The genres the taste questionnaire offers, each mapped onto TMDB's movie
/// and series genre ids, which differ: series fold action and adventure into
/// one genre, science fiction and fantasy into another, and have no horror
/// or thriller of their own.
enum TasteGenre {
  action({28}, {10759}),
  adventure({12}, {10759}),
  animation({16}, {16}),
  comedy({35}, {35}),
  crime({80}, {80}),
  documentary({99}, {99}),
  drama({18}, {18}),
  family({10751}, {10751}),
  fantasy({14}, {10765}),
  history({36}, {}),
  horror({27}, {}),
  kids({}, {10762}),
  music({10402}, {}),
  mystery({9648}, {9648}),
  reality({}, {10764}),
  romance({10749}, {}),
  scifi({878}, {10765}),
  talk({}, {10767, 10763, 10766}),
  thriller({53}, {}),
  war({10752}, {10768}),
  western({37}, {37});

  final Set<int> movieIds;
  final Set<int> tvIds;

  const TasteGenre(this.movieIds, this.tvIds);

  /// The questionnaire genres a TMDB title belongs to.
  static Set<TasteGenre> of(Iterable<int> genreIds, String mediaType) {
    final ids = genreIds.toSet();
    return {
      for (final genre in values)
        if ((mediaType == 'tv' ? genre.tvIds : genre.movieIds).any(
          ids.contains,
        ))
          genre,
    };
  }

  static TasteGenre? byName(String name) => values.asNameMap()[name];
}

/// Whether the viewer leans to movies, series, or neither.
enum TasteMediaPref { both, movies, series }

/// Whether the viewer leans to recent titles, to older ones, or neither.
enum TasteEra { any, recent, classic }

/// A mood the questionnaire offers, read as a few genres. The moods share no
/// genre, so one is chosen exactly when all of its genres are liked.
enum TasteMood {
  darkPlots({TasteGenre.crime, TasteGenre.thriller, TasteGenre.mystery}),
  adrenaline({
    TasteGenre.action,
    TasteGenre.adventure,
    TasteGenre.war,
    TasteGenre.western,
  }),
  imaginary({TasteGenre.scifi, TasteGenre.fantasy}),
  trueStories({TasteGenre.documentary, TasteGenre.history}),
  intenseDrama({TasteGenre.drama}),
  feelGood({TasteGenre.comedy, TasteGenre.romance, TasteGenre.music}),
  chills({TasteGenre.horror}),
  animated({TasteGenre.animation}),
  family({TasteGenre.family, TasteGenre.kids});

  final Set<TasteGenre> genres;

  const TasteMood(this.genres);
}

/// A title picked as a favourite in the questionnaire.
class TastePick {
  final int tmdbId;

  /// Seerr's media type, `movie` or `tv`.
  final String mediaType;
  final String title;
  final String? posterPath;

  const TastePick({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.posterPath,
  });

  String get key => '$mediaType:$tmdbId';

  Map<String, dynamic> toJson() => {
    'id': tmdbId,
    'type': mediaType,
    'title': title,
    'poster': ?posterPath,
  };

  static TastePick? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final type = json['type'];
    if (id is! int || (type != 'movie' && type != 'tv')) return null;
    return TastePick(
      tmdbId: id,
      mediaType: type as String,
      title: json['title'] as String? ?? '',
      posterPath: json['poster'] as String?,
    );
  }
}

/// What the viewer told the questionnaire.
class TasteProfile {
  final TasteMediaPref mediaPref;
  final Set<TasteGenre> liked;
  final Set<TasteGenre> avoided;

  /// ISO 639-1 codes. Empty means any language.
  final Set<String> languages;
  final List<TastePick> favorites;
  final TasteEra era;

  /// When the questionnaire was last completed, or null if never.
  final DateTime? updatedAt;

  const TasteProfile({
    this.mediaPref = TasteMediaPref.both,
    this.era = TasteEra.any,
    this.liked = const {},
    this.avoided = const {},
    this.languages = const {},
    this.favorites = const [],
    this.updatedAt,
  });

  static const empty = TasteProfile();

  bool get answered => updatedAt != null;

  TasteProfile copyWith({
    TasteMediaPref? mediaPref,
    TasteEra? era,
    Set<TasteGenre>? liked,
    Set<TasteGenre>? avoided,
    Set<String>? languages,
    List<TastePick>? favorites,
    DateTime? updatedAt,
  }) => TasteProfile(
    mediaPref: mediaPref ?? this.mediaPref,
    era: era ?? this.era,
    liked: liked ?? this.liked,
    avoided: avoided ?? this.avoided,
    languages: languages ?? this.languages,
    favorites: favorites ?? this.favorites,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'media': mediaPref.name,
    'era': era.name,
    'liked': [for (final g in liked) g.name],
    'avoided': [for (final g in avoided) g.name],
    'languages': languages.toList(),
    'favorites': [for (final f in favorites) f.toJson()],
    'updatedAt': ?updatedAt?.toUtc().toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  /// Reads what [encode] wrote, or [empty] for anything unreadable.
  static TasteProfile decode(String? source) {
    if (source == null || source.isEmpty) return empty;
    try {
      final json = jsonDecode(source);
      if (json is! Map) return empty;
      Set<TasteGenre> genres(Object? list) => {
        if (list is List)
          for (final name in list)
            if (name is String)
              if (TasteGenre.byName(name) case final genre?) genre,
      };
      return TasteProfile(
        mediaPref:
            TasteMediaPref.values.asNameMap()[json['media']] ??
            TasteMediaPref.both,
        era: TasteEra.values.asNameMap()[json['era']] ?? TasteEra.any,
        liked: genres(json['liked']),
        avoided: genres(json['avoided']),
        languages: {
          if (json['languages'] case final List list)
            for (final code in list)
              if (code is String && code.isNotEmpty) code,
        },
        favorites: [
          if (json['favorites'] case final List list)
            for (final entry in list)
              if (TastePick.fromJson(entry) case final pick?) pick,
        ],
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
    } catch (_) {
      return empty;
    }
  }
}

/// What the viewer turned down from the suggestions.
class TasteFeedback {
  /// Titles never to suggest again, by `movie:603` style keys.
  final List<String> hidden;

  /// How many turned-down titles carried each genre.
  final Map<TasteGenre, int> genrePenalties;

  const TasteFeedback({this.hidden = const [], this.genrePenalties = const {}});

  static const empty = TasteFeedback();

  /// Hidden titles kept, newest last. Older ones fall off past this.
  static const maxHidden = 500;

  Set<String> get hiddenKeys => hidden.toSet();

  /// Records that a title with [genres] was turned down.
  TasteFeedback notInterested(String key, Set<TasteGenre> genres) {
    final keys = [...hidden.where((k) => k != key), key];
    final penalties = {...genrePenalties};
    for (final genre in genres) {
      penalties[genre] = (penalties[genre] ?? 0) + 1;
    }
    return TasteFeedback(
      hidden: keys.length > maxHidden
          ? keys.sublist(keys.length - maxHidden)
          : keys,
      genrePenalties: penalties,
    );
  }

  String encode() => jsonEncode({
    'hidden': hidden,
    'penalties': {
      for (final entry in genrePenalties.entries) entry.key.name: entry.value,
    },
  });

  static TasteFeedback decode(String? source) {
    if (source == null || source.isEmpty) return empty;
    try {
      final json = jsonDecode(source);
      if (json is! Map) return empty;
      return TasteFeedback(
        hidden: [
          if (json['hidden'] case final List list)
            for (final key in list)
              if (key is String) key,
        ],
        genrePenalties: {
          if (json['penalties'] case final Map map)
            for (final entry in map.entries)
              if (TasteGenre.byName('${entry.key}') case final genre?)
                if (entry.value is int) genre: entry.value as int,
        },
      );
    } catch (_) {
      return empty;
    }
  }
}

/// How much [profile] and [feedback] want [item], as a factor on its score.
/// Zero means never show it: one of its genres is on the avoid list.
///
/// Everything else nudges rather than rules: a liked genre lifts a title, a
/// title outside the chosen languages or media type sinks without vanishing,
/// so a row never empties because the answers were strict.
double tasteFactor(
  SeerrDiscoverItem item,
  String mediaType,
  TasteProfile profile,
  TasteFeedback feedback, {
  DateTime? now,
}) {
  final genres = TasteGenre.of(item.genreIds, mediaType);
  if (genres.any(profile.avoided.contains)) return 0;

  var factor = 1.0;

  switch (profile.mediaPref) {
    case TasteMediaPref.movies when mediaType == 'tv':
    case TasteMediaPref.series when mediaType == 'movie':
      factor *= 0.45;
    default:
      break;
  }

  if (profile.liked.isNotEmpty) {
    final matches = genres.where(profile.liked.contains).length;
    factor *= matches == 0 ? 0.8 : 1 + 0.3 * math.min(matches, 2);
  }

  final language = item.originalLanguage;
  if (profile.languages.isNotEmpty && language != null && language.isNotEmpty) {
    factor *= profile.languages.contains(language) ? 1.15 : 0.7;
  }

  if (profile.era != TasteEra.any) {
    final year = _releaseYear(item);
    if (year != null) {
      final thisYear = (now ?? DateTime.now()).year;
      final recent = year >= thisYear - 8;
      final old = year <= thisYear - 20;
      if (profile.era == TasteEra.recent) {
        if (recent) factor *= 1.12;
        if (old) factor *= 0.8;
      } else {
        if (old) factor *= 1.25;
        if (recent) factor *= 0.85;
      }
    }
  }

  var penalty = 1.0;
  for (final genre in genres) {
    final count = feedback.genrePenalties[genre] ?? 0;
    if (count > 0) penalty *= math.pow(0.82, count).toDouble();
  }
  factor *= math.max(penalty, 0.3);

  return factor;
}

int? _releaseYear(SeerrDiscoverItem item) {
  final date = item.releaseDate ?? item.firstAirDate;
  if (date == null || date.length < 4) return null;
  return int.tryParse(date.substring(0, 4));
}
