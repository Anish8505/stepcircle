import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/providers.dart';
import '../friends/friends_providers.dart';

const _demoMode = bool.fromEnvironment('DEMO_MODE');
const _cloudFeaturesEnabled = bool.fromEnvironment('CLOUD_FEATURES_ENABLED');
const _permissionsChannel = MethodChannel('stepcircle/permissions');

enum StepSyncStatus { ready, needsAuthorization, healthConnectUnavailable, error }

class DailyStepsState {
  const DailyStepsState({
    required this.status,
    this.steps,
    this.lastSyncedAt,
    this.message,
    this.isDemo = false,
  });

  const DailyStepsState.needsAuthorization()
    : this(status: StepSyncStatus.needsAuthorization);

  final StepSyncStatus status;
  final int? steps;
  final DateTime? lastSyncedAt;
  final String? message;
  final bool isDemo;
}

final dailyStepsProvider =
    AsyncNotifierProvider<DailyStepsController, DailyStepsState>(
      DailyStepsController.new,
    );

/// Used only to preview the app. Normal builds never fabricate health data.
final currentFriendsRankProvider = Provider<int?>((ref) {
  if (_demoMode) return 2;
  final user = ref.watch(authStateProvider).asData?.value;
  final entries = ref.watch(friendLeaderboardProvider).asData?.value;
  if (user == null || entries == null) return null;
  for (final entry in entries) {
    if (entry.userId == user.uid) return entry.rank;
  }
  return null;
});

class DailyStepsController extends AsyncNotifier<DailyStepsState> {
  final Health _health = Health();
  bool _cloudSyncInFlight = false;

  static const _minimumCloudSyncInterval = Duration(minutes: 15);

  @override
  Future<DailyStepsState> build() => _loadExistingAccess();

  Future<DailyStepsState> _loadExistingAccess() async {
    if (_demoMode) {
      return DailyStepsState(
        status: StepSyncStatus.ready,
        steps: 7246,
        lastSyncedAt: DateTime.now(),
        isDemo: true,
      );
    }

    try {
      await _health.configure();
      if (Platform.isAndroid && !(await _health.isHealthConnectAvailable())) {
        return const DailyStepsState(
          status: StepSyncStatus.healthConnectUnavailable,
          message: 'Install or update Health Connect to continue.',
        );
      }

      final hasAccess = await _health.hasPermissions(
        [HealthDataType.STEPS],
        permissions: [HealthDataAccess.READ],
      );
      if (hasAccess == false) return const DailyStepsState.needsAuthorization();
      return _readToday();
    } catch (_) {
      return const DailyStepsState(
        status: StepSyncStatus.error,
        message: 'Step data could not be read. Try again after connecting health data.',
      );
    }
  }

  Future<DailyStepsState> _readToday() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final steps = await _health.getTotalStepsInInterval(start, now);
    if (steps == null) {
      return const DailyStepsState(
        status: StepSyncStatus.error,
        message: 'No step total is available from your health app yet.',
      );
    }
    final result = DailyStepsState(
      status: StepSyncStatus.ready,
      steps: steps,
      lastSyncedAt: now,
    );
    unawaited(_syncToSecureBackend(result));
    return result;
  }

  Future<void> _syncToSecureBackend(DailyStepsState state) async {
    if (!_cloudFeaturesEnabled || _cloudSyncInFlight) return;
    final user = ref.read(authStateProvider).asData?.value;
    final syncedAt = state.lastSyncedAt;
    final steps = state.steps;
    if (user == null || syncedAt == null || steps == null) return;

    final preferences = await SharedPreferences.getInstance();
    final dateKey = localDateKey(syncedAt);
    final keyPrefix = 'cloud_step_sync_${user.uid}_$dateKey';
    final previousSteps = preferences.getInt('${keyPrefix}_steps');
    final previousAtMillis = preferences.getInt('${keyPrefix}_at');
    final previousAt = previousAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(previousAtMillis);

    if (previousSteps == steps &&
        previousAt != null &&
        syncedAt.difference(previousAt) < _minimumCloudSyncInterval) {
      return;
    }

    _cloudSyncInFlight = true;
    try {
      await ref.read(functionsRepositoryProvider).syncDailySteps(
        dateKey: dateKey,
        steps: steps,
      );
      await preferences.setInt('${keyPrefix}_steps', steps);
      await preferences.setInt('${keyPrefix}_at', syncedAt.millisecondsSinceEpoch);
    } catch (_) {
      // The local health reading stays visible if the backend is temporarily offline.
    } finally {
      _cloudSyncInFlight = false;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_loadExistingAccess);
  }

  Future<void> connectHealthData() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (_demoMode) return _loadExistingAccess();
      await _health.configure();
      if (Platform.isAndroid && !(await _health.isHealthConnectAvailable())) {
        await _health.installHealthConnect();
        return const DailyStepsState(
          status: StepSyncStatus.healthConnectUnavailable,
          message: 'Install Health Connect, then return here and tap Connect again.',
        );
      }
      if (Platform.isAndroid) {
        final activityRecognitionGranted =
            await _permissionsChannel.invokeMethod<bool>('requestActivityRecognition') ?? false;
        if (!activityRecognitionGranted) {
          return const DailyStepsState(
            status: StepSyncStatus.needsAuthorization,
            message: 'Allow Physical activity access before connecting your steps.',
          );
        }
      }
      final granted = await _health.requestAuthorization(
        [HealthDataType.STEPS],
        permissions: [HealthDataAccess.READ],
      );
      if (!granted) return const DailyStepsState.needsAuthorization();
      return _readToday();
    });
  }
}
