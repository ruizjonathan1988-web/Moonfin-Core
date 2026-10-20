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
  // A file the server couldn't identify has no poster and no series: a
  // loose download, not something new to watch.
  if (type == 'Movie' && item.primaryImageTag == null) return false;
  if (type == 'Episode' && item.rawData['SeriesId'] == null) return false;
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

/// Genre names a family film can carry. The server names genres in its
/// metadata language, so English and French both appear.
const familyGenreNames = [
  'Family',
  'Familial',
  'Famille',
  'Animation',
  'Kids',
  'Children',
  'Jeunesse',
];

/// Family night: unwatched family films, best rated first among a random
/// draw so the row changes from one evening to the next.
List<AggregatedItem> pickFamilyNight(
  List<AggregatedItem> randomDraw, {
  int limit = 15,
  double minRating = 6.0,
}) {
  final seen = <String>{};
  final rated = <AggregatedItem>[];
  final rest = <AggregatedItem>[];
  for (final item in randomDraw) {
    if (!seen.add(item.id)) continue;
    if (item.primaryImageTag == null) continue;
    if ((item.communityRating ?? 0) >= minRating) {
      rated.add(item);
    } else {
      rest.add(item);
    }
  }
  rated.sort(
    (a, b) => (b.communityRating ?? 0).compareTo(a.communityRating ?? 0),
  );
  return [...rated, ...rest].take(limit).toList();
}
