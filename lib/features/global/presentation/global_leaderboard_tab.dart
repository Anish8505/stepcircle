import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state_card.dart';
import '../../friends/friends_providers.dart';

const _cloudFeaturesEnabled = bool.fromEnvironment('CLOUD_FEATURES_ENABLED');
const _pageSize = 25;

class GlobalLeaderboardEntry {
  const GlobalLeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.steps,
    required this.rank,
    this.photoUrl,
    this.city,
    this.countryCode,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final int steps;
  final int rank;
  final String? city;
  final String? countryCode;

  factory GlobalLeaderboardEntry.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data()!;
    return GlobalLeaderboardEntry(
      userId: data['userId'] as String? ?? snapshot.id,
      displayName: data['displayName'] as String? ?? 'StepCircle user',
      photoUrl: data['photoUrl'] as String?,
      steps: data['steps'] as int? ?? 0,
      rank: data['rank'] as int? ?? 0,
      city: data['city'] as String?,
      countryCode: data['countryCode'] as String?,
    );
  }
}

class GlobalLeaderboardTab extends StatefulWidget {
  const GlobalLeaderboardTab({super.key});

  @override
  State<GlobalLeaderboardTab> createState() => _GlobalLeaderboardTabState();
}

class _GlobalLeaderboardTabState extends State<GlobalLeaderboardTab> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firstPageSubscription;
  final List<GlobalLeaderboardEntry> _entries = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDocument;
  var _initialLoading = true;
  var _loadingMore = false;
  var _hasMore = true;

  Query<Map<String, dynamic>> get _query => FirebaseFirestore.instance
      .collection('globalLeaderboard')
      .doc(localDateKey())
      .collection('entries')
      .orderBy('rank');

  @override
  void initState() {
    super.initState();
    if (_cloudFeaturesEnabled) _listenToFirstPage();
  }

  void _listenToFirstPage() {
    _firstPageSubscription?.cancel();
    _firstPageSubscription = _query.limit(_pageSize).snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        final firstPage = snapshot.docs.map(GlobalLeaderboardEntry.fromSnapshot).toList();
        final firstIds = firstPage.map((entry) => entry.userId).toSet();
        setState(() {
          _entries
            ..removeWhere((entry) => firstIds.contains(entry.userId) || entry.rank <= _pageSize)
            ..insertAll(0, firstPage);
          _lastDocument = snapshot.docs.isEmpty ? null : snapshot.docs.last;
          _hasMore = snapshot.docs.length == _pageSize;
          _initialLoading = false;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _initialLoading = false);
      },
    );
  }

  Future<void> _loadMore() async {
    final lastDocument = _lastDocument;
    if (_loadingMore || !_hasMore || lastDocument == null) return;
    setState(() => _loadingMore = true);
    try {
      final snapshot = await _query.startAfterDocument(lastDocument).limit(_pageSize).get();
      if (!mounted) return;
      final more = snapshot.docs.map(GlobalLeaderboardEntry.fromSnapshot).toList();
      final existingIds = _entries.map((entry) => entry.userId).toSet();
      setState(() {
        _entries.addAll(more.where((entry) => existingIds.add(entry.userId)));
        _lastDocument = snapshot.docs.isEmpty ? _lastDocument : snapshot.docs.last;
        _hasMore = snapshot.docs.length == _pageSize;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  void dispose() {
    _firstPageSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cloudFeaturesEnabled) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: const [
          Text('Global'),
          SizedBox(height: 24),
          EmptyStateCard(
            icon: Icons.public_outlined,
            title: 'Global rankings are not live yet',
            message: 'They become available after the secure server is enabled.',
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _listenToFirstPage(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('Global', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          const Text('Only members who chose to appear here are shown.'),
          const SizedBox(height: 18),
          if (_initialLoading)
            const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()))
          else if (_entries.isEmpty)
            const EmptyStateCard(
              icon: Icons.public_outlined,
              title: 'No global entries yet',
              message: 'Choose Global privacy in Settings, then sync your steps to appear here.',
            )
          else ...[
            ..._entries.map((entry) => _GlobalRow(entry: entry)),
            if (_hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  child: _loadingMore
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Show more'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _GlobalRow extends StatelessWidget {
  const _GlobalRow({required this.entry});
  final GlobalLeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final location = entry.city == null || entry.countryCode == null
        ? null
        : '${entry.city} · ${_countryFlag(entry.countryCode!)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: entry.photoUrl == null ? null : NetworkImage(entry.photoUrl!),
          child: entry.photoUrl == null ? Text('#${entry.rank}') : null,
        ),
        title: Text(entry.displayName),
        subtitle: location == null ? null : Text(location),
        trailing: Text('${entry.steps}\nsteps', textAlign: TextAlign.right),
      ),
    );
  }
}

String _countryFlag(String code) {
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return code;
  return String.fromCharCodes(code.codeUnits.map((unit) => unit + 127397));
}
