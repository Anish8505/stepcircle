import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthRepository {
  AuthRepository(this._auth);
  final FirebaseAuth _auth;
  Stream<User?> authStateChanges() => _auth.authStateChanges();
  Future<void> signInWithGoogle() async {
    final user = await GoogleSignIn(scopes: ['email']).signIn();
    if (user == null) return;
    final tokens = await user.authentication;
    await _auth.signInWithCredential(
      GoogleAuthProvider.credential(
        accessToken: tokens.accessToken,
        idToken: tokens.idToken,
      ),
    );
  }

  Future<void> signInWithApple() async {
    final rawNonce = _createNonce();
    final nonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );
    await _auth.signInWithCredential(
      OAuthProvider(
        'apple.com',
      ).credential(idToken: apple.identityToken, rawNonce: rawNonce),
    );
  }

  Future<void> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);
  Future<void> createEmailAccount(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);
  Future<void> signOut() => _auth.signOut();
  String _createNonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}
