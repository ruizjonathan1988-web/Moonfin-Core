import 'package:flutter/foundation.dart';

import '../../repositories/seerr_repository.dart';
import 'for_you_ranker.dart';
import 'for_you_service.dart';
import 'seerr_api_models.dart';
import 'taste_profile.dart';

/// Picked favourites, the Seerr watchlist and the viewer's own requests,
/// as interest the watch history can't show.
Future<TasteExtras> loadTasteExtras(
  SeerrRepository repo,
  TasteProfile profile,
) async {
  final picked = [
    // An all-time favourite says three times what a liked title says.
    for (final pick in profile.pivots)
      TasteSignal(
        tmdbId: pick.tmdbId,
        mediaType: pick.mediaType,
        title: pick.title,
        strength: 3,
      ),
    for (final pick in profile.favorites)
      TasteSignal(
        tmdbId: pick.tmdbId,
        mediaType: pick.mediaType,
        title: pick.title,
      ),
  ];

  Future<List<TasteSignal>> watchlist() async {
    try {
      final page = await repo.getWatchlist(page: 1);
      return [
        for (final item in page.results)
          if (item.mediaType == 'movie' || item.mediaType == 'tv')
            TasteSignal(
              tmdbId: item.id,
              mediaType: item.mediaType!,
              title: item.displayTitle,
            ),
      ];
    } catch (e) {
      debugPrint('[ForYou] Watchlist signals failed: $e');
      return const [];
    }
  }

  Future<List<TasteSignal>> requested() async {
    try {
      final user = await repo.getCurrentUser();
      final response = await repo.getRequests(requestedBy: user.id, limit: 30);
      return [
        for (final request in response.results)
          if (request.status != SeerrRequest.statusDeclined &&
              request.media?.tmdbId != null)
            TasteSignal(
              tmdbId: request.media!.tmdbId!,
              mediaType: request.type == 'tv' ? 'tv' : 'movie',
              title: request.media!.title ?? request.media!.name ?? '',
            ),
      ];
    } catch (e) {
      debugPrint('[ForYou] Request signals failed: $e');
      return const [];
    }
  }

  final results = await Future.wait([watchlist(), requested()]);
  return TasteExtras(
    picked: picked,
    watchlist: results[0],
    requested: results[1],
  );
}
