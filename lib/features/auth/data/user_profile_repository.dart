import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserProfileRepository {
  UserProfileRepository(this._firestore);
  final FirebaseFirestore _firestore;
  Future<void> createIfMissing(User user) async {
    final reference = _firestore.collection('users').doc(user.uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (snapshot.exists) {
        transaction.update(reference, {
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      transaction.set(reference, {
        'displayName': user.displayName ?? 'StepCircle member',
        'photoUrl': user.photoURL,
        'globalLeaderboardOptIn': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<Map<String, dynamic>?> watchProfile(String userId) =>
      _firestore.collection('users').doc(userId).snapshots().map((snapshot) => snapshot.data());

  Future<void> updateGlobalLeaderboardOptIn({
    required String userId,
    required bool optedIn,
  }) => _firestore.collection('users').doc(userId).update({
    'globalLeaderboardOptIn': optedIn,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> updatePublicCity({
    required String userId,
    required String? city,
    required String? countryCode,
    required bool showCity,
  }) => _firestore.collection('users').doc(userId).update({
    'city': city,
    'countryCode': countryCode,
    'showCityOnGlobalLeaderboard': showCity,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
