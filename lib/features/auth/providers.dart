import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/firebase_setup.dart';
import '../../firebase_options.dart';
import 'data/auth_repository.dart';
import 'data/user_profile_repository.dart';
import '../friends/data/functions_repository.dart';

final firebaseAppProvider = FutureProvider<FirebaseApp?>(
  (ref) async => FirebaseSetup.isConfigured
      ? Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
      : null,
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(FirebaseAuth.instance),
);
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);
final userProfileRepositoryProvider = Provider<UserProfileRepository>(
  (ref) => UserProfileRepository(FirebaseFirestore.instance),
);
final functionsRepositoryProvider = Provider<FunctionsRepository>(
  (ref) => FunctionsRepository(FirebaseFunctions.instanceFor(region: 'asia-south1')),
);
final profileProvisionProvider = FutureProvider.family<void, User>(
  (ref, user) => ref.watch(userProfileRepositoryProvider).createIfMissing(user),
);
final currentProfileProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = ref.watch(authStateProvider).asData?.value;
  if (user == null) return Stream.value(null);
  return ref.watch(userProfileRepositoryProvider).watchProfile(user.uid);
});
