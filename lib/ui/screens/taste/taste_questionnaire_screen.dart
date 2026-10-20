import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/for_you_service.dart';
import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../data/services/seerr/taste_profile.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/seerr_preferences.dart';
import '../../widgets/seerr/seerr_image_urls.dart';

/// Opens the taste questionnaire. Returns true once the viewer saved
/// answers, so the caller can refresh what it suggests.
Future<bool> openTasteQuestionnaire(BuildContext context) async {
  final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const TasteQuestionnaireScreen(),
    ),
  );
  return saved == true;
}

/// A poster on offer, with the media type Seerr gave or the list implied.
typedef _Poster = ({SeerrDiscoverItem item, String type});

/// A short questionnaire that tells the suggestions what the viewer likes:
/// movies or series, moods, genres refused, recent or classic, languages,
/// and a few titles picked from their posters.
///
/// Six steps, each answerable in a few presses on a remote. Every step can
/// be left as it is, and the whole thing can be put off.
class TasteQuestionnaireScreen extends StatefulWidget {
  const TasteQuestionnaireScreen({super.key});

  @override
  State<TasteQuestionnaireScreen> createState() =>
      _TasteQuestionnaireScreenState();
}

class _TasteQuestionnaireScreenState extends State<TasteQuestionnaireScreen> {
  static const _steps = 6;
  static const maxPicks = 15;

  /// Original languages offered, as ISO 639-1 codes.
  static const _languages = ['fr', 'en', 'ru', 'uk', 'es', 'it', 'de', 'ja', 'ko'];

  final _prefs = GetIt.instance<SeerrPreferences>();

  int _step = 0;
  late TasteMediaPref _mediaPref;
  late TasteEra _era;
  late Set<TasteGenre> _liked;
  late Set<TasteGenre> _avoided;
  late Set<String> _languagesPicked;
  late Map<String, TastePick> _picks;

  List<_Poster>? _posters;
  bool _postersFailed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = TasteProfile.decode(_prefs.tasteProfileJson);
    _mediaPref = profile.mediaPref;
    _era = profile.era;
    _liked = {...profile.liked};
    _avoided = {...profile.avoided};
    _languagesPicked = {...profile.languages};
    _picks = {for (final pick in profile.favorites) pick.key: pick};
    _loadPosters();
  }

  /// Posters to choose from. Every list is asked for on its own, so one
  /// that this server cannot give does not take the others down.
  Future<void> _loadPosters() async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();

      Future<List<({SeerrDiscoverItem item, String type})>> list(
        Future<SeerrDiscoverPage> Function() load,
        String? fallbackType,
      ) async {
        try {
          final page = await load();
          return [
            for (final item in page.results)
              if ((item.mediaType ?? fallbackType) case final type?)
                (item: item, type: type),
          ];
        } catch (e) {
          debugPrint('[Taste] A poster list failed: $e');
          return const [];
        }
      }

      final pages = await Future.wait([
        list(() => repo.getTrending(limit: 20, offset: 0), null),
        list(() => repo.getTrendingMovies(limit: 20, offset: 0), 'movie'),
        list(() => repo.getTrendingTv(limit: 20, offset: 0), 'tv'),
        list(() => repo.getTrending(limit: 20, offset: 20), null),
        list(() => repo.getTrendingMovies(limit: 20, offset: 20), 'movie'),
        list(() => repo.getTrendingTv(limit: 20, offset: 20), 'tv'),
      ]);

      // Interleave the lists so the first posters already mix sources.
      final seen = <String>{};
      final items = <_Poster>[];
      final longest = pages.fold<int>(0, (m, p) => p.length > m ? p.length : m);
      for (var i = 0; i < longest; i++) {
        for (final page in pages) {
          if (i >= page.length) continue;
          final (:item, :type) = page[i];
          if (type != 'movie' && type != 'tv') continue;
          final poster = item.posterPath;
          if (poster == null || poster.isEmpty) continue;
          if (item.adult) continue;
          if (!seen.add('$type:${item.id}')) continue;
          items.add((item: item, type: type));
        }
      }
      if (!mounted) return;
      setState(() {
        _posters = items;
        _postersFailed = items.isEmpty;
      });
    } catch (e) {
      debugPrint('[Taste] Posters failed: $e');
      if (!mounted) return;
      setState(() => _postersFailed = true);
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    final profile = TasteProfile(
      mediaPref: _mediaPref,
      era: _era,
      liked: _liked,
      avoided: _avoided,
      languages: _languagesPicked,
      favorites: _picks.values.toList(),
      updatedAt: DateTime.now(),
    );
    await _prefs.setTasteProfileJson(profile.encode());
    await _prefs.setTastePromptedAt(DateTime.now().millisecondsSinceEpoch);
    ForYouService.instance.clearCache();
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _later() async {
    await _prefs.setTastePromptedAt(DateTime.now().millisecondsSinceEpoch);
    if (mounted) Navigator.of(context).pop(false);
  }

  void _next() {
    if (_step < _steps - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, hint) = switch (_step) {
      0 => (l10n.tasteMediaQuestion, l10n.tasteIntro),
      1 => (l10n.tasteMoodQuestion, l10n.tasteMoodHint),
      2 => (l10n.tasteAvoidedQuestion, l10n.tasteAvoidedHint),
      3 => (l10n.tasteEraQuestion, l10n.tasteEraHint),
      4 => (l10n.tasteLanguagesQuestion, l10n.tasteLanguagesHint),
      _ => (l10n.tastePicksQuestion, l10n.tastePicksHint(maxPicks)),
    };

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColorScheme.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, color: AppColorScheme.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.tasteTitle,
                        style: TextStyle(
                          color: AppColorScheme.onBackground,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      l10n.tasteStepOf(_step + 1, _steps),
                      style: TextStyle(
                        color: AppColorScheme.onBackground.withValues(
                          alpha: 0.6,
                        ),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (_step + 1) / _steps,
                    minHeight: 4,
                    color: AppColorScheme.accent,
                    backgroundColor: AppColorScheme.onBackground.withValues(
                      alpha: 0.12,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: TextStyle(
                    color: AppColorScheme.onBackground,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hint,
                  style: TextStyle(
                    color: AppColorScheme.onBackground.withValues(alpha: 0.7),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: FocusTraversalGroup(
                    key: ValueKey(_step),
                    child: _buildStep(l10n),
                  ),
                ),
                const SizedBox(height: 12),
                _buildFooter(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(AppLocalizations l10n) {
    switch (_step) {
      case 0:
        return _chips([
          for (final (i, pref) in TasteMediaPref.values.indexed)
            _TasteChip(
              label: switch (pref) {
                TasteMediaPref.both => l10n.tasteMediaBoth,
                TasteMediaPref.movies => l10n.tasteMediaMovies,
                TasteMediaPref.series => l10n.tasteMediaSeries,
              },
              icon: switch (pref) {
                TasteMediaPref.both => Icons.video_library_outlined,
                TasteMediaPref.movies => Icons.movie_outlined,
                TasteMediaPref.series => Icons.tv_outlined,
              },
              selected: _mediaPref == pref,
              autofocus: i == 0,
              onTap: () => setState(() => _mediaPref = pref),
            ),
        ]);
      case 1:
        return SingleChildScrollView(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (i, mood) in TasteMood.values.indexed)
                _MoodCard(
                  title: tasteMoodTitle(l10n, mood),
                  subtitle: tasteMoodSubtitle(l10n, mood),
                  icon: tasteMoodIcon(mood),
                  selected: mood.genres.every(_liked.contains),
                  autofocus: i == 0,
                  onTap: () => setState(() {
                    if (mood.genres.every(_liked.contains)) {
                      _liked.removeAll(mood.genres);
                    } else {
                      _liked.addAll(mood.genres);
                      _avoided.removeAll(mood.genres);
                    }
                  }),
                ),
            ],
          ),
        );
      case 2:
        return _chips([
          for (final (i, genre) in TasteGenre.values.indexed)
            _TasteChip(
              label: tasteGenreLabel(l10n, genre),
              selected: _avoided.contains(genre),
              danger: true,
              autofocus: i == 0,
              onTap: () => setState(() {
                if (!_avoided.remove(genre)) {
                  _avoided.add(genre);
                  _liked.remove(genre);
                }
              }),
            ),
        ]);
      case 3:
        return _chips([
          for (final (i, era) in TasteEra.values.indexed)
            _TasteChip(
              label: switch (era) {
                TasteEra.any => l10n.tasteEraAny,
                TasteEra.recent => l10n.tasteEraRecent,
                TasteEra.classic => l10n.tasteEraClassic,
              },
              icon: switch (era) {
                TasteEra.any => Icons.all_inclusive_rounded,
                TasteEra.recent => Icons.new_releases_outlined,
                TasteEra.classic => Icons.history_edu_outlined,
              },
              selected: _era == era,
              autofocus: i == 0,
              onTap: () => setState(() => _era = era),
            ),
        ]);
      case 4:
        return _chips([
          for (final (i, code) in _languages.indexed)
            _TasteChip(
              label: tasteLanguageLabel(l10n, code),
              selected: _languagesPicked.contains(code),
              autofocus: i == 0,
              onTap: () => setState(() {
                if (!_languagesPicked.remove(code)) _languagesPicked.add(code);
              }),
            ),
        ]);
      default:
        return _buildPosters(l10n);
    }
  }

  Widget _chips(List<Widget> chips) => SingleChildScrollView(
    child: Wrap(spacing: 10, runSpacing: 10, children: chips),
  );

  /// The posters worth showing given the answers so far: nothing from a
  /// refused genre, the kind of title preferred first, then the moods liked.
  List<_Poster> _orderedPosters(List<_Poster> posters) {
    final scored = <(_Poster, double)>[];
    for (final poster in posters) {
      final genres = TasteGenre.of(poster.item.genreIds, poster.type);
      if (genres.any(_avoided.contains)) continue;
      var score = genres.where(_liked.contains).length * 2.0;
      if (_mediaPref == TasteMediaPref.movies && poster.type == 'movie') {
        score += 1;
      }
      if (_mediaPref == TasteMediaPref.series && poster.type == 'tv') {
        score += 1;
      }
      final language = poster.item.originalLanguage;
      if (language != null && _languagesPicked.contains(language)) score += 1;
      scored.add((poster, score));
    }
    // A stable sort keeps the mixed order among equal scores.
    final indexed = [for (final (i, e) in scored.indexed) (i, e.$1, e.$2)];
    indexed.sort((a, b) {
      final byScore = b.$3.compareTo(a.$3);
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  Widget _buildPosters(AppLocalizations l10n) {
    final posters = _posters;
    if (posters == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_postersFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.tastePicksEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColorScheme.onBackground.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              autofocus: true,
              onPressed: () {
                setState(() {
                  _posters = null;
                  _postersFailed = false;
                });
                _loadPosters();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.tastePicksRetry),
            ),
          ],
        ),
      );
    }
    // Earlier picks first, so they can be unpicked without hunting.
    final picked = _picks.values.toList();
    final pickedKeys = _picks.keys.toSet();
    final rest = _orderedPosters(
      posters
          .where((p) => !pickedKeys.contains('${p.type}:${p.item.id}'))
          .toList(),
    );
    final tiles = <({String key, String title, String? poster, String type, int id})>[
      for (final p in picked)
        (key: p.key, title: p.title, poster: p.posterPath, type: p.mediaType, id: p.tmdbId),
      for (final p in rest)
        (
          key: '${p.type}:${p.item.id}',
          title: p.item.displayTitle,
          poster: p.item.posterPath,
          type: p.type,
          id: p.item.id,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.tastePicksCount(_picks.length),
          style: TextStyle(
            color: AppColorScheme.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              childAspectRatio: 2 / 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: tiles.length,
            itemBuilder: (context, index) {
              final tile = tiles[index];
              final selected = _picks.containsKey(tile.key);
              return _PosterTile(
                key: ValueKey(tile.key),
                title: tile.title,
                posterUrl: tile.poster == null || tile.poster!.isEmpty
                    ? null
                    : '$seerrPosterBase${tile.poster}',
                selected: selected,
                autofocus: index == 0,
                onTap: () => setState(() {
                  if (selected) {
                    _picks.remove(tile.key);
                  } else if (_picks.length < maxPicks) {
                    _picks[tile.key] = TastePick(
                      tmdbId: tile.id,
                      mediaType: tile.type,
                      title: tile.title,
                      posterPath: tile.poster,
                    );
                  }
                }),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    final last = _step == _steps - 1;
    return Row(
      children: [
        TextButton(
          onPressed: _saving ? null : (_step == 0 ? _later : _back),
          child: Text(_step == 0 ? l10n.tasteLater : l10n.tasteBack),
        ),
        const Spacer(),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColorScheme.accent,
            foregroundColor: AppColorScheme.onAccent,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          ),
          onPressed: _saving ? null : _next,
          icon: Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded),
          label: Text(last ? l10n.tasteFinish : l10n.tasteNext),
        ),
      ],
    );
  }
}

/// A pill that shows clearly when a remote is on it, and when it is chosen.
class _TasteChip extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final bool danger;
  final bool autofocus;
  final VoidCallback onTap;

  const _TasteChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.danger = false,
    this.autofocus = false,
  });

  @override
  State<_TasteChip> createState() => _TasteChipState();
}

class _TasteChipState extends State<_TasteChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onBg = AppColorScheme.onBackground;
    final tint = widget.danger ? const Color(0xFFE53935) : AppColorScheme.accent;
    final fill = widget.selected
        ? tint.withValues(alpha: 0.9)
        : onBg.withValues(alpha: 0.08);
    final text = widget.selected ? Colors.white : onBg;
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(24),
      onFocusChange: (f) => setState(() => _focused = f),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _focused ? onBg : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.selected)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  widget.danger ? Icons.block_rounded : Icons.check_rounded,
                  size: 18,
                  color: text,
                ),
              )
            else if (widget.icon != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(widget.icon, size: 18, color: text),
              ),
            Text(
              widget.label,
              style: TextStyle(
                color: text,
                fontSize: 15,
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A mood with a line saying what it covers, easy to see and press from a
/// couch.
class _MoodCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  const _MoodCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_MoodCard> createState() => _MoodCardState();
}

class _MoodCardState extends State<_MoodCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onBg = AppColorScheme.onBackground;
    final accent = AppColorScheme.accent;
    final selected = widget.selected;
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(14),
      onFocusChange: (f) => setState(() => _focused = f),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 250,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.9)
              : onBg.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused ? onBg : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : widget.icon,
              color: selected ? Colors.white : accent,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: selected ? Colors.white : onBg,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: (selected ? Colors.white : onBg).withValues(
                        alpha: 0.75,
                      ),
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterTile extends StatefulWidget {
  final String title;
  final String? posterUrl;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  const _PosterTile({
    super.key,
    required this.title,
    required this.posterUrl,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_PosterTile> createState() => _PosterTileState();
}

class _PosterTileState extends State<_PosterTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppColorScheme.accent;
    final url = widget.posterUrl;
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(10),
      onFocusChange: (f) => setState(() => _focused = f),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _focused ? 1.05 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.selected
                  ? accent
                  : (_focused ? Colors.white : Colors.transparent),
              width: 3,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url != null)
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _fallback(),
                  )
                else
                  _fallback(),
                if (widget.selected)
                  Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    alignment: Alignment.center,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: accent,
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback() => Container(
    color: Colors.white10,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(8),
    child: Text(
      widget.title,
      textAlign: TextAlign.center,
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    ),
  );
}

/// A questionnaire genre, as the viewer reads it.
String tasteGenreLabel(AppLocalizations l10n, TasteGenre genre) =>
    switch (genre) {
      TasteGenre.action => l10n.tasteGenreAction,
      TasteGenre.adventure => l10n.tasteGenreAdventure,
      TasteGenre.animation => l10n.tasteGenreAnimation,
      TasteGenre.comedy => l10n.tasteGenreComedy,
      TasteGenre.crime => l10n.tasteGenreCrime,
      TasteGenre.documentary => l10n.tasteGenreDocumentary,
      TasteGenre.drama => l10n.tasteGenreDrama,
      TasteGenre.family => l10n.tasteGenreFamily,
      TasteGenre.fantasy => l10n.tasteGenreFantasy,
      TasteGenre.history => l10n.tasteGenreHistory,
      TasteGenre.horror => l10n.tasteGenreHorror,
      TasteGenre.kids => l10n.tasteGenreKids,
      TasteGenre.music => l10n.tasteGenreMusic,
      TasteGenre.mystery => l10n.tasteGenreMystery,
      TasteGenre.reality => l10n.tasteGenreReality,
      TasteGenre.romance => l10n.tasteGenreRomance,
      TasteGenre.scifi => l10n.tasteGenreScifi,
      TasteGenre.talk => l10n.tasteGenreTalk,
      TasteGenre.thriller => l10n.tasteGenreThriller,
      TasteGenre.war => l10n.tasteGenreWar,
      TasteGenre.western => l10n.tasteGenreWestern,
    };

/// An original language the questionnaire offers, as the viewer reads it.
String tasteLanguageLabel(AppLocalizations l10n, String code) =>
    switch (code) {
      'fr' => l10n.tasteLangFr,
      'en' => l10n.tasteLangEn,
      'ru' => l10n.tasteLangRu,
      'uk' => l10n.tasteLangUk,
      'es' => l10n.tasteLangEs,
      'it' => l10n.tasteLangIt,
      'de' => l10n.tasteLangDe,
      'ja' => l10n.tasteLangJa,
      'ko' => l10n.tasteLangKo,
      _ => code,
    };

/// A questionnaire mood, as the viewer reads it.
String tasteMoodTitle(AppLocalizations l10n, TasteMood mood) => switch (mood) {
  TasteMood.darkPlots => l10n.tasteMoodDark,
  TasteMood.adrenaline => l10n.tasteMoodAdrenaline,
  TasteMood.imaginary => l10n.tasteMoodImaginary,
  TasteMood.trueStories => l10n.tasteMoodTrue,
  TasteMood.intenseDrama => l10n.tasteMoodDrama,
  TasteMood.feelGood => l10n.tasteMoodFeelGood,
  TasteMood.chills => l10n.tasteMoodChills,
  TasteMood.animated => l10n.tasteMoodAnimated,
  TasteMood.family => l10n.tasteMoodFamily,
};

String tasteMoodSubtitle(AppLocalizations l10n, TasteMood mood) =>
    switch (mood) {
      TasteMood.darkPlots => l10n.tasteMoodDarkSub,
      TasteMood.adrenaline => l10n.tasteMoodAdrenalineSub,
      TasteMood.imaginary => l10n.tasteMoodImaginarySub,
      TasteMood.trueStories => l10n.tasteMoodTrueSub,
      TasteMood.intenseDrama => l10n.tasteMoodDramaSub,
      TasteMood.feelGood => l10n.tasteMoodFeelGoodSub,
      TasteMood.chills => l10n.tasteMoodChillsSub,
      TasteMood.animated => l10n.tasteMoodAnimatedSub,
      TasteMood.family => l10n.tasteMoodFamilySub,
    };

IconData tasteMoodIcon(TasteMood mood) => switch (mood) {
  TasteMood.darkPlots => Icons.search_rounded,
  TasteMood.adrenaline => Icons.bolt_rounded,
  TasteMood.imaginary => Icons.auto_awesome_rounded,
  TasteMood.trueStories => Icons.menu_book_rounded,
  TasteMood.intenseDrama => Icons.theater_comedy_rounded,
  TasteMood.feelGood => Icons.sentiment_very_satisfied_rounded,
  TasteMood.chills => Icons.nightlight_round,
  TasteMood.animated => Icons.animation_rounded,
  TasteMood.family => Icons.family_restroom_rounded,
};
