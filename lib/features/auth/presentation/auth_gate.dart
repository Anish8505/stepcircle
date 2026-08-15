import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_shell.dart';
import '../../../config/firebase_setup.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../notifications/notification_setup.dart';
import '../providers.dart';
import 'sign_in_page.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseApp = ref.watch(firebaseAppProvider);
    return firebaseApp.when(
      loading: () => const _LoadingPage(),
      error: (error, stackTrace) => _FirebaseSetupPage(error: error.toString()),
      data: (app) {
        if (app == null) return const _FirebaseSetupPage();
        return ref
            .watch(authStateProvider)
            .when(
              loading: () => const _LoadingPage(),
              error: (error, stackTrace) =>
                  _FirebaseSetupPage(error: error.toString()),
              data: (user) => user == null
                  ? const SignInPage()
                  : _ProfileProvisioner(user: user),
            );
      },
    );
  }
}

class _ProfileProvisioner extends ConsumerWidget {
  const _ProfileProvisioner({required this.user});
  final User user;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(profileProvisionProvider(user))
      .when(
        loading: () =>
            const _LoadingPage(label: 'Setting up your StepCircle profile…'),
        error: (error, stackTrace) =>
            _FirebaseSetupPage(error: error.toString()),
        data: (_) {
          ref.watch(notificationSetupProvider(user.uid));
          return const StepCircleShell();
        },
      );
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage({this.label = 'Loading StepCircle…'});
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label),
        ],
      ),
    ),
  );
}

class _FirebaseSetupPage extends StatelessWidget {
  const _FirebaseSetupPage({this.error});
  final String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('StepCircle')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: EmptyStateCard(
        icon: Icons.cloud_outlined,
        title: 'Firebase setup required',
        message: error ?? FirebaseSetup.instructions,
      ),
    ),
  );
}
