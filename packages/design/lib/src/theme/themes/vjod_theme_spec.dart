import 'package:flutter/material.dart';

import '../theme_spec.dart';

/// VJOD: near black rather than pure black, which tires the eye on a TV, an
/// ivory halo for whatever is selected, and statuses in soft, distinct hues.
/// The logo's red stays out of the chrome: a saturated red glares on a TV.
const vjodThemeSpec = ThemeSpec(
  id: 'vjod',
  displayName: 'VJOD',
  semantic: ThemeSemanticTokens(
    statusAvailable: Color(0xFF7FD6A8),
    statusRequested: Color(0xFFE3C07E),
    statusPending: Color(0xFFE3C07E),
    statusDownloading: Color(0xFF8DB8F2),
    statusError: Color(0xFFE07A7A),
    mediaTypeBadgeMovie: Color(0xFF8DB8F2),
    mediaTypeBadgeShow: Color(0xFFC9A7E8),
  ),
  colors: ThemeColorTokens(
    background: Color(0xFF0B0B0D),
    onBackground: Color(0xFFEDEBE6),
    surface: Color(0xFF16171B),
    onSurface: Color(0xFFEDEBE6),
    surfaceVariant: Color(0xFF1F2026),
    scrim: Color(0xD90B0B0D),
    accent: Color(0xFFEDEBE6),
    onAccent: Color(0xFF0B0B0D),
    buttonNormal: Color(0x29EDEBE6),
    buttonFocused: Color(0xFFEDEBE6),
    buttonDisabled: Color(0x14EDEBE6),
    buttonActive: Color(0x40EDEBE6),
    onButtonNormal: Color(0xFFEDEBE6),
    onButtonFocused: Color(0xFF0B0B0D),
    onButtonDisabled: Color(0x80EDEBE6),
    inputBackground: Color(0xFF1F2026),
    inputFocused: Color(0xFF2A2B31),
    inputBorder: Color(0xFF34363D),
    inputBorderFocused: Color(0xFFEDEBE6),
    rangeTrack: Color(0x40EDEBE6),
    rangeProgress: Color(0xFFEDEBE6),
    rangeThumb: Color(0xFFEDEBE6),
    seekbarBuffered: Color(0x66EDEBE6),
    badgeBackground: Color(0xFF2A2B31),
    onBadge: Color(0xFFEDEBE6),
    badgeUnplayed: Color(0xFFEDEBE6),
    badgeWatched: Color(0xFF7FD6A8),
    recordingActive: Color(0xFFC93A3A),
    recordingScheduled: Color(0xFFE3C07E),
    error: Color(0xFFE07A7A),
  ),
  borders: ThemeBorderTokens(
    cardBorder: BorderSide(color: Colors.transparent),
    chipBorder: BorderSide(color: Color(0x33EDEBE6)),
    focusBorder: BorderSide(color: Color(0xFFEDEBE6), width: 3),
    // Barely rounded, like a film poster.
    cardRadius: BorderRadius.all(Radius.circular(6)),
    chipRadius: BorderRadius.all(Radius.circular(999)),
    chipBackground: Color(0x1FEDEBE6),
    focusGlow: [
      BoxShadow(color: Color(0x40EDEBE6), blurRadius: 18, spreadRadius: 1),
    ],
  ),
);
