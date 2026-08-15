import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/providers.dart';
import '../friends_providers.dart';

class FriendsLeaderboardTab extends ConsumerStatefulWidget {
  const FriendsLeaderboardTab({super.key});

  @override
  ConsumerState<FriendsLeaderboardTab> createState() => _FriendsLeaderboardTabState();
}

class _FriendsLeaderboardTabState extends ConsumerState<FriendsLeaderboardTab> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      try {
        await ref.read(functionsRepositoryProvider).refreshFriendsLeaderboard();
      } catch (_) {
        // The Firestore stream continues with its existing cached data.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final leaderboard = ref.watch(friendLeaderboardProvider);
    final directFriendIds =
        ref.watch(directFriendIdsProvider).asData?.value ?? const <String>[];
    final currentUser = ref.watch(authStateProvider).asData?.value;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Friends',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              tooltip: 'Use an invitation code',
              onPressed: () => _showAcceptInvite(context, ref),
              icon: const Icon(Icons.qr_code_2_outlined),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Only direct friends are visible here.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        leaderboard.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, _) => _UnavailableCard(
            onCreateInvite: () => _showCreateInvite(context, ref),
            onAcceptInvite: () => _showAcceptInvite(context, ref),
          ),
          data: (entries) {
            final listedUserIds = entries.map((entry) => entry.userId).toSet();
            final waitingForRanks = directFriendIds.any(
              (friendId) => !listedUserIds.contains(friendId),
            );
            if (entries.isEmpty) {
              if (directFriendIds.isNotEmpty) return const _FriendSyncingCard();
              return _EmptyFriendsCard(
                onCreateInvite: () => _showCreateInvite(context, ref),
                onAcceptInvite: () => _showAcceptInvite(context, ref),
              );
            }
            return Column(
              children: [
                ...entries.map(
                  (entry) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () => context.push('/profile/${entry.userId}'),
                      leading: CircleAvatar(
                        backgroundImage: entry.photoUrl == null
                            ? null
                            : NetworkImage(entry.photoUrl!),
                        child: entry.photoUrl == null
                            ? Text(entry.rank.toString())
                            : null,
                      ),
                      title: Text(
                        entry.userId == currentUser?.uid
                            ? '${entry.displayName} (You)'
                            : entry.displayName,
                      ),
                      subtitle: Text('${entry.steps} steps'),
                      trailing: entry.userId == currentUser?.uid
                          ? Text(
                              '#${entry.rank}',
                              style: Theme.of(context).textTheme.titleMedium,
                            )
                          : PopupMenuButton<_FriendAction>(
                              onSelected: (action) {
                                if (action == _FriendAction.remove) {
                                  _removeFriend(context, ref, entry.userId);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: _FriendAction.remove,
                                  child: Text('Remove friend'),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                if (waitingForRanks) const _FriendSyncingCard(compact: true),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _showCreateInvite(context, ref),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Invite a direct friend'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _showCreateInvite(BuildContext context, WidgetRef ref) async {
    try {
      final code = await ref
          .read(functionsRepositoryProvider)
          .createFriendInvite();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Share invitation code'),
          content: SelectableText(
            code,
            style: Theme.of(
              dialogContext,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await SharePlus.instance.share(
                  ShareParams(
                    text:
                        'Join my private StepCircle friends leaderboard. Open StepCircle, choose Use an invitation code, and enter: $code',
                    subject: 'My StepCircle invitation',
                  ),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share'),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) _showBackendMessage(context, error);
    }
  }

  Future<void> _showAcceptInvite(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Accept an invitation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.none,
          decoration: const InputDecoration(labelText: 'Invitation code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      await ref.read(functionsRepositoryProvider).acceptFriendInvite(code);
    } catch (error) {
      if (context.mounted) _showBackendMessage(context, error);
    }
  }

  Future<void> _removeFriend(
    BuildContext context,
    WidgetRef ref,
    String friendId,
  ) async {
    try {
      await ref.read(functionsRepositoryProvider).removeFriend(friendId);
    } catch (error) {
      if (context.mounted) _showBackendMessage(context, error);
    }
  }

  void _showBackendMessage(BuildContext context, Object error) {
    final message = switch (error) {
      FirebaseFunctionsException(code: 'unavailable') =>
        'Connecting to StepCircle services. Please try again in a moment.',
      FirebaseFunctionsException(code: 'not-found') =>
        'That invitation is invalid, expired, or has already been used.',
      FirebaseFunctionsException(code: 'deadline-exceeded') =>
        'That invitation has expired.',
      FirebaseFunctionsException(:final message?) => message,
      _ =>
        'Could not complete that action. Please check your connection and try again.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EmptyFriendsCard extends StatelessWidget {
  const _EmptyFriendsCard({
    required this.onCreateInvite,
    required this.onAcceptInvite,
  });
  final VoidCallback onCreateInvite;
  final VoidCallback onAcceptInvite;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          const Icon(Icons.group_add_outlined, size: 42),
          const SizedBox(height: 12),
          Text(
            'Add a direct friend',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Share a private invitation code, or accept one from someone you know. Friends-of-friends are never added automatically.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onCreateInvite,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Create invitation'),
          ),
          TextButton(
            onPressed: onAcceptInvite,
            child: const Text('Use an invitation code'),
          ),
        ],
      ),
    ),
  );
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({
    required this.onCreateInvite,
    required this.onAcceptInvite,
  });
  final VoidCallback onCreateInvite;
  final VoidCallback onAcceptInvite;

  @override
  Widget build(BuildContext context) => _EmptyFriendsCard(
    onCreateInvite: onCreateInvite,
    onAcceptInvite: onAcceptInvite,
  );
}

class _FriendSyncingCard extends StatelessWidget {
  const _FriendSyncingCard({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: EdgeInsets.all(compact ? 14 : 22),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              compact
                  ? 'Your new friend is added. Their live rank is updating…'
                  : 'Your new friend is added. Setting up the private live leaderboard…',
            ),
          ),
        ],
      ),
    ),
  );
}

enum _FriendAction { remove }
