# StepCircle

StepCircle is a Flutter mobile app for securely comparing real, permissioned daily step totals with direct friends.

## Current status

The app includes Firebase sign-in, private local step reading through Health Connect on Android, daily goals, dark mode, manual public city selection, a personal 7-day chart, badges, and a private 12-month activity heatmap. While the app is open, it checks Health Connect every 15 seconds and also refreshes when you return to the app. The production UI does not invent step, distance, calorie, or leaderboard data. A clearly labelled preview is available only with `--dart-define=DEMO_MODE=true`.

The secure direct-friend architecture is implemented in `functions/src/index.ts`: invitation codes, deterministic two-way friendships, removal, server-validated step records, and viewer-specific direct-friends leaderboards. It remains disabled until the Cloud Functions backend is deployed. This is intentional: an offline client cannot safely create or share friendships, ranks, or another person's health totals. Global rankings, notifications, and historical group-rank snapshots likewise require that backend.

## Run the app

1. Open this `step_circle` folder in Android Studio.
2. Select an Android emulator or connected phone, then press Run.
3. Or run `flutter pub get`, followed by `flutter run`.

### Android health setup

Install **Health Connect** from Google Play if your phone does not already include it. Open StepCircle and tap **Connect** on the Today screen, then grant Android activity recognition and Health Connect read access for steps. The app reads today's total only after access is granted.

### iOS health setup

On macOS, open the iOS project in Xcode and enable the **HealthKit** capability for the Runner target. The required usage descriptions are already included in `Info.plist`.

## Firebase setup

Firebase is configured for the project. Enable the sign-in providers you want in Firebase Authentication and run `flutter run`.

The Firestore rules allow each signed-in person to access only their own private data and safe direct-friend profiles. Clients cannot write ranks, friendship records, or raw step records. Those actions are reserved for the secure backend.

## Planned data model and security

The backend will use deterministic `friendships/{smallerUserId_largerUserId}` records, per-user `userFriends`, validated daily-step documents, viewer-specific friend leaderboards, and opt-in global leaderboard snapshots. Cloud Functions will validate every sync and calculate ranks. Clients will never write rank documents, friendship records, or another person's steps. Global leaderboard documents will be written only for users with explicit opt-in.
