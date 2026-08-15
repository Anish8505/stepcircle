import 'package:flutter_test/flutter_test.dart';
import 'package:step_circle/core/rank/rank_color_theme.dart';

void main() {
  group('rank presentation', () {
    test('uses the specified podium labels', () {
      expect(RankColorTheme.forRank(1).label, 'First place');
      expect(RankColorTheme.forRank(2).label, 'Second place');
      expect(RankColorTheme.forRank(3).label, 'Third place');
    });

    test('uses a neutral fallback for non-podium rankings', () {
      expect(RankColorTheme.forRank(4).label, contains('Rank'));
      expect(RankColorTheme.forRank(null).label, contains('Rank'));
    });
  });
}
