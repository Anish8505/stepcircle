import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';

/// The callable backend is enabled only after it has been deployed to Firebase.
/// Keeping this false prevents an empty new project from retrying a live query.
const _liveFriendBackend = bool.fromEnvironment('CLOUD_FEATURES_ENABLED');

class FriendLeaderboardEntry {
  const FriendLeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.steps,
    required this.rank,
    this.photoUrl,
    this.updatedAt,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final int steps;
  final int rank;
  final Timestamp? updatedAt;

  factory FriendLeaderboardEntry.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data()!;
    return FriendLeaderboardEntry(
      userId: data['participantUserId'] as String,
      displayName: data['displayName'] as String? ?? 'StepCircle user',
      photoUrl: data['photoUrl'] as String?,
      steps: data['steps'] as int? ?? 0,
      rank: data['rank'] as int? ?? 0,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }
}

/// Profiles are readable only for the signed-in member and their direct
/// friends. Firestore rules enforce that privacy boundary.
final directFriendProfileProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, userId) {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots()
          .map((snapshot) => snapshot.data());
    });

class GroupRankHistoryDay {
  const GroupRankHistoryDay({
    required this.date,
    required this.steps,
    required this.rank,
    required this.totalParticipants,
  });

  final DateTime date;
  final int steps;
  final int rank;
  final int totalParticipants;
}

/// Loads only the selected person's entry from each of the signed-in viewer's
/// immutable direct-friend rank snapshots.
final groupRankHistoryProvider =
    FutureProvider.family<List<GroupRankHistoryDay>, String>((
      ref,
      participantId,
    ) async {
      final user = ref.watch(authStateProvider).asData?.value;
      if (user == null || !_liveFriendBackend) return const [];
      final snapshots = await FirebaseFirestore.instance
          .collection('viewerFriendRankSnapshots')
          .where('viewerUserId', isEqualTo: user.uid)
          .orderBy('dateKey', descending: true)
          .limit(365)
          .get();
      final history = await Future.wait(
        snapshots.docs.map((snapshot) async {
          final entry = await snapshot.reference
              .collection('entries')
              .doc(participantId)
              .get();
          if (!entry.exists) return null;
          final data = entry.data()!;
          final key = data['dateKey'] as String? ?? '';
          if (key.length != 8) return null;
          return GroupRankHistoryDay(
            date: DateTime(
              int.parse(key.substring(0, 4)),
              int.parse(key.substring(4, 6)),
              int.parse(key.substring(6, 8)),
            ),
            steps: data['steps'] as int? ?? 0,
            rank: data['rank'] as int? ?? 0,
            totalParticipants: data['totalParticipants'] as int? ?? 0,
          );
        }),
      );
      return history.whereType<GroupRankHistoryDay>().toList()
        ..sort((a, b) => a.date.compareTo(b.date));
    });

String localDateKey([DateTime? time]) {
  final value = time ?? DateTime.now();
  return '${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}';
}

final friendLeaderboardProvider = StreamProvider<List<FriendLeaderboardEntry>>((
  ref,
) {
  if (!_liveFriendBackend) return Stream.value(const []);
  final user = ref.watch(authStateProvider).asData?.value;
  if (user == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('friendLeaderboards')
      .doc('${user.uid}_${localDateKey()}')
      .collection('entries')
      .orderBy('rank')
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(FriendLeaderboardEntry.fromSnapshot).toList(),
      );
});

/// Arrives immediately after the invitation transaction, before leaderboard
/// ranks have finished being recalculated by the secure backend.
final directFriendIdsProvider = StreamProvider<List<String>>((ref) {
  if (!_liveFriendBackend) return Stream.value(const []);
  final user = ref.watch(authStateProvider).asData?.value;
  if (user == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('userFriends')
      .doc(user.uid)
      .collection('friends')
      .snapshots()
      .map((snapshot) => snapshot.docs.map((document) => document.id).toList());
});
