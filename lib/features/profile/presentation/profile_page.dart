import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/rank/rank_color_theme.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../auth/providers.dart';
import '../../friends/friends_providers.dart';
import '../../personal/personal_activity.dart';
import '../../steps/steps_controller.dart';

/// Shows either the signed-in person's private activity or a direct friend's
/// safe, viewer-specific leaderboard status. Firestore rules block any other
/// profile from being read.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authStateProvider).asData?.value;
    final isCurrentUser = currentUser?.uid == userId;
    final profile = ref
        .watch(directFriendProfileProvider(userId))
        .asData
        ?.value;
    final entries =
        ref.watch(friendLeaderboardProvider).asData?.value ??
        const <FriendLeaderboardEntry>[];
    FriendLeaderboardEntry? entry;
    for (final candidate in entries) {
      if (candidate.userId == userId) {
        entry = candidate;
        break;
      }
    }
    final rankTheme = RankColorTheme.forRank(entry?.rank);
    final localSteps = ref.watch(dailyStepsProvider).asData?.value;
    final steps = isCurrentUser ? localSteps?.steps : entry?.steps;
    final name =
        profile?['displayName'] as String? ??
        entry?.displayName ??
        'StepCircle member';
    final photoUrl = profile?['photoUrl'] as String? ?? entry?.photoUrl;
    final city = profile?['city'] as String?;
    final countryCode = profile?['countryCode'] as String?;
    final showCity = profile?['showCityOnGlobalLeaderboard'] as bool? ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(isCurrentUser ? 'My dashboard' : 'Friend dashboard'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Center(
            child: CircleAvatar(
              radius: 42,
              backgroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
              child: photoUrl == null
                  ? const Icon(Icons.person, size: 40)
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          if (showCity && city != null && countryCode != null) ...[
            const SizedBox(height: 4),
            Text(
              '$city · ${_countryFlag(countryCode)}',
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    steps?.toString() ?? '—',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text('Steps today'),
                  if (entry?.updatedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Last synced ${_relativeTime(entry!.updatedAt!.toDate())}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: rankTheme.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      entry == null
                          ? 'No direct-friends rank yet'
                          : '${rankTheme.label} · Rank #${entry.rank} of ${entries.length}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: rankTheme.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (isCurrentUser)
            const _MyActivitySection()
          else
            _GroupRankHistorySection(userId: userId),
          const SizedBox(height: 20),
          Text(
            'Your direct-friends comparison',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          _GroupStatusLeaderboard(
            entries: entries,
            currentUserId: currentUser?.uid,
          ),
        ],
      ),
    );
  }
}

class _MyActivitySection extends ConsumerWidget {
  const _MyActivitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(activityHistoryProvider(30));
    final goal = ref.watch(dailyGoalProvider).asData?.value ?? 10000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Personal progress',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        history.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (_, _) => const _PersonalHistoryUnavailable(),
          data: (days) => days.isEmpty
              ? const _PersonalHistoryUnavailable()
              : _PersonalProgress(history: days, goal: goal),
        ),
      ],
    );
  }
}

class _PersonalProgress extends StatelessWidget {
  const _PersonalProgress({required this.history, required this.goal});
  final List<ActivityDay> history;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final recent = history.length > 7
        ? history.sublist(history.length - 7)
        : history;
    final total = recent.fold<int>(0, (sum, day) => sum + (day.steps ?? 0));
    final streak = currentStreak(history, goal);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last 7 days', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            SizedBox(height: 160, child: _StepsLineChart(history: recent)),
            const SizedBox(height: 12),
            Text('$total steps this week'),
            if (streak >= 3 ||
                recent.any((day) => (day.steps ?? 0) >= 10000)) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  if (streak >= 3) Chip(label: Text('$streak-day streak')),
                  if (recent.any((day) => (day.steps ?? 0) >= 10000))
                    const Chip(label: Text('10K day')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepsLineChart extends StatelessWidget {
  const _StepsLineChart({required this.history});
  final List<ActivityDay> history;

  @override
  Widget build(BuildContext context) {
    final maxSteps = history.fold<int>(
      1,
      (max, day) => (day.steps ?? 0) > max ? day.steps ?? 0 : max,
    );
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: (maxSteps * 1.2).ceilToDouble(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .12),
            ),
            spots: [
              for (var i = 0; i < history.length; i++)
                FlSpot(i.toDouble(), (history[i].steps ?? 0).toDouble()),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupRankHistorySection extends ConsumerWidget {
  const _GroupRankHistorySection({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(groupRankHistoryProvider(userId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Yearly group rank tracker',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        history.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (_, _) => const _GroupHistoryMessage(),
          data: (days) => days.isEmpty
              ? const _GroupHistoryMessage()
              : _GroupRankHeatmap(history: days),
        ),
      ],
    );
  }
}

class _GroupHistoryMessage extends StatelessWidget {
  const _GroupHistoryMessage();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(18),
      child: Text(
        'The first private rank snapshot appears shortly after your local day ends. It is visible only to you and your direct friend.',
      ),
    ),
  );
}

class _GroupRankHeatmap extends StatelessWidget {
  const _GroupRankHeatmap({required this.history});
  final List<GroupRankHistoryDay> history;

  @override
  Widget build(BuildContext context) {
    final byDate = {
      for (final day in history) DateUtils.dateOnly(day.date): day,
    };
    final today = DateUtils.dateOnly(DateTime.now());
    final first = today.subtract(const Duration(days: 364));
    final cells = List.generate(
      365,
      (index) => first.add(Duration(days: index)),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tap a day for its private group rank.'),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(53, (week) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Column(
                      children: List.generate(7, (weekday) {
                        final index = week * 7 + weekday;
                        if (index >= cells.length)
                          return const SizedBox(width: 11, height: 14);
                        final date = cells[index];
                        final item = byDate[date];
                        final rankTheme = RankColorTheme.forRank(item?.rank);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(3),
                            onTap: item == null
                                ? null
                                : () => _showDay(context, item),
                            child: Semantics(
                              label: item == null
                                  ? '${date.day}/${date.month}: no snapshot'
                                  : '${date.day}/${date.month}: ${item.steps} steps, rank ${item.rank} of ${item.totalParticipants}',
                              child: Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: item == null
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest
                                      : rankTheme.background,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDay(BuildContext context, GroupRankHistoryDay day) {
    final theme = RankColorTheme.forRank(day.rank);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${day.date.day}/${day.date.month}/${day.date.year}',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text('${day.steps} steps'),
            Text(
              '${theme.label} — Rank #${day.rank} of ${day.totalParticipants}',
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupStatusLeaderboard extends StatelessWidget {
  const _GroupStatusLeaderboard({
    required this.entries,
    required this.currentUserId,
  });
  final List<FriendLeaderboardEntry> entries;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty)
      return const EmptyStateCard(
        icon: Icons.group_outlined,
        title: 'No direct friends yet',
        message:
            'Create or accept an invitation to begin a private comparison.',
      );
    return Card(
      child: Column(
        children: entries.map((item) {
          final rankTheme = RankColorTheme.forRank(item.rank);
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: rankTheme.background,
              backgroundImage: item.photoUrl == null
                  ? null
                  : NetworkImage(item.photoUrl!),
              child: item.photoUrl == null ? Text('#${item.rank}') : null,
            ),
            title: Text(
              item.userId == currentUserId
                  ? '${item.displayName} (You)'
                  : item.displayName,
            ),
            subtitle: Text('${item.steps} steps'),
            trailing: Text(
              rankTheme.label,
              style: TextStyle(
                color: rankTheme.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PersonalHistoryUnavailable extends StatelessWidget {
  const _PersonalHistoryUnavailable();
  @override
  Widget build(BuildContext context) => const EmptyStateCard(
    icon: Icons.calendar_view_month_outlined,
    title: 'No local history available yet',
    message:
        'Connect Health Connect and allow Steps access to build your private on-device history.',
  );
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes} min ago';
  if (difference.inDays < 1) return '${difference.inHours} hr ago';
  return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
}

String _countryFlag(String code) {
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return code;
  return String.fromCharCodes(code.codeUnits.map((unit) => unit + 127397));
}
