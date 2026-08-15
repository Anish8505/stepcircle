import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:country_state_city_picker/country_state_city_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../../config/firebase_setup.dart';
import '../../auth/providers.dart';
import '../../personal/personal_activity.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).asData?.value;
    final profile = ref.watch(currentProfileProvider);
    final dailyGoal = ref.watch(dailyGoalProvider).asData?.value ?? 10000;
    final darkMode = ref.watch(darkModeProvider).asData?.value ?? false;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Your privacy settings could not be loaded.')),
        data: (data) {
          final globalOptIn = data?['globalLeaderboardOptIn'] as bool? ?? false;
          final city = data?['city'] as String?;
          final countryCode = data?['countryCode'] as String?;
          final showCity = data?['showCityOnGlobalLeaderboard'] as bool? ?? false;
          final cityLabel = city == null || city.isEmpty
              ? 'Not set'
              : '$city${countryCode == null || countryCode.isEmpty ? '' : ' · ${_countryFlag(countryCode)}'}';
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Personal activity', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Daily step goal'),
                  subtitle: Text('$dailyGoal steps'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editGoal(context, ref, dailyGoal),
                ),
              ),
              Card(
                child: SwitchListTile(
                  value: darkMode,
                  onChanged: (value) => ref.read(darkModeProvider.notifier).setEnabled(value),
                  title: const Text('Dark mode'),
                  subtitle: const Text('Saved only on this phone.'),
                ),
              ),
              const SizedBox(height: 24),
              Text('Global privacy', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: SwitchListTile(
                  value: globalOptIn,
                  onChanged: (value) => _save(
                    context,
                    ref.read(userProfileRepositoryProvider).updateGlobalLeaderboardOptIn(
                      userId: user.uid,
                      optedIn: value,
                    ),
                  ),
                  title: const Text('Appear on global leaderboard'),
                  subtitle: const Text('Optional. Your name and steps are not published until secure syncing is enabled.'),
                ),
              ),
              const SizedBox(height: 20),
              Text('Optional public city', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.location_city_outlined),
                  title: const Text('Public city'),
                  subtitle: Text(cityLabel),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editCity(context, ref, user.uid, city, countryCode, showCity),
                ),
              ),
              if (city != null && city.isNotEmpty)
                Card(
                  child: SwitchListTile(
                    value: showCity,
                    onChanged: (value) => _save(
                      context,
                      ref.read(userProfileRepositoryProvider).updatePublicCity(
                        userId: user.uid,
                        city: city,
                        countryCode: countryCode,
                        showCity: value,
                      ),
                    ),
                    title: const Text('Show city if I join Global'),
                    subtitle: const Text('Only your city and country flag can be shown—never your address or live location.'),
                  ),
                ),
              const SizedBox(height: 24),
              Text('My activity', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.insights_outlined),
                  title: const Text('My profile dashboard'),
                  subtitle: const Text('Today’s steps, rank and future history'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/profile/${user.uid}'),
                ),
              ),
              const SizedBox(height: 24),
              Text('Setup status', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Firebase'),
                  subtitle: Text(FirebaseSetup.instructions),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editCity(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String? initialCity,
    String? initialCountryCode,
    bool showCity,
  ) async {
    var selectedCity = '';
    var selectedCountryCode = '';
    final result = await showDialog<_CityResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Set public city'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose your country first, then select state and city. StepCircle stores only city and country code—never your address or live location.'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final enabled = await Geolocator.isLocationServiceEnabled();
                    if (!enabled) return;
                    var permission = await Geolocator.checkPermission();
                    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
                    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
                    final position = await Geolocator.getCurrentPosition();
                    final places = await Geocoding().placemarkFromCoordinates(position.latitude, position.longitude);
                    if (places.isEmpty) return;
                    final place = places.first;
                    setDialogState(() {
                      selectedCity = place.locality?.isNotEmpty == true ? place.locality! : (place.subAdministrativeArea ?? '');
                      selectedCountryCode = place.isoCountryCode ?? '';
                    });
                  },
                  icon: const Icon(Icons.my_location_outlined),
                  label: const Text('Use my current city'),
                ),
                const SizedBox(height: 12),
                SelectState(
                  pickerType: PickerType.material,
                  showSearch: true,
                  countryHint: 'Choose country',
                  stateHint: 'Choose state / province',
                  cityHint: 'Choose city',
                  onCountrySelected: (country) {
                    setDialogState(() {
                      selectedCountryCode = _codeFromFlag(country.emoji ?? '');
                      selectedCity = '';
                    });
                  },
                  onCityChanged: (city) => setDialogState(() => selectedCity = city),
                ),
              ],
            ),
          ),
          actions: [
            if (initialCity != null)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, const _CityResult.remove()),
                child: const Text('Remove'),
              ),
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: selectedCity.isEmpty || selectedCountryCode.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, _CityResult(selectedCity, selectedCountryCode)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (!context.mounted) return;
    _save(
      context,
      ref.read(userProfileRepositoryProvider).updatePublicCity(
        userId: userId,
        city: result.remove ? null : result.city,
        countryCode: result.remove ? null : result.countryCode,
        showCity: result.remove ? false : showCity,
      ),
    );
  }

  Future<void> _editGoal(BuildContext context, WidgetRef ref, int currentGoal) async {
    final controller = TextEditingController(text: currentGoal.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Daily step goal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Steps (1,000–100,000)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || value < 1000 || value > 100000) return;
    await ref.read(dailyGoalProvider.notifier).setGoal(value);
  }

  Future<void> _save(BuildContext context, Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      if (context.mounted) _showMessage(context, 'That setting could not be saved. Please try again.');
    }
  }

  void _showMessage(BuildContext context, String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _CityResult {
  const _CityResult(this.city, this.countryCode) : remove = false;
  const _CityResult.remove() : city = '', countryCode = '', remove = true;
  final String city;
  final String countryCode;
  final bool remove;
}

String _countryFlag(String code) {
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return code;
  return String.fromCharCodes(code.codeUnits.map((unit) => unit + 127397));
}

String _codeFromFlag(String flag) {
  final codePoints = flag.runes.where((rune) => rune >= 127462 && rune <= 127487).toList();
  if (codePoints.length != 2) return '';
  return String.fromCharCodes(codePoints.map((rune) => rune - 127397));
}
