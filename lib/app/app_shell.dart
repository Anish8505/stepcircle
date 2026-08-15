import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/friends/presentation/friends_leaderboard_tab.dart';
import '../features/global/presentation/global_leaderboard_tab.dart';
import '../features/steps/presentation/my_steps_tab.dart';

final selectedTabProvider = NotifierProvider<SelectedTab, int>(SelectedTab.new);

class SelectedTab extends Notifier<int> {
  @override
  int build() => 0;
  void select(int index) => state = index;
}

class StepCircleShell extends ConsumerWidget {
  const StepCircleShell({super.key});
  static const _tabs = [
    MyStepsTab(),
    FriendsLeaderboardTab(),
    GlobalLeaderboardTab(),
  ];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTab = ref.watch(selectedTabProvider);
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: selectedTab, children: _tabs),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) =>
            ref.read(selectedTabProvider.notifier).select(index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.directions_walk_outlined),
            selectedIcon: Icon(Icons.directions_walk),
            label: 'My Steps',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Friends',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: 'Global',
          ),
        ],
      ),
    );
  }
}
