import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:health/health.dart';
import 'package:workmanager/workmanager.dart';

import 'app/app.dart';
import 'firebase_options.dart';

const _backgroundStepSync = 'stepcircle-background-step-sync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return true;
    final health = Health();
    await health.configure();
    final access = await health.hasPermissions([HealthDataType.STEPS], permissions: [HealthDataAccess.READ]);
    if (access != true) return true;
    final now = DateTime.now();
    final steps = await health.getTotalStepsInInterval(DateTime(now.year, now.month, now.day), now);
    if (steps == null) return true;
    final key = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    await FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('syncDailySteps').call<void>({
      'dateKey': key,
      'steps': steps,
      'timeZoneOffsetMinutes': now.timeZoneOffset.inMinutes,
    });
    return true;
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().initialize(callbackDispatcher);
  Workmanager().registerPeriodicTask(_backgroundStepSync, _backgroundStepSync, frequency: const Duration(minutes: 15));
  runApp(const ProviderScope(child: StepCircleApp()));
}
