import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// The key BetaSeries gave this app. Like any API key of an app it travels
/// with every request. The secret that goes with it is not needed here.
const betaSeriesApiKey = '09fe278bf39e';

/// The French side of the charts and suggestions: what BetaSeries' members
/// follow, watch and tie together.
class BetaSeriesClient {
  BetaSeriesClient({Dio? dio, String apiKey = betaSeriesApiKey})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.betaseries.com',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'X-BetaSeries-Key': apiKey,
                'X-BetaSeries-Version': '3.0',
              },
            ),
          );

  final Dio _dio;

  /// The countries BetaSeries ranks on its own, the others get the world.
  static const _rankedCountries = {'fr', 'de', 'es'};

  /// A series keeps its TMDB id, so it is asked once.
  final Map<int, int> _tmdbIds = {};

  /// The members' similar titles change little, so they are asked once per
  /// title and run of the app, keyed by `movie:` or `tv:` and the TMDB id.
  final Map<String, List<int>> _similars = {};

  /// The TMDB ids of the series watched most over the last seven days on the
  /// streaming services of [country], best first. BetaSeries ranks by its own
  /// ids, so each one is looked up; a series that fails is left out.
  Future<List<int>> showChart({required String country, int limit = 10}) async {
    final code = country.toLowerCase();
    final response = await _dio.get<Object?>(
      '/stats/shows_ranking',
      queryParameters: {
        'country': _rankedCountries.contains(code) ? code : 'all',
        'genre': 'all',
        'limit': limit,
      },
    );
    final tmdbIds = await Future.wait([
      for (final showId in parseBetaSeriesRanking(response.data))
        _tmdbIdOf(showId),
    ]);
    return [for (final id in tmdbIds) ?id];
  }

  /// The TMDB ids of the films BetaSeries' members follow most, best first.
  Future<List<int>> movieChart({int limit = 20}) async {
    final response = await _dio.get<Object?>(
      '/movies/list',
      queryParameters: {'order': 'popularity', 'limit': limit},
    );
    return parseBetaSeriesMovies(response.data);
  }

  /// The TMDB ids of the films BetaSeries' members tie to the film [tmdbId],
  /// the most followed first.
  Future<List<int>> similarMovies(int tmdbId) async {
    final key = 'movie:$tmdbId';
    final known = _similars[key];
    if (known != null) return known;
    final movie = await _dio.get<Object?>(
      '/movies/movie',
      queryParameters: {'tmdb_id': tmdbId},
    );
    final id = parseBetaSeriesMovieId(movie.data);
    if (id == null) return _similars[key] = const [];
    final response = await _dio.get<Object?>(
      '/movies/similars',
      queryParameters: {'id': id, 'details': 'true'},
    );
    return _similars[key] = parseBetaSeriesSimilars(
      response.data,
      mediaType: 'movie',
    );
  }

  /// The TMDB ids of the series BetaSeries' members tie to the series
  /// [tmdbId], the most followed first. BetaSeries finds a series by its
  /// TheTVDB id, which [tvdbIdOf] gives.
  Future<List<int>> similarShows(
    int tmdbId, {
    required Future<int?> Function() tvdbIdOf,
  }) async {
    final key = 'tv:$tmdbId';
    final known = _similars[key];
    if (known != null) return known;
    final tvdbId = await tvdbIdOf();
    if (tvdbId == null) return _similars[key] = const [];
    final response = await _dio.get<Object?>(
      '/shows/similars',
      queryParameters: {'thetvdb_id': tvdbId, 'details': 'true'},
    );
    return _similars[key] = parseBetaSeriesSimilars(
      response.data,
      mediaType: 'tv',
    );
  }

  Future<int?> _tmdbIdOf(int showId) async {
    final known = _tmdbIds[showId];
    if (known != null) return known;
    try {
      final response = await _dio.get<Object?>(
        '/shows/display',
        queryParameters: {'id': showId},
      );
      final tmdbId = parseBetaSeriesShowTmdbId(response.data);
      if (tmdbId != null) _tmdbIds[showId] = tmdbId;
      return tmdbId;
    } catch (e) {
      debugPrint('[BetaSeries] No TMDB id for show $showId: $e');
      return null;
    }
  }
}

/// The BetaSeries ids in a series ranking, best first.
List<int> parseBetaSeriesRanking(Object? json) {
  final shows = json is Map ? json['shows'] : null;
  if (shows is! List) return const [];
  return [
    for (final show in shows)
      if (show is Map && show['show_id'] is int) show['show_id'] as int,
  ];
}

/// The TMDB ids in a list of films, in order; a film BetaSeries has no TMDB
/// id for is skipped.
List<int> parseBetaSeriesMovies(Object? json) {
  final movies = json is Map ? json['movies'] : null;
  if (movies is! List) return const [];
  return [
    for (final movie in movies)
      if (movie is Map && movie['tmdb_id'] is int && movie['tmdb_id'] > 0)
        movie['tmdb_id'] as int,
  ];
}

/// The TMDB id of a series in BetaSeries' description of it, if it has one.
int? parseBetaSeriesShowTmdbId(Object? json) {
  final show = json is Map ? json['show'] : null;
  final id = show is Map ? show['themoviedb_id'] : null;
  return id is int && id > 0 ? id : null;
}

/// BetaSeries' own id for a film in its description of it.
int? parseBetaSeriesMovieId(Object? json) {
  final movie = json is Map ? json['movie'] : null;
  final id = movie is Map ? movie['id'] : null;
  return id is int && id > 0 ? id : null;
}

/// The TMDB ids in a list of similar titles, the most followed first, each
/// once. Members add similar titles in no order, so how many follow each
/// one is the best guide to which to show.
List<int> parseBetaSeriesSimilars(Object? json, {required String mediaType}) {
  final similars = json is Map ? json['similars'] : null;
  if (similars is! List) return const [];
  final key = mediaType == 'tv' ? 'show' : 'movie';
  final idField = mediaType == 'tv' ? 'themoviedb_id' : 'tmdb_id';
  final found = <({int id, int followers, int order})>[];
  final seen = <int>{};
  for (final similar in similars) {
    final title = similar is Map ? similar[key] : null;
    if (title is! Map) continue;
    final id = title[idField];
    if (id is! int || id <= 0 || !seen.add(id)) continue;
    final followers = title['followers'];
    found.add((
      id: id,
      followers: followers is int ? followers : 0,
      order: found.length,
    ));
  }
  found.sort((a, b) {
    final byFollowers = b.followers.compareTo(a.followers);
    return byFollowers != 0 ? byFollowers : a.order.compareTo(b.order);
  });
  return [for (final title in found) title.id];
}
