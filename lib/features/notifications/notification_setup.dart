import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';

final notificationSetupProvider = FutureProvider.family<void, String>((ref, userId) async {
  final messaging = FirebaseMessaging.instance;
  final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
  if (settings.authorizationStatus != AuthorizationStatus.authorized &&
      settings.authorizationStatus != AuthorizationStatus.provisional) return;
  final repository = ref.read(functionsRepositoryProvider);
  final token = await messaging.getToken();
  if (token != null) await repository.registerNotificationToken(token);
  messaging.onTokenRefresh.listen((nextToken) => repository.registerNotificationToken(nextToken));
});
