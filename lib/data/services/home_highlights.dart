/// Small decisions behind the streaming-style touches on the home screen:
/// the Top 10 row, the Surprise row and the New badge.
library;

import '../models/aggregated_item.dart';
import 'seerr/seerr_api_models.dart';

/// Jellyfin ids of the trending titles this server can already play, in
/// trending order, at most [limit] of them.
List<String> playableTrendingIds(
  Iterable<SeerrDiscoverItem> trending, {
  int limit = 10,
}) {
  final ids = <String>[];
  final seen = <String>{};
  for (final item in trending) {
    final status = item.mediaInfo?.status;
    if (status != SeerrMediaStatus.available &&
        status != SeerrMediaStatus.partiallyAvailable) {
      continue;
    }
    final id = item.mediaInfo?.jellyfinMediaId;
    if (id == null || id.isEmpty || !seen.add(id)) continue;
    ids.add(id);
    if (ids.length >= limit) break;
  }
  return ids;
}

/// How long a title counts as new on its card.
const freshlyAddedWindow = Duration(days: 10);

/// Whether a card gets the New badge: a movie or episode added lately that
/// nobody started yet. Series are left out, since adding an episode doesn't
/// date the series itself.
bool isFreshlyAdded(AggregatedItem item, {DateTime? now}) {
  final type = item.type;
  if (type != 'Movie' && type != 'Episode') return false;
  if (item.isPlayed) return false;
  if ((item.playedPercentage ?? 0) > 0) return false;
  final created = item.dateCreated;
  if (created == null) return false;
  final age = (now ?? DateTime.now()).difference(created);
  return !age.isNegative && age <= freshlyAddedWindow;
}

/// The first well-rated title of a random draw, or the first one at all
/// when none is, so the Surprise row has something to offer.
AggregatedItem? pickSurprise(
  List<AggregatedItem> randomDraw, {
  double minRating = 6.5,
}) {
  for (final item in randomDraw) {
    if ((item.communityRating ?? 0) >= minRating) return item;
  }
  return randomDraw.isEmpty ? null : randomDraw.first;
}
