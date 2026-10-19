import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../l10n/app_localizations.dart';

/// The fold line when a foldable stands half-open like a small laptop with
/// the fold running across the screen, or null in any other posture.
///
/// Flutter reports the hinge of a Galaxy Z Fold and similar through
/// [MediaQueryData.displayFeatures], with its posture.
Rect? tabletopFold(MediaQueryData media) {
  for (final feature in media.displayFeatures) {
    if (feature.type != DisplayFeatureType.fold &&
        feature.type != DisplayFeatureType.hinge) {
      continue;
    }
    if (feature.state != DisplayFeatureState.postureHalfOpened) continue;
    final bounds = feature.bounds;
    final spansWidth = bounds.width >= media.size.width * 0.9;
    if (spansWidth && bounds.width > bounds.height) return bounds;
  }
  return null;
}

/// Lays the player out for a half-folded phone: the picture on the upper
/// half, a control deck on the lower half resting on the table, the way
/// YouTube does on Samsung's Flex mode.
///
/// Builds the same tree in every posture so [child] keeps its state, focus
/// and video surface when the phone is folded or opened mid-playback.
class TabletopLayout extends StatelessWidget {
  final bool enabled;
  final Widget child;
  final WidgetBuilder panelBuilder;

  const TabletopLayout({
    super.key,
    required this.enabled,
    required this.child,
    required this.panelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final fold = enabled ? tabletopFold(media) : null;
    final topHeight = fold?.top ?? media.size.height;
    final bottomInset = media.size.height - topHeight;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: bottomInset,
          child: MediaQuery(
            // The player sizes its overlays from MediaQuery, so tell it how
            // much screen it really has.
            data: fold == null
                ? media
                : media.copyWith(
                    size: Size(media.size.width, topHeight),
                    padding: media.padding.copyWith(bottom: 0),
                    viewPadding: media.viewPadding.copyWith(bottom: 0),
                  ),
            child: child,
          ),
        ),
        if (fold != null)
          Positioned(
            left: 0,
            right: 0,
            top: fold.bottom,
            bottom: 0,
            child: panelBuilder(context),
          ),
      ],
    );
  }
}

/// The lower half in tabletop posture: title, progress and big buttons
/// that are easy to hit on a phone resting on a table.
class TabletopControlPanel extends StatelessWidget {
  final String title;
  final Stream<Duration> positionStream;
  final Duration initialPosition;
  final Duration Function() duration;
  final Stream<bool> playingStream;
  final bool initialPlaying;
  final VoidCallback onTogglePlay;
  final void Function(int milliseconds) onSeekRelative;

  const TabletopControlPanel({
    super.key,
    required this.title,
    required this.positionStream,
    required this.initialPosition,
    required this.duration,
    required this.playingStream,
    required this.initialPlaying,
    required this.onTogglePlay,
    required this.onSeekRelative,
  });

  static String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accent = AppColorScheme.accent;
    return ColoredBox(
      color: const Color(0xFF0B0B0D),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (title.isNotEmpty)
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 10),
              StreamBuilder<Duration>(
                stream: positionStream,
                initialData: initialPosition,
                builder: (context, snap) {
                  final position = snap.data ?? Duration.zero;
                  final total = duration();
                  final progress = total.inMilliseconds <= 0
                      ? 0.0
                      : (position.inMilliseconds / total.inMilliseconds)
                            .clamp(0.0, 1.0);
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
                          color: accent,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            _clock(position),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '-${_clock(total - position < Duration.zero ? Duration.zero : total - position)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: l10n.tabletopRewind,
                    iconSize: 40,
                    color: Colors.white,
                    onPressed: () => onSeekRelative(-10000),
                    icon: const Icon(Icons.replay_10_rounded),
                  ),
                  const SizedBox(width: 28),
                  StreamBuilder<bool>(
                    stream: playingStream,
                    initialData: initialPlaying,
                    builder: (context, snap) {
                      final playing = snap.data ?? false;
                      return IconButton.filled(
                        iconSize: 48,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: onTogglePlay,
                        icon: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 28),
                  IconButton(
                    tooltip: l10n.tabletopForward,
                    iconSize: 40,
                    color: Colors.white,
                    onPressed: () => onSeekRelative(10000),
                    icon: const Icon(Icons.forward_10_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
