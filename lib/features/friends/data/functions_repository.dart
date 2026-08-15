import 'package:cloud_functions/cloud_functions.dart';

class FunctionsRepository {
  FunctionsRepository(this._functions);

  final FirebaseFunctions _functions;

  Future<void> syncDailySteps({required String dateKey, required int steps}) async {
    await _functions.httpsCallable('syncDailySteps').call<void>({
      'dateKey': dateKey,
      'steps': steps,
      'timeZoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
    });
  }

  Future<void> registerNotificationToken(String token) async {
    await _functions.httpsCallable('registerNotificationToken').call<void>({'token': token});
  }

  Future<String> createFriendInvite() async {
    final result = await _functions.httpsCallable('createFriendInvite').call<Map<Object?, Object?>>();
    return result.data['invitationCode']! as String;
  }

  Future<void> acceptFriendInvite(String invitationCode) =>
      _functions.httpsCallable('acceptFriendInvite').call<void>({
        'invitationCode': invitationCode,
        'dateKey': _localDateKey(),
      });

  Future<void> refreshFriendsLeaderboard() =>
      _functions.httpsCallable('refreshFriendsLeaderboard').call<void>({
        'dateKey': _localDateKey(),
      });

  Future<void> declineFriendInvite(String invitationCode) =>
      _functions.httpsCallable('declineFriendInvite').call<void>({
        'invitationCode': invitationCode,
      });

  Future<void> removeFriend(String friendId) =>
      _functions.httpsCallable('removeFriend').call<void>({'friendId': friendId});

  Future<void> updatePublicLocation(String city) =>
      _functions.httpsCallable('updatePublicLocation').call<void>({'city': city});
}

String _localDateKey() {
  final now = DateTime.now();
  return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
}
