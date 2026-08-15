import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/rank/rank_color_theme.dart';
import '../steps_controller.dart';

class MyStepsTab extends ConsumerStatefulWidget {
  const MyStepsTab({super.key});

  @override
  ConsumerState<MyStepsTab> createState() => _MyStepsTabState();
}

class _MyStepsTabState extends ConsumerState<MyStepsTab>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.read(dailyStepsProvider.notifier).refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(dailyStepsProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stepsState = ref.watch(dailyStepsProvider);
    final rank = ref.watch(currentFriendsRankProvider);
    final rankTheme = RankColorTheme.forRank(rank);
    final pageBackground = switch (rank) {
      1 => const Color(0xFFDCFCE7),
      2 => const Color(0xFFFFE0B2),
      3 => const Color(0xFFFEF08A),
      _ => Theme.of(context).scaffoldBackgroundColor,
    };
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pageBackground, Theme.of(context).scaffoldBackgroundColor],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: () => ref.read(dailyStepsProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 36),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My Steps',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Small steps. Real momentum.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.86),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: 'Settings',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Center(
              child: Container(
                width: 238,
                height: 238,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, scheme.secondary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.28),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.surface,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_walk_rounded, color: scheme.primary),
                        const SizedBox(height: 6),
                        stepsState.when(
                          loading: () => const _StepsValue(value: '-'),
                          error: (_, _) => const _StepsValue(value: '-'),
                          data: (data) => _StepsValue(
                            value: data.status == StepSyncStatus.ready
                                ? data.steps!.toString()
                                : '-',
                          ),
                        ),
                        Text(
                          'steps today',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
              decoration: BoxDecoration(
                color: rankTheme.background,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: rankTheme.foreground.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.emoji_events_rounded, color: rankTheme.foreground),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      rank == null ? rankTheme.label : 'Rank #$rank - ${rankTheme.label}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: rankTheme.foreground,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            stepsState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _ConnectHealthCard(
                message: 'Step data could not be loaded.',
                onPressed: () => ref.read(dailyStepsProvider.notifier).connectHealthData(),
              ),
              data: (data) => _HealthStatus(
                data: data,
                onConnect: () => ref.read(dailyStepsProvider.notifier).connectHealthData(),
                onRefresh: () => ref.read(dailyStepsProvider.notifier).refresh(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepsValue extends StatelessWidget {
  const _StepsValue({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) => Text(
        value,
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -2.5,
              fontSize: 47,
            ),
      );
}

class _HealthStatus extends StatelessWidget {
  const _HealthStatus({
    required this.data,
    required this.onConnect,
    required this.onRefresh,
  });

  final DailyStepsState data;
  final VoidCallback onConnect;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (data.status != StepSyncStatus.ready) {
      return _ConnectHealthCard(message: data.message, onPressed: onConnect);
    }
    final time = data.lastSyncedAt;
    final timeLabel = time == null
        ? 'Not synced yet'
        : 'Last synced ${TimeOfDay.fromDateTime(time).format(context)}';
    return Column(
      children: [
        Text(timeLabel, style: Theme.of(context).textTheme.bodySmall),
        if (data.isDemo) ...[
          const SizedBox(height: 6),
          Text('Demo data', style: Theme.of(context).textTheme.labelSmall),
        ],
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh steps'),
        ),
      ],
    );
  }
}

class _ConnectHealthCard extends StatelessWidget {
  const _ConnectHealthCard({this.message, required this.onPressed});
  final String? message;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.health_and_safety_rounded,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text('Connect health data', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(message ?? 'Allow access to today\'s steps from your health app.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.link_rounded),
                label: const Text('Connect Health Connect'),
              ),
            ],
          ),
        ),
      );
}
