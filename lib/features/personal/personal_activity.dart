import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _demoMode = bool.fromEnvironment('DEMO_MODE');

class ActivityDay {
  const ActivityDay({required this.date, required this.steps});
  final DateTime date;
  final int? steps;
}

final dailyGoalProvider = AsyncNotifierProvider<DailyGoalController, int>(DailyGoalController.new);

class DailyGoalController extends AsyncNotifier<int> {
  static const _key = 'daily_goal';

  @override
  Future<int> build() async => (await SharedPreferences.getInstance()).getInt(_key) ?? 10000;

  Future<void> setGoal(int goal) async {
    final normalized = goal.clamp(1000, 100000);
    state = AsyncData(normalized);
    await (await SharedPreferences.getInstance()).setInt(_key, normalized);
  }
}

final darkModeProvider = AsyncNotifierProvider<DarkModeController, bool>(DarkModeController.new);

class DarkModeController extends AsyncNotifier<bool> {
  static const _key = 'dark_mode';

  @override
  Future<bool> build() async => (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> setEnabled(bool enabled) async {
    state = AsyncData(enabled);
    await (await SharedPreferences.getInstance()).setBool(_key, enabled);
  }
}

/// Reads personal history directly from the phone's health store. Nothing is uploaded.
final activityHistoryProvider = FutureProvider.family<List<ActivityDay>, int>((ref, days) async {
  if (_demoMode) {
    final now = DateTime.now();
    return List.generate(days, (index) {
      final date = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1 - index));
      return ActivityDay(date: date, steps: 4000 + (index * 731) % 9000);
    });
  }
  try {
    final health = Health();
    await health.configure();
    if (Platform.isAndroid && !(await health.isHealthConnectAvailable())) return const [];
    final access = await health.hasPermissions(
      [HealthDataType.STEPS],
      permissions: [HealthDataAccess.READ],
    );
    if (access == false) return const [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = <ActivityDay>[];
    for (var index = days - 1; index >= 0; index--) {
      final start = today.subtract(Duration(days: index));
      final end = index == 0 ? now : start.add(const Duration(days: 1));
      final steps = await health.getTotalStepsInInterval(start, end);
      result.add(ActivityDay(date: start, steps: steps));
    }
    return result;
  } catch (_) {
    return const [];
  }
});

int currentStreak(List<ActivityDay> history, int goal) {
  var streak = 0;
  for (final day in history.reversed) {
    if ((day.steps ?? 0) < goal) break;
    streak++;
  }
  return streak;
}
