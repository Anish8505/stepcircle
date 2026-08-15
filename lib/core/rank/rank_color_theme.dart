import 'package:flutter/material.dart';

/// Visual treatment for a verified leaderboard position.
/// Production has no position until the secure direct-friends backend supplies one.
class RankColorTheme {
  const RankColorTheme._({
    required this.background,
    required this.foreground,
    required this.label,
  });

  final Color background;
  final Color foreground;
  final String label;

  static RankColorTheme forRank(int? rank) => switch (rank) {
    1 => const RankColorTheme._(
      background: Color(0xFFDCFCE7),
      foreground: Color(0xFF166534),
      label: 'First place',
    ),
    2 => const RankColorTheme._(
      background: Color(0xFFFFEDD5),
      foreground: Color(0xFF9A3412),
      label: 'Second place',
    ),
    3 => const RankColorTheme._(
      background: Color(0xFFFEF9C3),
      foreground: Color(0xFF854D0E),
      label: 'Third place',
    ),
    _ => const RankColorTheme._(
      background: Color(0xFFF1F5F9),
      foreground: Color(0xFF475569),
      label: 'Rank available after you add friends',
    ),
  };
}
