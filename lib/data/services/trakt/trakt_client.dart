import 'package:dio/dio.dart';

/// The id Trakt gave this app. Like any client id it travels with every
/// request, so it is public by nature.
const traktClientId = 'TCAqoSzejS8EETqVZUEc3c0RhsSgxYcM-HYt0_vcHpE';

/// A chart Trakt keeps without any account, built from what its members
/// scrobble, so it follows what people really watch.
enum TraktChart {
  /// The most watched over the last seven days.
  watchedWeekly('watched/weekly'),

  /// What is being watched right now.
  trending('trending');

  const TraktChart(this.path);

  final String path;
}

/// The public side of the Trakt API.
class TraktClient {
  TraktClient({Dio? dio, String clientId = traktClientId})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.trakt.tv',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'Content-Type': 'application/json',
                'trakt-api-version': '2',
                'trakt-api-key': clientId,
              },
            ),
          );

  final Dio _dio;

  /// The TMDB ids of [chart] for [mediaType] (`movie` or `tv`), best first.
  Future<List<int>> chart(
    TraktChart chart,
    String mediaType, {
    int limit = 20,
  }) async {
    final response = await _dio.get<Object?>(
      '/${mediaType == 'tv' ? 'shows' : 'movies'}/${chart.path}',
      queryParameters: {'limit': limit},
    );
    return parseTraktChart(response.data, mediaType: mediaType);
  }
}

/// The TMDB ids in a Trakt chart answer, in order. Each entry holds its title
/// under `movie` or `show`; one Trakt could not match to TMDB is skipped.
List<int> parseTraktChart(Object? json, {required String mediaType}) {
  if (json is! List) return const [];
  final key = mediaType == 'tv' ? 'show' : 'movie';
  final ids = <int>[];
  for (final entry in json) {
    final title = entry is Map ? entry[key] : null;
    final tmdb = title is Map && title['ids'] is Map
        ? (title['ids'] as Map)['tmdb']
        : null;
    if (tmdb is int && !ids.contains(tmdb)) ids.add(tmdb);
  }
  return ids;
}
