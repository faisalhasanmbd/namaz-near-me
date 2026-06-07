import 'dart:async';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/cities.dart';
import 'data/sample_mosques.dart';
import 'utils/mosque_utils.dart';
import 'models/daily_islamic_timings.dart';
import 'models/mosque.dart';
import 'services/islamic_timing_service.dart';
import 'services/city_seeder_service.dart';
import 'services/city_service.dart';
import 'services/jamaat_sorter.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'screens/suggest_edit_screen.dart';
import 'screens/voice_assistant_screen.dart';
import 'screens/contributor_signup_screen.dart';
import 'screens/rewards_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';

// ── Eid detection ────────────────────────────────────────────────────────────
enum EidType { none, eidUlFitr, eidUlAdha }

class EidWindow {
  const EidWindow({required this.type, required this.daysUntilEid});
  final EidType type;
  final int daysUntilEid;
  bool get isEidDay => daysUntilEid == 0;
  bool get isBeforeEid => daysUntilEid > 0;
}

// hijriAdjustment: admin-confirmed day offset (-2..+2) for the city.
// Applying it here ensures Eid windows align with the confirmed Hijri date.
EidWindow getEidWindowStatus(DateTime date, {int hijriAdjustment = 0}) {
  final adjustedDate = date.add(Duration(days: hijriAdjustment));
  final h = IslamicTimingService.hijriMonthDay(adjustedDate);
  // Eid ul Fitr = 1 Shawwal (month 10), show from 27 Ramadan (3 days before)
  if (h[0] == 9 && h[1] >= 27) {
    return EidWindow(type: EidType.eidUlFitr, daysUntilEid: 30 - h[1]);
  }
  if (h[0] == 10 && h[1] <= 3) {
    return EidWindow(type: EidType.eidUlFitr, daysUntilEid: 1 - h[1]);
  }
  // Eid ul Adha = 10 Dhu al-Hijjah (month 12), show from 7th (3 days before)
  if (h[0] == 12 && h[1] >= 7 && h[1] <= 13) {
    return EidWindow(type: EidType.eidUlAdha, daysUntilEid: 10 - h[1]);
  }
  return const EidWindow(type: EidType.none, daysUntilEid: 999);
}

// ─────────────────────────────────────────────────────────────────────────────

final ValueNotifier<Locale?> appLocaleNotifier = ValueNotifier<Locale?>(null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestProvider(),
    );
  } catch (error) {
    debugPrint('Firebase unavailable at startup: $error');
  }
  // Sign in anonymously so the OSM seeder and read-only flows have a valid
  // auth token. Phone OTP verification will replace this session.
  if (FirebaseAuth.instance.currentUser == null) {
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {}
  }
  final appState = AppState();
  await appState.init();
  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const NamazNearMeApp(),
    ),
  );
}

class NamazNearMeApp extends StatefulWidget {
  const NamazNearMeApp({super.key});

  @override
  State<NamazNearMeApp> createState() => _NamazNearMeAppState();
}

class _NamazNearMeAppState extends State<NamazNearMeApp> {
  @override
  void initState() {
    super.initState();
    appLocaleNotifier.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    appLocaleNotifier.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Namaz Near Me',
      debugShowCheckedModeBanner: false,
      scrollBehavior:
          const MaterialScrollBehavior().copyWith(overscroll: false),
      locale: appLocaleNotifier.value,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('ur'),
        Locale('ar'),
        Locale('id'),
        Locale('tr'),
        Locale('fr'),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F7C68),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const NearbyMosquesScreen(),
    );
  }
}

class NearbyMosquesScreen extends StatefulWidget {
  const NearbyMosquesScreen({super.key});

  @override
  State<NearbyMosquesScreen> createState() => _NearbyMosquesScreenState();
}

class _NearbyMosquesScreenState extends State<NearbyMosquesScreen>
    with WidgetsBindingObserver {
  String _selectedNamaz = 'all';
  int _radiusKm = 2;
  UserLocation _location = LocationService.moradabadCenter;
  bool _loadingLocation = true;
  CityInfo _selectedCity = indianCities.first;
  late Stream<List<Mosque>> _mosquesStream;
  bool _showFavouritesOnly = false;
  String? _hijriDateOverride;
  int _hijriAdjustment = 0;
  bool _hijriMonthConfirmed = false;
  String? _hijriVerifiedBy;
  bool _canAdjustHijri = false;
  Timer? _dateTicker;
  String? _lastHijriLookupKey;
  String? _lastEnglishDateKey;
  String? _focusedMosqueKey;
  int _asrShadowFactor = 2;
  bool _cityManuallySelected = false;
  bool _locationPermissionDeniedForever = false;
  bool _isSeedingMosques = false;

  Stream<List<Mosque>> _watchMosques(CityInfo city) async* {
    final cityName = city.name;
    final useSampleFallback = cityName.toLowerCase().trim() == 'moradabad';
    if (Firebase.apps.isEmpty) {
      yield useSampleFallback ? sampleMosques : const <Mosque>[];
      return;
    }
    while (true) {
      try {
        final snapshots = FirebaseFirestore.instance
            .collection('mosques')
            .where('city', isEqualTo: cityName)
            .snapshots()
            .map((snapshot) {
          final result = <String, Mosque>{};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final name = _readString(data['name']);
            if (name == null) continue;
            final key = mosqueKey(name);
            if (_readBool(data['deleted']) || data['status'] == 'deleted') {
              result.remove(key);
              continue;
            }
            result[key] = _mosqueFromFirestore(
              data,
              result[key],
              docId: doc.id,
            );
          }
          return result.values.toList();
        });
        await for (final liveMosques in snapshots) {
          if (liveMosques.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isSeedingMosques = true);
            });
            CitySeederService.instance.seedIfNeeded(city);
            yield useSampleFallback ? sampleMosques : const <Mosque>[];
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _isSeedingMosques) {
                setState(() => _isSeedingMosques = false);
              }
            });
            yield liveMosques;
          }
        }
        return;
      } catch (e) {
        debugPrint('Firestore error, retrying in 5s: $e');
        yield useSampleFallback ? sampleMosques : const <Mosque>[];
        await Future.delayed(const Duration(seconds: 5));
      }
    }
  }

  bool _openedExternalSettings = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedExternalSettings) {
      _openedExternalSettings = false;
      _loadLocation();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mosquesStream = _watchMosques(_selectedCity);
    CityService.instance.load().then((_) {
      if (!mounted) return;
      final savedName = context.read<AppState>().selectedCity;
      final matches = CityService.instance.all
          .where((c) => c.name.toLowerCase() == savedName.toLowerCase());
      if (matches.isNotEmpty && matches.first.name != _selectedCity.name) {
        final city = matches.first;
        setState(() {
          _cityManuallySelected = true;
          _selectedCity = city;
          _location = UserLocation(
            latitude: city.latitude,
            longitude: city.longitude,
            isCurrentLocation: false,
          );
          _mosquesStream = _watchMosques(city);
        });
      } else {
        setState(() {});
      }
    });
    _loadLocation();
    _loadHijriDate();
    _loadHijriAdjustmentPermission();
    _startDateTicker();
    _loadAsrMethod();
  }

  Future<void> _loadAsrMethod() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('asr_shadow_factor');
    if (saved != null && mounted) setState(() => _asrShadowFactor = saved);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dateTicker?.cancel();
    super.dispose();
  }

  Future<void> _backfillMyContributorScore() async {
    // Score is managed exclusively by Cloud Functions.
    // This method only syncs the display name so the leaderboard shows a
    // real name instead of the "Namaz Volunteer" placeholder.
    // Skip for anonymous users — top_contributors requires phone verification.
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      if (uid == null || user!.isAnonymous) return;
      final cityName = _selectedCity.name;
      await FirebaseFirestore.instance
          .collection('top_contributors')
          .doc(cityContributorDocId(cityName, uid))
          .set({
        'name':
            _cleanContributorNameOrNull(user?.displayName) ?? 'Namaz Volunteer',
        'uid': uid,
        'city': cityName,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Contributor display sync skipped: $error');
    }
  }

  Future<void> _openAsrMethodSelector(BuildContext context) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Hanafi (Asr later)'),
              trailing: _asrShadowFactor == 2 ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(2),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Shafi (Asr earlier)'),
              trailing: _asrShadowFactor == 1 ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(1),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    if (!mounted) return;
    setState(() => _asrShadowFactor = selected);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('asr_shadow_factor', selected);
  }

  Future<void> _toggleFavourite(String key) async {
    await context.read<AppState>().toggleFavourite(key);
    if (mounted) setState(() {});
  }

  // Uses firestoreDocId (city-name-area kebab key) as the stable unique key.
  // placeId is first choice (OSM), firestoreDocId is second (Firestore-keyed),
  // fallback combines name+area+city to avoid collisions on duplicate names.
  String _mosqueUniqueKey(Mosque m) =>
      m.placeId ??
      m.firestoreDocId ??
      mosqueKey('${m.name}_${m.area}_${m.city ?? ''}');

  Future<void> _loadHijriDate() async {
    var adjustment = 0;
    String? confirmedMonth;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('islamic_date_city')
          .doc(cityDateKey(_selectedCity.name))
          .get();
      final data = doc.data();
      adjustment = (data?['adjustment'] as num?)?.toInt() ?? 0;
      confirmedMonth = data?['confirmed_hijri_month'] as String?;
    } catch (_) {}
    final service = IslamicTimingService(
      latitude: _selectedCity.latitude,
      longitude: _selectedCity.longitude,
      asrShadowFactor: _asrShadowFactor,
    );
    final lookupDate = service.hijriDateFor(DateTime.now());
    final hijriDate = await IslamicTimingService.fetchHijriDateIndia(
      date: lookupDate,
      dayAdjustment: adjustment,
    );
    if (!mounted || hijriDate == null) return;
    setState(() {
      _hijriDateOverride = hijriDate;
      _hijriAdjustment = adjustment;
      _hijriMonthConfirmed =
          confirmedMonth != null && confirmedMonth == _hijriMonthKey(hijriDate);
      _lastHijriLookupKey = dateKey(lookupDate);
      _lastEnglishDateKey = dateKey(DateTime.now());
    });
  }

  void _startDateTicker() {
    _lastEnglishDateKey = dateKey(DateTime.now());
    _lastHijriLookupKey = dateKey(
      IslamicTimingService(
        latitude: _selectedCity.latitude,
        longitude: _selectedCity.longitude,
        asrShadowFactor: _asrShadowFactor,
      ).hijriDateFor(DateTime.now()),
    );
    _dateTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final englishKey = dateKey(now);
      final hijriLookupKey = dateKey(
        IslamicTimingService(
          latitude: _selectedCity.latitude,
          longitude: _selectedCity.longitude,
          asrShadowFactor: _asrShadowFactor,
        ).hijriDateFor(now),
      );
      if (englishKey != _lastEnglishDateKey ||
          hijriLookupKey != _lastHijriLookupKey) {
        _lastEnglishDateKey = englishKey;
        _lastHijriLookupKey = hijriLookupKey;
        _loadHijriDate();
        setState(() {});
      }
    });
  }

  Future<void> _loadLocation() async {
    final appState = context.read<AppState>();
    final permission = await Geolocator.checkPermission();

    // Permission was permanently denied — cannot re-prompt.
    // Fall back to selected city center and show settings link.
    if (permission == LocationPermission.deniedForever && mounted) {
      setState(() {
        _loadingLocation = false;
        _locationPermissionDeniedForever = true;
        // Use the currently selected city's center, not a hardcoded coordinate
        _location = UserLocation(
          latitude: _selectedCity.latitude,
          longitude: _selectedCity.longitude,
          isCurrentLocation: false,
        );
      });
      return;
    }

    if (permission == LocationPermission.denied && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Allow location access'),
          content: const Text(
            'Namaz Near Me uses your location to show nearby mosques. '
            'Your location is never stored or shared.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Use city center'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        if (mounted) {
          setState(() {
            _loadingLocation = false;
            // Still use selected city center, not hardcoded Moradabad
            _location = UserLocation(
              latitude: _selectedCity.latitude,
              longitude: _selectedCity.longitude,
              isCurrentLocation: false,
            );
          });
        }
        return;
      }
    }

    // If GPS (location service) is off, prompt user to enable it
    final gpsEnabled = await LocationService().isLocationServiceEnabled();
    if (!gpsEnabled && mounted) {
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Location (GPS) is off'),
          content: const Text(
            'Please turn on your device location (GPS) so we can show mosques near you.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (openSettings == true) {
        _openedExternalSettings = true;
        await LocationService().openLocationSettings();
        return; // location will refresh via didChangeAppLifecycleState on resume
      }
    }

    final rawLocation = await LocationService().currentOrFallback();
    // If GPS was not available, use the selected city's center rather than
    // the hardcoded Moradabad fallback in LocationService.
    final location = rawLocation.isCurrentLocation
        ? rawLocation
        : UserLocation(
            latitude: _selectedCity.latitude,
            longitude: _selectedCity.longitude,
            isCurrentLocation: false,
          );

    final nearestCity = _nearestCityForLocation(location);
    if (!mounted) return;
    if (_cityManuallySelected) {
      setState(() => _loadingLocation = false);
      return;
    }
    setState(() {
      _location = location;
      _selectedCity = nearestCity;
      _loadingLocation = false;
      _locationPermissionDeniedForever = false;
      _mosquesStream = _watchMosques(nearestCity);
    });
    appState.setCity(nearestCity.name);
    _lastHijriLookupKey = null;
    _loadHijriDate();
  }

  Future<void> _openSearch(BuildContext context) async {
    final allResults = _lastResults;
    final selected = await showSearch<MosqueResult?>(
      context: context,
      delegate: _MosqueSearchDelegate(results: allResults),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _showFavouritesOnly = false;
      _focusedMosqueKey = _focusKeyForMosque(selected.mosque);
    });
  }

  String _focusKeyForMosque(Mosque mosque) {
    final placeId = mosque.placeId?.trim();
    if (placeId != null && placeId.isNotEmpty) return 'pid:$placeId';
    final city = (mosque.city ?? '').toLowerCase().trim();
    final area = mosque.area.toLowerCase().trim();
    final name = mosque.name.toLowerCase().trim();
    return 'name:$name|area:$area|city:$city';
  }

  CityInfo _nearestCityForLocation(UserLocation location) {
    var nearest = indianCities.first;
    var bestDistance = double.infinity;
    for (final city in indianCities) {
      final dLat = city.latitude - location.latitude;
      final dLng = city.longitude - location.longitude;
      final score = (dLat * dLat) + (dLng * dLng);
      if (score < bestDistance) {
        bestDistance = score;
        nearest = city;
      }
    }
    return nearest;
  }

  Future<void> _openCitySelector(BuildContext context) async {
    final appState = context.read<AppState>();
    final selected = await showModalBottomSheet<CityInfo>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CitySearchSheet(selectedCity: _selectedCity),
    );
    if (selected != null && mounted) {
      setState(() {
        _cityManuallySelected = true;
        _selectedCity = selected;
        _location = UserLocation(
          latitude: selected.latitude,
          longitude: selected.longitude,
          isCurrentLocation: false,
        );
        _loadingLocation = false;
        _mosquesStream = _watchMosques(selected);
      });
      appState.setCity(selected.name);
      _lastHijriLookupKey = null;
      _loadHijriDate();
    }
  }

  Future<void> _confirmHijriAdjustment(int adjustment) async {
    final phone = context.read<AppState>().verifiedPhone;
    if (phone == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please verify your number first via Suggest Edit.'),
          ),
        );
      }
      return;
    }
    final lookupDate = IslamicTimingService(
      latitude: _selectedCity.latitude,
      longitude: _selectedCity.longitude,
      asrShadowFactor: _asrShadowFactor,
    ).hijriDateFor(DateTime.now());
    final correctedHijri = await IslamicTimingService.fetchHijriDateIndia(
      date: lookupDate,
      dayAdjustment: adjustment,
    );
    if (correctedHijri == null) return;
    final monthKey = _hijriMonthKey(correctedHijri);
    if (monthKey == null) return;
    await FirebaseFirestore.instance
        .collection('islamic_date_city')
        .doc(cityDateKey(_selectedCity.name))
        .set({
      'city': _selectedCity.name,
      'adjustment': adjustment,
      'confirmed_hijri_month': monthKey,
      'confirmed_hijri_date': correctedHijri,
      'verified_by_phone': phone,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!mounted) return;
    setState(() {
      _hijriDateOverride = correctedHijri;
      _hijriAdjustment = adjustment;
      _hijriMonthConfirmed = true;
    });
  }

  Future<void> _loadHijriAdjustmentPermission() async {
    User? user;
    try {
      user = FirebaseAuth.instance.currentUser;
    } catch (_) {
      return; // Firebase not initialized (e.g., in tests)
    }
    if (user == null) {
      if (mounted) setState(() => _canAdjustHijri = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('admin_users')
          .doc(user.uid)
          .get();
      if (mounted) {
        setState(() =>
            _canAdjustHijri = snap.exists && snap.data()?['is_admin'] == true);
      }
    } catch (_) {
      if (mounted) setState(() => _canAdjustHijri = false);
    }
  }

  Future<void> _openContributorScreen(BuildContext context) async {
    await _backfillMyContributorScore();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContributorSignupScreen(
          cityName: _selectedCity.name,
          mosques: _lastVisibleMosques,
        ),
      ),
    );
  }

  List<MosqueResult> _lastResults = [];
  List<Mosque> _lastVisibleMosques = [];

  @override
  Widget build(BuildContext context) {
    final useCompactActions = MediaQuery.sizeOf(context).width < 430;
    final islamicTimingService = IslamicTimingService(
      latitude: _selectedCity.latitude,
      longitude: _selectedCity.longitude,
      asrShadowFactor: _asrShadowFactor,
    );
    final dailyTimings = islamicTimingService.today(
      hijriDateOverride: _hijriDateOverride,
    );
    final autoMaghribJamaat = islamicTimingService.maghribJamaatTime();

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 40,
        titleSpacing: 4,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
          child: Image.asset(
            'assets/images/namaz-near-me-icon.png',
            fit: BoxFit.contain,
          ),
        ),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Namaz Near Me',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search mosque',
            onPressed: () => _openSearch(context),
          ),
          IconButton(
            icon: const Icon(Icons.mic_rounded),
            tooltip: 'Voice Assistant',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VoiceAssistantScreen(
                  mosques: _lastVisibleMosques,
                  userLocation: _location,
                  cityName: _selectedCity.name,
                  radiusKm: _radiusKm.toDouble(),
                ),
              ),
            ),
          ),
          if (useCompactActions)
            IconButton(
              tooltip: 'Change city: ${_selectedCity.name}',
              onPressed: () => _openCitySelector(context),
              icon: const Icon(Icons.location_city),
            )
          else
            TextButton.icon(
              onPressed: () => _openCitySelector(context),
              icon: const Icon(Icons.location_city),
              label: Text(_selectedCity.name, overflow: TextOverflow.ellipsis),
            ),
          IconButton(
            tooltip: 'Asr Method',
            icon: const Icon(Icons.schedule),
            onPressed: () => _openAsrMethodSelector(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openContributorScreen(context),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Add / Update Mosque'),
      ),
      body: SafeArea(
        child: StreamBuilder<List<Mosque>>(
          stream: _mosquesStream,
          initialData: const [],
          builder: (context, snapshot) {
            final appState = context.watch<AppState>();
            final selectedCityName = _selectedCity.name;
            final mosques = (snapshot.data ?? [])
                .where((mosque) => sameCity(mosque.city, selectedCityName))
                .toList();
            final mosquesWithAutoMaghrib = mosques
                .map(
                  (mosque) =>
                      _withAutoCalendarMaghrib(mosque, autoMaghribJamaat),
                )
                .toList();
            final mosquesWithDistance = LocationService().applyDistances(
              mosquesWithAutoMaghrib,
              _location,
            );
            final visibleMosques = mosquesWithDistance
                .where(
                  (m) =>
                      m.distanceMeters <= _radiusKm * 1000 || !m.hasCoordinates,
                )
                .toList();
            final filteredMosques = _showFavouritesOnly
                ? visibleMosques
                    .where((m) => appState.isFavourite(_mosqueUniqueKey(m)))
                    .toList()
                : visibleMosques;
            final sortedResults = sortMosquesForUser(
              filteredMosques,
              now: DateTime.now(),
              namazFilter: _selectedNamaz,
            );
            _lastResults = sortedResults;
            _lastVisibleMosques = filteredMosques;
            final focusedResults = _focusedMosqueKey == null
                ? sortedResults
                : sortedResults
                    .where(
                      (result) =>
                          _focusKeyForMosque(result.mosque) ==
                          _focusedMosqueKey,
                    )
                    .toList();
            final duplicateGroups = _findDuplicateGroups(
              focusedResults.map((r) => r.mosque).toList(),
            );

            return RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _mosquesStream = _watchMosques(_selectedCity);
                });
                await Future.delayed(const Duration(milliseconds: 800));
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
                children: [
                  _DailyIslamicTimingPanel(
                    timings: dailyTimings,
                    cityName: _selectedCity.name,
                    adjustment: _hijriAdjustment,
                    monthConfirmed: _hijriMonthConfirmed,
                    verifiedBy: _hijriVerifiedBy,
                    canAdjustHijri: _canAdjustHijri,
                    onConfirmAdjustment: _confirmHijriAdjustment,
                  ),
                  const SizedBox(height: 16),
                  _LocationPanel(
                    radiusKm: _radiusKm,
                    loadingLocation: _loadingLocation,
                    isCurrentLocation: _location.isCurrentLocation,
                    permissionDeniedForever: _locationPermissionDeniedForever,
                    onRefreshLocation: _loadLocation,
                    onRadiusChanged: (value) =>
                        setState(() => _radiusKm = value),
                    cityName: _selectedCity.name,
                  ),
                  const SizedBox(height: 16),
                  _NamazFilter(
                    selectedNamaz: _selectedNamaz,
                    onSelected: (value) =>
                        setState(() => _selectedNamaz = value),
                  ),
                  const SizedBox(height: 16),
                  _RewardsPreviewCard(
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RewardsScreen(
                          cityName: _selectedCity.name,
                          onBackfill: _backfillMyContributorScore,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (snapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.wifi_off_rounded,
                              color: Colors.orange.shade700,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Live updates paused — check internet connection.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_focusedMosqueKey != null) ...[
                    _FocusedMosqueBanner(
                      mosqueName: focusedResults.isNotEmpty
                          ? focusedResults.first.mosque.name
                          : 'Selected mosque',
                      onViewAll: () => setState(() => _focusedMosqueKey = null),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (focusedResults.isEmpty)
                    _isSeedingMosques && !_showFavouritesOnly
                        ? _SeedingState(cityName: _selectedCity.name)
                        : _EmptyState(
                            message: _showFavouritesOnly
                                ? 'No favourite mosques saved.\nTap ★ on a mosque to add it.'
                                : 'No mosques found within ${_radiusKm}km of ${_selectedCity.name}.',
                            onViewAll: _showFavouritesOnly
                                ? () => setState(() {
                                      _showFavouritesOnly = false;
                                      _focusedMosqueKey = null;
                                    })
                                : null,
                            onWidenRadius:
                                !_showFavouritesOnly && _radiusKm < 20
                                    ? () => setState(
                                          () => _radiusKm =
                                              (_radiusKm + 2).clamp(2, 20),
                                        )
                                    : null,
                            onAddMosque: !_showFavouritesOnly
                                ? () => _openContributorScreen(context)
                                : null,
                          )
                  else ...[
                    // Pinned mosque always first
                    for (final result in [
                      ...focusedResults.where(
                          (r) => appState.isPinned(_mosqueUniqueKey(r.mosque))),
                      ...focusedResults.where((r) =>
                          !appState.isPinned(_mosqueUniqueKey(r.mosque))),
                    ]) ...[
                      _MosqueCard(
                        result: result,
                        cityName: _selectedCity.name,
                        isFavourite: appState
                            .isFavourite(_mosqueUniqueKey(result.mosque)),
                        onToggleFavourite: () =>
                            _toggleFavourite(_mosqueUniqueKey(result.mosque)),
                        isPinned:
                            appState.isPinned(_mosqueUniqueKey(result.mosque)),
                        onTogglePin: () {
                          final key = _mosqueUniqueKey(result.mosque);
                          appState.setPinnedMosque(
                              appState.isPinned(key) ? null : key);
                        },
                        hijriAdjustment: _hijriAdjustment,
                        duplicates: result.mosque.firestoreDocId != null
                            ? (duplicateGroups[result.mosque.firestoreDocId] ??
                                [])
                            : [],
                        onContribute: () => _openContributorScreen(context),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_showFavouritesOnly)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: () => setState(() {
                              _showFavouritesOnly = false;
                              _focusedMosqueKey = null;
                            }),
                            icon: const Icon(Icons.mosque_outlined),
                            label: const Text('View all mosques'),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FocusedMosqueBanner extends StatelessWidget {
  const _FocusedMosqueBanner({
    required this.mosqueName,
    required this.onViewAll,
  });

  final String mosqueName;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Color(0xFF0F7C68), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mosqueName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(onPressed: onViewAll, child: const Text('View all')),
        ],
      ),
    );
  }
}

class _DailyIslamicTimingPanel extends StatefulWidget {
  const _DailyIslamicTimingPanel({
    required this.timings,
    required this.cityName,
    required this.adjustment,
    required this.monthConfirmed,
    required this.verifiedBy,
    required this.onConfirmAdjustment,
    this.canAdjustHijri = false,
  });
  final DailyIslamicTimings timings;
  final String cityName;
  final int adjustment;
  final bool monthConfirmed;
  final String? verifiedBy;
  final Future<void> Function(int adjustment) onConfirmAdjustment;
  final bool canAdjustHijri;

  @override
  State<_DailyIslamicTimingPanel> createState() =>
      _DailyIslamicTimingPanelState();
}

class _DailyIslamicTimingPanelState extends State<_DailyIslamicTimingPanel> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _submitting = false;
  int _page = 0;
  static const int _pillsPerPage = 3;
  static const double _pillWidth = 88;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  int get _totalPages => (widget.timings.entries.length / _pillsPerPage).ceil();

  void _scrollTo(int dir) {
    final newPage = (_page + dir).clamp(0, _totalPages - 1);
    if (newPage == _page) return;
    setState(() => _page = newPage);
    _scrollCtrl.animateTo(
      newPage * _pillsPerPage * _pillWidth,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _submitOffset(int offset) async {
    setState(() => _submitting = true);
    try {
      await widget.onConfirmAdjustment(offset);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update. Check internet.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedHijri = widget.timings.hijriDate;
    final hijriDay = _hijriDay(displayedHijri);
    final canCorrect = widget.canAdjustHijri &&
        !widget.monthConfirmed &&
        (hijriDay == 29 || hijriDay == 30 || hijriDay == 1);
    final entries = widget.timings.entries;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F7C68),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.cityName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.timings.weekday}  ·  $displayedHijri  ·  ${widget.timings.englishDate}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Verified badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.monthConfirmed ? '✓ Verified' : 'Aladhan',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),

          // ── Hijri date correction (admin only, near month end) ──
          if (canCorrect)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  const Text(
                    'Moon date:',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const Spacer(),
                  _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          children: [
                            _adjBtn(
                              '-1 day',
                              () => _submitOffset(widget.adjustment - 1),
                            ),
                            const SizedBox(width: 4),
                            _adjBtn(
                              'Correct',
                              () => _submitOffset(widget.adjustment),
                              highlight: true,
                            ),
                            const SizedBox(width: 4),
                            _adjBtn(
                              '+1 day',
                              () => _submitOffset(widget.adjustment + 1),
                            ),
                          ],
                        ),
                ],
              ),
            ),

          const SizedBox(height: 10),

          // ── Swipeable pills row ──────────────────────────────
          Row(
            children: [
              // Left arrow
              _ArrowBtn(
                icon: Icons.chevron_left,
                enabled: _page > 0,
                onTap: () => _scrollTo(-1),
              ),

              // Scrollable pills
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: entries.map((entry) {
                      // For ranges like "12:02 PM – 12:11 PM", show as "12:02-12:11"
                      final isRange = entry.time.contains(' – ');
                      final displayLine1 = isRange
                          ? entry.time
                              .replaceAll(' AM', '')
                              .replaceAll(' PM', '')
                              .replaceAll(' – ', '-')
                          : entry.time;
                      return SizedBox(
                        width: _pillWidth,
                        height: 72,
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                entry.label.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 8.5,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                displayLine1,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: isRange ? 10 : 11,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // Right arrow
              _ArrowBtn(
                icon: Icons.chevron_right,
                enabled: _page < _totalPages - 1,
                onTap: () => _scrollTo(1),
              ),
            ],
          ),

          // ── Page dots ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalPages, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == _page ? 14 : 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i == _page
                        ? Colors.white.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _adjBtn(String label, VoidCallback onTap, {bool highlight = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: highlight ? Colors.white : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: highlight ? const Color(0xFF0F7C68) : Colors.white,
          ),
        ),
      ),
    );
  }
}

// ── Arrow button widget ──────────────────────────────────────────
class _ArrowBtn extends StatelessWidget {
  const _ArrowBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: enabled ? 0.2 : 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white.withValues(alpha: enabled ? 0.9 : 0.3),
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _CitySearchSheet extends StatefulWidget {
  const _CitySearchSheet({required this.selectedCity});
  final CityInfo selectedCity;
  @override
  State<_CitySearchSheet> createState() => _CitySearchSheetState();
}

class _CitySearchSheetState extends State<_CitySearchSheet> {
  final _search = TextEditingController();
  List<CityInfo> _filtered = CityService.instance.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    final ql = q.toLowerCase();
    setState(() {
      _filtered = CityService.instance.all
          .where(
            (c) =>
                c.name.toLowerCase().contains(ql) ||
                c.state.toLowerCase().contains(ql) ||
                c.country.toLowerCase().contains(ql),
          )
          .toList();
    });
  }

  Future<void> _openAddCity() async {
    final result = await showModalBottomSheet<CityInfo>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddCitySheet(),
    );
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, sc) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search city, state or country...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: _onSearch,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: sc,
              itemCount: _filtered.length + 1,
              itemBuilder: (context, i) {
                if (i == _filtered.length) {
                  return ListTile(
                    leading: const Icon(
                      Icons.add_location_alt_outlined,
                      color: Color(0xFF0F7C68),
                    ),
                    title: const Text(
                      'Add my city',
                      style: TextStyle(color: Color(0xFF0F7C68)),
                    ),
                    subtitle: const Text(
                      'City not in list? Add it for everyone',
                    ),
                    onTap: _openAddCity,
                  );
                }
                final city = _filtered[i];
                final isSel = city.name == widget.selectedCity.name;
                return ListTile(
                  leading: Icon(
                    isSel ? Icons.location_on : Icons.location_city,
                    color: isSel ? const Color(0xFF0F7C68) : Colors.black45,
                  ),
                  title: Text(
                    city.name,
                    style: TextStyle(
                      fontWeight: isSel ? FontWeight.w800 : FontWeight.normal,
                      color: isSel ? const Color(0xFF0F7C68) : null,
                    ),
                  ),
                  subtitle: Text(
                    city.displayName
                        .replaceFirst(city.name, '')
                        .replaceFirst(', ', ''),
                  ),
                  trailing: isSel
                      ? const Icon(Icons.check, color: Color(0xFF0F7C68))
                      : null,
                  onTap: () => Navigator.of(context).pop(city),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AddCitySheet extends StatefulWidget {
  const _AddCitySheet();
  @override
  State<_AddCitySheet> createState() => _AddCitySheetState();
}

class _AddCitySheetState extends State<_AddCitySheet> {
  final _nameCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(text: 'India');
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _stateCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final state = _stateCtrl.text.trim();
    final country = _countryCtrl.text.trim();
    if (name.isEmpty || country.isEmpty) {
      setState(() => _error = 'City name and country are required.');
      return;
    }
    final phone = context.read<AppState>().verifiedPhone;
    if (phone == null) {
      setState(
        () => _error =
            'Please verify your phone first via Suggest Edit on any mosque.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final location = await LocationService().currentOrFallback();
      await CityService.instance.addCity(
        name: name,
        state: state,
        country: country,
        latitude: location.latitude,
        longitude: location.longitude,
        verifiedPhone: phone,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        CityInfo(
          name: name,
          state: state,
          country: country,
          latitude: location.latitude,
          longitude: location.longitude,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not save. Check internet.';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        24,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Add a new city',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Your current GPS location will be used as the city center.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'City name *',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _stateCtrl,
            decoration: const InputDecoration(
              labelText: 'State / Province',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _countryCtrl,
            decoration: const InputDecoration(
              labelText: 'Country *',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add_location_alt),
            label: Text(_submitting ? 'Saving...' : 'Add City'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}

int? _hijriDay(String? hijriDate) {
  if (hijriDate == null) return null;
  return int.tryParse(hijriDate.split(' ').first);
}

String? _hijriMonthKey(String? hijriDate) {
  if (hijriDate == null) return null;
  final parts = hijriDate.split(' ');
  if (parts.length < 4) return null;
  final year = parts[parts.length - 2];
  final month = parts.sublist(1, parts.length - 2).join(' ');
  return '$month-$year';
}

Mosque _mosqueFromFirestore(
  Map<String, dynamic> data,
  Mosque? existing, {
  String? docId,
}) {
  final timings = _mergeTimings(data['timings'], existing?.timings, data);
  final prayerEditMeta = _readPrayerEditMeta(data['timing_edit_meta']);
  final updatedAt = _readDate(data['timing_updated_at']) ??
      _readDate(data['updated_at']) ??
      existing?.timingUpdatedAt ??
      DateTime(2000);

  if (existing != null) {
    return existing.copyWith(
      city: _readString(data['city']) ?? existing.city,
      area: _readString(data['area']) ?? existing.area,
      address: _readString(data['address']) ?? existing.address,
      timings: timings,
      isVerified: (data['timing_verification_status'] == 'admin_verified' ||
              data['timing_verification_status'] == 'source_verified') ||
          existing.isVerified,
      timingVerificationStatus:
          _readString(data['timing_verification_status']) ??
              existing.timingVerificationStatus,
      timingVerifiedByName: _readString(data['timing_verified_by_name']) ??
          existing.timingVerifiedByName,
      timingVerifiedByPhone: _readString(data['timing_verified_by_phone']) ??
          existing.timingVerifiedByPhone,
      timingUpdatedAt: updatedAt,
      addedByName: _readString(data['added_by_name']) ??
          _readString(data['added_by_name_private']) ??
          existing.addedByName,
      addedByPhone:
          _readString(data['added_by_phone']) ?? existing.addedByPhone,
      addedAt: _readDate(data['added_at']) ??
          _readDate(data['created_at']) ??
          existing.addedAt,
      prayerEditMeta:
          prayerEditMeta.isNotEmpty ? prayerEditMeta : existing.prayerEditMeta,
      placeId: _readString(data["place_id"]) ?? existing.placeId,
      firestoreDocId: docId ?? existing.firestoreDocId,
      needsReview: _readBool(data['needs_review']) || existing.needsReview,
    );
  }

  final dataLat = _readDouble(data['latitude']);
  final dataLng = _readDouble(data['longitude']);
  final cityName = _readString(data['city']) ?? '';
  CityInfo? cityMatch;
  if (dataLat == null || dataLng == null) {
    try {
      cityMatch = indianCities.firstWhere(
        (c) => c.name.toLowerCase() == cityName.toLowerCase(),
      );
    } catch (_) {}
  }

  return Mosque(
    name: _readString(data['name']) ?? 'Unnamed mosque',
    city: cityName,
    area: _readString(data['area']) ?? 'Area pending',
    address: _readString(data['address']) ?? 'Address pending',
    latitude: dataLat ?? cityMatch?.latitude,
    longitude: dataLng ?? cityMatch?.longitude,
    hasOwnCoordinates: dataLat != null && dataLng != null,
    distanceMeters: 999999,
    timings: timings,
    isVerified: data['timing_verification_status'] == 'admin_verified' ||
        data['timing_verification_status'] == 'source_verified',
    timingVerificationStatus:
        _readString(data['timing_verification_status']) ?? 'source_verified',
    timingVerifiedByName: _readString(data['timing_verified_by_name']),
    timingVerifiedByPhone: _readString(data['timing_verified_by_phone']),
    timingUpdatedAt: updatedAt,
    addedByName: _readString(data['added_by_name']) ??
        _readString(data['added_by_name_private']),
    addedByPhone: _readString(data['added_by_phone']),
    addedAt: _readDate(data['added_at']) ?? _readDate(data['created_at']),
    prayerEditMeta: prayerEditMeta,
    placeId: _readString(data['place_id']),
    firestoreDocId: docId,
    needsReview: _readBool(data['needs_review']),
  );
}

Map<String, PrayerEditMeta> _readPrayerEditMeta(dynamic raw) {
  if (raw is! Map) return const {};
  final result = <String, PrayerEditMeta>{};
  for (final entry in raw.entries) {
    final key = entry.key?.toString();
    final value = entry.value;
    if (key == null || value is! Map) continue;
    final name = _readString(value['name']) ??
        _readString(value['name_private']) ??
        _readString(value['updated_by_name']);
    final updatedAt =
        _readDate(value['updated_at']) ?? _readDate(value['created_at']);
    if (name == null || updatedAt == null) continue;
    result[key] = PrayerEditMeta(
      name: name,
      phone: _readString(value['phone']),
      updatedAt: updatedAt,
      value: _readString(value['value']),
    );
  }
  return result;
}

NamazTiming _mergeTimings(
  dynamic raw,
  NamazTiming? fallback, [
  Map<String, dynamic> flatData = const {},
]) {
  final map = raw is Map ? raw : const {};
  return NamazTiming(
    fajr: _readPrayerTiming('fajr', map['fajr']) ??
        _readPrayerTiming('fajr', flatData['timings.fajr']) ??
        _readPrayerTiming('fajr', flatData['fajr']) ??
        fallback?.fajr,
    zohar: _readPrayerTiming('zohar', map['zohar']) ??
        _readPrayerTiming('zohar', flatData['timings.zohar']) ??
        _readPrayerTiming('zohar', flatData['zohar']) ??
        fallback?.zohar,
    asr: _readPrayerTiming('asr', map['asr']) ??
        _readPrayerTiming('asr', flatData['timings.asr']) ??
        _readPrayerTiming('asr', flatData['asr']) ??
        fallback?.asr,
    maghrib: _readPrayerTiming('maghrib', map['maghrib']) ??
        _readPrayerTiming('maghrib', flatData['timings.maghrib']) ??
        _readPrayerTiming('maghrib', flatData['maghrib']) ??
        fallback?.maghrib,
    isha: _readPrayerTiming('isha', map['isha']) ??
        _readPrayerTiming('isha', flatData['timings.isha']) ??
        _readPrayerTiming('isha', flatData['isha']) ??
        fallback?.isha,
    juma: _readPrayerTiming('juma', map['juma']) ??
        _readPrayerTiming('juma', flatData['timings.juma']) ??
        _readPrayerTiming('juma', flatData['juma']) ??
        fallback?.juma,
    eidUlFitr: _readPrayerTiming('eid_ul_fitr', map['eid_ul_fitr']) ??
        _readPrayerTiming('eid_ul_fitr', flatData['timings.eid_ul_fitr']) ??
        _readPrayerTiming('eid_ul_fitr', flatData['eid_ul_fitr']) ??
        fallback?.eidUlFitr,
    eidUlAzha: _readPrayerTiming('eid_ul_azha', map['eid_ul_azha']) ??
        _readPrayerTiming('eid_ul_azha', flatData['timings.eid_ul_azha']) ??
        _readPrayerTiming('eid_ul_azha', flatData['eid_ul_azha']) ??
        fallback?.eidUlAzha,
  );
}

Mosque _withAutoCalendarMaghrib(Mosque mosque, String maghribJamaat) {
  final normalizedMaghrib =
      normalizePrayerTimingInput('maghrib', maghribJamaat) ?? maghribJamaat;
  final timings = mosque.timings;
  return mosque.copyWith(
    timings: NamazTiming(
      fajr: timings.fajr,
      zohar: timings.zohar,
      asr: timings.asr,
      maghrib: normalizedMaghrib,
      isha: timings.isha,
      juma: timings.juma,
      eidUlFitr: timings.eidUlFitr,
      eidUlAzha: timings.eidUlAzha,
    ),
  );
}

String? _readPrayerTiming(String prayer, dynamic value) {
  return normalizePrayerTimingInput(prayer, _readString(value) ?? '');
}

String? _readString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return text;
}

bool _readBool(dynamic value) {
  if (value is bool) return value;
  return value?.toString().toLowerCase() == 'true';
}

double? _readDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

DateTime? _readDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

String? _cleanContributorNameOrNull(Object? value) {
  final name = value?.toString().trim() ?? '';
  if (name.isEmpty || name.toLowerCase() == 'namaz volunteer') return null;
  return name;
}

class _RewardsPreviewCard extends StatelessWidget {
  const _RewardsPreviewCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFE4B4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.workspace_premium, size: 16, color: Color(0xFFB8860B)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Contributors Leaderboard',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}

class _LocationPanel extends StatelessWidget {
  const _LocationPanel({
    required this.radiusKm,
    required this.loadingLocation,
    required this.isCurrentLocation,
    required this.permissionDeniedForever,
    required this.onRefreshLocation,
    required this.onRadiusChanged,
    required this.cityName,
  });

  final int radiusKm;
  final bool loadingLocation;
  final bool isCurrentLocation;
  final bool permissionDeniedForever;
  final VoidCallback onRefreshLocation;
  final ValueChanged<int> onRadiusChanged;
  final String cityName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.my_location, color: Color(0xFF0F7C68)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  loadingLocation
                      ? 'Finding your location...'
                      : isCurrentLocation
                          ? 'Nearest masjids from your location'
                          : '$cityName masjid list',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Use current location',
                onPressed: onRefreshLocation,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          // Show a clear message when location permission is permanently denied
          if (permissionDeniedForever) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_off,
                    size: 14, color: Color(0xFF856404)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Location access blocked. Distances shown from city center.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF856404)),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Geolocator.openAppSettings(),
                  child: const Text(
                    'Open Settings',
                    style: TextStyle(fontSize: 12, color: Color(0xFF0F7C68)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2 km')),
                ButtonSegment(value: 10, label: Text('10 km')),
                ButtonSegment(value: 25, label: Text('25 km')),
              ],
              selected: {radiusKm},
              onSelectionChanged: (values) => onRadiusChanged(values.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _NamazFilter extends StatelessWidget {
  const _NamazFilter({required this.selectedNamaz, required this.onSelected});

  final String selectedNamaz;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = {
      'all': 'All',
      'fajr': 'Fajr',
      'zohar': 'Zuhr',
      'asr': 'Asr',
      'maghrib': 'Maghrib',
      'isha': 'Isha',
      'juma': "Jumu'ah",
      'eid': 'Eid',
    };

    final entries = options.entries.toList();
    final eidWindow = getEidWindowStatus(DateTime.now());
    final eidActive = eidWindow.type != EidType.none;

    void handleTap(String key) {
      if (key == 'eid' && !eidActive) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Row(
              children: [
                Text('🌙 ', style: TextStyle(fontSize: 20)),
                Text(
                  'Eid Timings',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            content: const Text(
              'Eid prayer times become available closer to Eid.\n\n'
              'When the Eid moon is sighted, you can update your '
              'mosque\'s Eid namaz time via "Suggest Edit" and it '
              'will be visible to everyone instantly.\n\n'
              'This filter activates automatically a few days before Eid.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Got it',
                  style: TextStyle(color: Color(0xFF0F7C68)),
                ),
              ),
            ],
          ),
        );
        return;
      }
      onSelected(key);
    }

    return Column(
      children: [
        Row(
          children: List.generate(
            4,
            (i) => _filterCell(entries[i], selectedNamaz, handleTap),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(
            4,
            (i) => _filterCell(entries[i + 4], selectedNamaz, handleTap),
          ),
        ),
      ],
    );
  }
}

Widget _filterCell(
  MapEntry<String, String> entry,
  String selected,
  ValueChanged<String> onSelected,
) {
  final isSelected = selected == entry.key;
  return Expanded(
    child: GestureDetector(
      onTap: () => onSelected(entry.key),
      child: Container(
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F7C68) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF0F7C68) : const Color(0xFFDDDDDD),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          entry.value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    ),
  );
}

// ── Duplicate detection ──────────────────────────────────────────────────────

String _normalizeMosqueName(String name) {
  const stopWords = {
    'masjid',
    'mosque',
    'مسجد',
    'मस्जिद',
    'jama',
    'jamia',
    'जामा',
    'जामिया',
    'wali',
    'wala',
    'wale',
    'वाली',
    'वाला',
    'sahab',
    'saab',
    'sahib',
    'ki',
    'ka',
    'ke',
    'की',
    'का',
    'के',
    'the',
    'and',
  };
  final words = name
      .toLowerCase()
      .replaceAll(RegExp(r"[^\w\s؀-ۿऀ-ॿ]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !stopWords.contains(w))
      .join(' ');
  return words.trim();
}

Set<String> _trigrams(String s) {
  final clean = s.replaceAll(' ', '');
  if (clean.length < 3) return {clean};
  return {
    for (int i = 0; i <= clean.length - 3; i++) clean.substring(i, i + 3)
  };
}

double _nameSimilarity(String a, String b) {
  final na = _normalizeMosqueName(a);
  final nb = _normalizeMosqueName(b);
  if (na == nb) return 1.0;
  if (na.isEmpty || nb.isEmpty) return 0.0;
  final ta = _trigrams(na);
  final tb = _trigrams(nb);
  final intersection = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  return union == 0 ? 0 : intersection / union;
}

int _duplicateScore(Mosque a, Mosque b) {
  if (a.firestoreDocId == null ||
      b.firestoreDocId == null ||
      a.firestoreDocId == b.firestoreDocId) return 0;

  int score = 0;

  // Location proximity
  if (a.hasCoordinates && b.hasCoordinates) {
    final dist = Geolocator.distanceBetween(
        a.latitude!, a.longitude!, b.latitude!, b.longitude!);
    if (dist < 100)
      score += 45;
    else if (dist < 300)
      score += 25;
    else if (dist < 800) score += 10;
  } else if ((a.area.isNotEmpty && b.area.isNotEmpty) &&
      _nameSimilarity(a.area, b.area) > 0.5) {
    score += 20;
  }

  // Name similarity (trigram, language-agnostic)
  final nameSim = _nameSimilarity(a.name, b.name);
  if (nameSim >= 0.85)
    score += 50;
  else if (nameSim >= 0.65)
    score += 35;
  else if (nameSim >= 0.45) score += 15;

  // Address overlap
  if (a.address.length > 5 && b.address.length > 5) {
    if (_nameSimilarity(a.address, b.address) > 0.55) score += 15;
  }

  return score.clamp(0, 100);
}

/// Returns map of docId → list of duplicate Mosques for that entry.
Map<String, List<Mosque>> _findDuplicateGroups(List<Mosque> mosques) {
  final result = <String, List<Mosque>>{};
  for (int i = 0; i < mosques.length; i++) {
    for (int j = i + 1; j < mosques.length; j++) {
      if (_duplicateScore(mosques[i], mosques[j]) >= 60) {
        final idI = mosques[i].firestoreDocId;
        final idJ = mosques[j].firestoreDocId;
        if (idI != null && idJ != null) {
          result.putIfAbsent(idI, () => []).add(mosques[j]);
          result.putIfAbsent(idJ, () => []).add(mosques[i]);
        }
      }
    }
  }
  return result;
}

/// Returns true if delete is allowed, false if rate-limited (and signs out).
Future<bool> _checkAndRecordDelete(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;

  final today = DateTime.now();
  final dateKey =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  final quotaRef = FirebaseFirestore.instance
      .collection('user_delete_quota')
      .doc('${uid}_$dateKey');

  try {
    final snap = await quotaRef.get();
    final count = (snap.data()?['count'] as num?)?.toInt() ?? 0;

    if (count >= 1) {
      // Rate-limited: sign out and warn
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Account Suspended'),
            content: const Text(
              'You have deleted more than allowed mosques today. '
              'Your account has been signed out for suspicious activity.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(_),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return false;
    }

    // Record the deletion
    await quotaRef.set(
      {'count': count + 1, 'date': dateKey, 'uid': uid},
      SetOptions(merge: true),
    );
    return true;
  } catch (_) {
    return true; // allow on quota-check failure (don't block genuine users)
  }
}

void _showDuplicateResolver(
    BuildContext context, Mosque thisMosque, List<Mosque> others) {
  final all = [thisMosque, ...others];
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Possible Duplicates',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Keep one mosque and delete the rest.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 16),
            ...all.map((m) {
              final timingCount = [
                m.timings.fajr,
                m.timings.zohar,
                m.timings.asr,
                m.timings.maghrib,
                m.timings.isha,
                m.timings.juma,
              ].where((t) => t != null).length;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700),
                              maxLines: 2),
                          if (m.area.isNotEmpty)
                            Text(m.area,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.black54)),
                          const SizedBox(height: 4),
                          Row(children: [
                            Icon(
                              timingCount > 0
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              size: 12,
                              color:
                                  timingCount > 0 ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 3),
                            Text('$timingCount timings',
                                style: const TextStyle(fontSize: 11)),
                            const SizedBox(width: 10),
                            Icon(
                              m.hasCoordinates
                                  ? Icons.location_on
                                  : Icons.location_off,
                              size: 12,
                              color:
                                  m.hasCoordinates ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 3),
                            Text(
                                m.hasCoordinates
                                    ? 'Has location'
                                    : 'No location',
                                style: const TextStyle(fontSize: 11)),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F7C68),
                            minimumSize: const Size(64, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Keep'),
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            minimumSize: const Size(64, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                          onPressed: m.firestoreDocId == null
                              ? null
                              : () async {
                                  Navigator.pop(ctx);
                                  if (!await _checkAndRecordDelete(context))
                                    return;
                                  await FirebaseFirestore.instance
                                      .collection('mosques')
                                      .doc(m.firestoreDocId!)
                                      .update({
                                    'deleted': true,
                                    'status': 'deleted'
                                  });
                                },
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _MosqueCard extends StatelessWidget {
  const _MosqueCard({
    required this.result,
    required this.cityName,
    required this.isFavourite,
    required this.onToggleFavourite,
    required this.isPinned,
    required this.onTogglePin,
    this.hijriAdjustment = 0,
    this.duplicates = const [],
    this.onContribute,
  });

  final MosqueResult result;
  final String cityName;
  final bool isFavourite;
  final VoidCallback onToggleFavourite;
  final bool isPinned;
  final VoidCallback onTogglePin;
  final int hijriAdjustment;
  final List<Mosque> duplicates;
  final VoidCallback? onContribute;

  bool get isPotentialDuplicate => duplicates.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final mosque = result.mosque;
    final next = result.nextJamaat;
    final updateStamp = _formatUpdatedAt(mosque.timingUpdatedAt);

    return Card(
      elevation: isPinned ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isPinned ? const Color(0xFF0F7C68) : const Color(0xFFE0E0E0),
          width: isPinned ? 2 : 1,
        ),
      ),
      color: isPinned ? const Color(0xFFF0FAF7) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: mosque.addedByName != null &&
                            mosque.addedByName!.isNotEmpty
                        ? () {
                            showDialog<void>(
                              context: context,
                              builder: (_) => Dialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                insetPadding: const EdgeInsets.symmetric(
                                  horizontal: 40,
                                  vertical: 24,
                                ),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(18, 16, 18, 12),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(top: 2),
                                            child: Icon(Icons.mosque,
                                                size: 16,
                                                color: Color(0xFF0F7C68)),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  mosque.name,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF0F7C68),
                                                  ),
                                                ),
                                                if (mosque.address.isNotEmpty)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 2),
                                                    child: Text(
                                                      mosque.address,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            Color(0xFF888888),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      GestureDetector(
                                        onTap: mosque.addedByPhone != null
                                            ? () {
                                                Navigator.pop(context);
                                                _openContributorContact(
                                                  context,
                                                  mosque.addedByName!,
                                                  mosque.addedByPhone,
                                                );
                                              }
                                            : null,
                                        child: RichText(
                                          text: TextSpan(
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF555555),
                                            ),
                                            children: [
                                              const TextSpan(text: 'Added by '),
                                              TextSpan(
                                                text: mosque.addedByName ?? '',
                                                style: TextStyle(
                                                  color:
                                                      const Color(0xFF0F7C68),
                                                  fontWeight: FontWeight.w700,
                                                  decoration: mosque
                                                              .addedByPhone !=
                                                          null
                                                      ? TextDecoration.underline
                                                      : TextDecoration.none,
                                                  decorationColor:
                                                      const Color(0xFF0F7C68),
                                                ),
                                              ),
                                              if (mosque.addedAt != null)
                                                TextSpan(
                                                  text:
                                                      '  ·  ${_formatUpdatedAt(mosque.addedAt!)}',
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFFAF7),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Jazakallah Khairan',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF0A5244),
                                              ),
                                            ),
                                            SizedBox(height: 1),
                                            Text(
                                              'May Allah reward you with goodness.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF0F7C68),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          style: TextButton.styleFrom(
                                            minimumSize: Size.zero,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 6),
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Close'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                        : null,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: SizedBox(
                            height: 26,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                mosque.name,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (mosque.isVerified)
                          const Padding(
                            padding: EdgeInsets.only(left: 5),
                            child: Icon(
                              Icons.verified,
                              size: 16,
                              color: Color(0xFF0F7C68),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: isPinned ? 'Unpin mosque' : 'Pin — my mosque',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: onTogglePin,
                  icon: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: isPinned ? const Color(0xFF0F7C68) : Colors.black38,
                    size: 18,
                  ),
                ),
              ],
            ),
            if (mosque.needsReview || isPotentialDuplicate)
              Row(
                children: [
                  if (mosque.needsReview)
                    Container(
                      margin: const EdgeInsets.only(top: 4, right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber,
                              size: 12, color: Colors.orange),
                          SizedBox(width: 4),
                          Text('Under Review',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.orange)),
                        ],
                      ),
                    ),
                  if (isPotentialDuplicate)
                    GestureDetector(
                      onTap: () =>
                          _showDuplicateResolver(context, mosque, duplicates),
                      child: Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_outlined,
                                size: 12, color: Colors.red),
                            SizedBox(width: 4),
                            Text('Possible Duplicate — tap to resolve',
                                style:
                                    TextStyle(fontSize: 10, color: Colors.red)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 6),
            Text('${mosque.area} - ${_distanceLabel(mosque)}'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE1F5EE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          next == null
                              ? 'Namaz timing pending'
                              : '${_title(next.namaz)} jamaat',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F6E56),
                          ),
                        ),
                        if (next != null)
                          Text(
                            formatPrayerStoredTime(next.namaz, next.time),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F6E56),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (next != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'starts in',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF0F6E56),
                          ),
                        ),
                        Text(
                          next.startsIn,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F6E56),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_eidBannerText() != null) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFD700)),
                ),
                child: Row(
                  children: [
                    const Text('🌙', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      _eidBannerText()!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF856404),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.4,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              children: [
                _TimingCell(
                  label: 'Fajr',
                  value: mosque.timings.fajr,
                  editMeta: mosque.prayerEditMeta['fajr'],
                ),
                _TimingCell(
                  label: 'Zuhr',
                  value: mosque.timings.zohar,
                  editMeta: mosque.prayerEditMeta['zohar'],
                ),
                _TimingCell(
                  label: 'Asr',
                  value: mosque.timings.asr,
                  editMeta: mosque.prayerEditMeta['asr'],
                ),
                _TimingCell(
                  label: 'Maghrib',
                  value: mosque.timings.maghrib,
                  editMeta: mosque.prayerEditMeta['maghrib'],
                ),
                _TimingCell(
                  label: 'Isha',
                  value: mosque.timings.isha,
                  editMeta: mosque.prayerEditMeta['isha'],
                ),
                _TimingCell(
                  label: "Jumu'ah",
                  value: mosque.timings.juma,
                  editMeta: mosque.prayerEditMeta['juma'],
                ),
                if (_shouldShowEid(EidType.eidUlFitr) &&
                    mosque.timings.eidUlFitr != null)
                  _TimingCell(
                    label: 'Eid Fitr',
                    value: mosque.timings.eidUlFitr,
                    editMeta: mosque.prayerEditMeta['eid_ul_fitr'],
                  ),
                if (_shouldShowEid(EidType.eidUlAdha) &&
                    mosque.timings.eidUlAzha != null)
                  _TimingCell(
                    label: 'Eid Adha',
                    value: mosque.timings.eidUlAzha,
                    editMeta: mosque.prayerEditMeta['eid_ul_azha'],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Stale timing warning — shown when timings haven't been updated in 60+ days
            Builder(
              builder: (_) {
                final updatedAt = mosque.timingUpdatedAt;
                // Dates before 2015 are seeded defaults, not real updates
                final isDefaultTimestamp = updatedAt.year < 2015;
                final daysSinceUpdate =
                    DateTime.now().difference(updatedAt).inDays;
                final isStale = !isDefaultTimestamp &&
                    daysSinceUpdate >= 60 &&
                    mosque.hasAnyTiming;
                final needsTimings = !mosque.hasAnyTiming || isDefaultTimestamp;
                if (!isStale && !needsTimings) return const SizedBox.shrink();
                final message = needsTimings
                    ? 'Community timings not yet added — tap + to contribute'
                    : 'Timings not updated in $daysSinceUpdate days — please verify';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: needsTimings ? onContribute : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: needsTimings
                            ? const Color(0xFFEFFAF7)
                            : const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: needsTimings
                              ? const Color(0xFF0F7C68)
                              : const Color(0xFFFFCC02),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            needsTimings
                                ? Icons.add_circle_outline
                                : Icons.access_time,
                            size: 13,
                            color: needsTimings
                                ? const Color(0xFF0F7C68)
                                : const Color(0xFF856404),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(
                                fontSize: 11,
                                color: needsTimings
                                    ? const Color(0xFF0F7C68)
                                    : const Color(0xFF856404),
                              ),
                            ),
                          ),
                          if (needsTimings)
                            const Icon(Icons.arrow_forward_ios,
                                size: 10, color: Color(0xFF0F7C68)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // Verified badge + timestamp + contributor name
            Row(
              children: [
                if (mosque.isVerified)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE1F5EE),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, size: 12, color: Color(0xFF0F6E56)),
                        SizedBox(width: 3),
                        Text(
                          'Verified',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF0F6E56),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (mosque.isVerified) const SizedBox(width: 6),
                Expanded(
                  child: Builder(
                    builder: (_) {
                      String prayerLabel = '';
                      String contributorLabel = '';
                      // Exclude maghrib — it auto-calculates from sunset; only
                      // show it here if someone explicitly did a manual edit.
                      final manualEdits = mosque.prayerEditMeta.entries
                          .where((e) =>
                              e.key != 'maghrib' ||
                              e.value.name.isNotEmpty && e.value.name != 'auto')
                          .toList();
                      if (manualEdits.isNotEmpty) {
                        final recent = manualEdits.reduce(
                          (a, b) => a.value.updatedAt.isAfter(b.value.updatedAt)
                              ? a
                              : b,
                        );
                        prayerLabel = ' · ${_title(recent.key)}';
                        if (recent.value.name.isNotEmpty) {
                          contributorLabel = ' by ${recent.value.name}';
                        }
                      } else if (mosque.timingVerifiedByName != null &&
                          mosque.timingVerifiedByName!.isNotEmpty) {
                        contributorLabel = ' by ${mosque.timingVerifiedByName}';
                      }
                      return Text(
                        '$updateStamp$prayerLabel$contributorLabel',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Actions row
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed:
                        mosque.hasCoordinates ? () => _openMaps(mosque) : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F7C68),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'Navigate',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _IconRoundBtn(
                  icon: Icons.edit_note,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SuggestEditScreen(mosque: mosque),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _IconRoundBtn(
                  icon: Icons.alarm_add,
                  onTap: () => _MosqueCard._openReminderSheet(context, mosque),
                ),
                const SizedBox(width: 6),
                _IconRoundBtn(
                  icon: Icons.share_outlined,
                  onTap: () => _shareTimingOnWhatsApp(mosque, next),
                ),
                const SizedBox(width: 6),
                _IconRoundBtn(
                  icon: Icons.flag_outlined,
                  color: Colors.orange.shade400,
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _ReportMosqueDialog(mosque: mosque),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _shouldShowEid(EidType type) {
    final window =
        getEidWindowStatus(DateTime.now(), hijriAdjustment: hijriAdjustment);
    return window.type == type;
  }

  String? _eidBannerText() {
    final window =
        getEidWindowStatus(DateTime.now(), hijriAdjustment: hijriAdjustment);
    if (window.type == EidType.none) return null;
    final name =
        window.type == EidType.eidUlFitr ? 'Eid ul Fitr' : 'Eid ul Adha';
    if (window.isEidDay) return 'Eid Mubarak! $name is today';
    if (window.isBeforeEid) {
      final d = window.daysUntilEid;
      return '$name in $d day${d == 1 ? '' : 's'}';
    }
    return null;
  }

  static String _distanceLabel(Mosque mosque) {
    if (!mosque.hasCoordinates) return 'location pending';
    final meters = mosque.distanceMeters;
    if (meters < 1000) return '${meters}m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String _title(String value) {
    return switch (value.toLowerCase()) {
      'zohar' => 'Zuhr',
      'juma' => "Jumu'ah",
      _ => value[0].toUpperCase() + value.substring(1),
    };
  }

  static Future<void> _openMaps(Mosque mosque) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${mosque.latitude},${mosque.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> _openContributorContact(
    BuildContext context,
    String name,
    String? phone,
  ) async {
    if (phone == null || phone.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name ka number available nahi hai')),
        );
      }
      return;
    }
    // E.164 format (+919876543210) → WhatsApp needs digits only
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    final whatsappUri = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(whatsappUri)) {
      await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(name),
            content: Text('Phone: $phone'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  static Future<void> _shareTimingOnWhatsApp(
    Mosque mosque,
    NextJamaat? next,
  ) async {
    final nextLine = next == null
        ? 'Namaz timing pending'
        : 'Next ${_title(next.namaz)} jamaat: ${formatPrayerStoredTime(next.namaz, next.time)} (in ${next.startsIn})';
    final msg = Uri.encodeComponent(
      'Namaz Near Me\n${mosque.name}\n${mosque.area}\n$nextLine',
    );
    final uri = Uri.parse('https://wa.me/?text=$msg');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String _formatUpdatedAt(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} hr ago';
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';
  }

  static Future<void> _openReminderSheet(
    BuildContext context,
    Mosque mosque,
  ) async {
    var selectedNamaz = 'fajr';
    var before = 10;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(context).viewPadding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set reminder - ${mosque.name}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedNamaz,
                  decoration: const InputDecoration(
                    labelText: 'Namaz',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'fajr', child: Text('Fajr')),
                    DropdownMenuItem(value: 'zohar', child: Text('Zuhr')),
                    DropdownMenuItem(value: 'asr', child: Text('Asr')),
                    DropdownMenuItem(value: 'maghrib', child: Text('Maghrib')),
                    DropdownMenuItem(value: 'isha', child: Text('Isha')),
                    DropdownMenuItem(
                        value: 'juma', child: Text("Jumu'ah (Fri)")),
                  ],
                  onChanged: (v) => setState(() => selectedNamaz = v ?? 'fajr'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: before,
                  decoration: const InputDecoration(
                    labelText: 'Remind before jamaat',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('5 minutes')),
                    DropdownMenuItem(value: 10, child: Text('10 minutes')),
                    DropdownMenuItem(value: 15, child: Text('15 minutes')),
                  ],
                  onChanged: (v) => setState(() => before = v ?? 10),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final storedTime = mosque.timings.byName(selectedNamaz);
                      if (storedTime == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Timing not available')),
                        );
                        return;
                      }
                      final jamaat = _nextDateTimeForStoredTime(
                        selectedNamaz,
                        storedTime,
                      );
                      final id = Object.hash(
                            mosqueKey(mosque.name),
                            selectedNamaz,
                            before,
                          ).abs() %
                          2147483647;
                      try {
                        final canExact = await NotificationService.instance
                            .schedulePrayerReminder(
                          id: id,
                          mosqueName: mosque.name,
                          namaz: _title(selectedNamaz),
                          jamaatTime: jamaat,
                          beforeMinutes: before,
                        );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Reminder set: ${_title(selectedNamaz)} ${formatPrayerStoredTime(selectedNamaz, storedTime)} ($before min before)',
                              ),
                            ),
                          );
                          if (!canExact) {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Enable Exact Reminders'),
                                content: const Text(
                                  'Reminder saved. For precise alerts on Samsung:\n\n'
                                  '1. Settings → Battery and device care → Battery\n'
                                  '2. Background usage limits\n'
                                  '3. "Never sleeping apps" → (+) → Add Namaz Near Me\n\n'
                                  'This is a one-time setup.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () async {
                                      Navigator.of(context).pop();
                                      try {
                                        await launchUrl(
                                          Uri.parse(
                                            'package:com.samsung.android.lool',
                                          ),
                                          mode: LaunchMode.externalApplication,
                                        );
                                      } catch (_) {
                                        try {
                                          await launchUrl(
                                            Uri.parse(
                                              'android.settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
                                            ),
                                          );
                                        } catch (_) {}
                                      }
                                    },
                                    child: const Text('Open Settings'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('Later'),
                                  ),
                                ],
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not set reminder. Please try again. ($e)',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Set Reminder'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static DateTime _nextDateTimeForStoredTime(String prayer, String time) {
    final now = DateTime.now();
    final normalized = normalizePrayerTimingInput(prayer, time) ?? time;
    final parts = normalized.split(':');
    final hour = int.tryParse(parts.first) ?? now.hour;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    if (prayer == 'juma') {
      final daysToFriday = (DateTime.friday - now.weekday + 7) % 7;
      var target = DateTime(
        now.year,
        now.month,
        now.day + daysToFriday,
        hour,
        minute,
      );
      if (!target.isAfter(now)) target = target.add(const Duration(days: 7));
      return target;
    }
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
    return target;
  }
}

class _ReportMosqueDialog extends StatefulWidget {
  const _ReportMosqueDialog({required this.mosque});
  final Mosque mosque;

  @override
  State<_ReportMosqueDialog> createState() => _ReportMosqueDialogState();
}

class _ReportMosqueDialogState extends State<_ReportMosqueDialog> {
  String _reason = 'timing_wrong';
  bool _submitting = false;

  static const _reasons = {
    'timing_wrong': 'Prayer timing is incorrect',
    'does_not_exist': 'Masjid does not exist here',
    'duplicate': 'Duplicate entry',
    'location_wrong': 'Location is incorrect',
  };

  Future<void> _submit() async {
    final phone = context.read<AppState>().verifiedPhone;
    if (phone == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please verify your phone via "Update" first, then you can submit a report.',
          ),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await FirebaseFirestore.instance.collection('mosque_edits').add({
        'edit_type': 'report',
        'mosque_name': widget.mosque.name,
        'mosque_id': widget.mosque.firestoreDocId ?? '',
        'city': (widget.mosque.city ?? '').trim(),
        'area': widget.mosque.area,
        'report_reason': _reason,
        'reported_by_phone': phone,
        'submitted_by_uid': FirebaseAuth.instance.currentUser?.uid,
        'status': 'pending',
        'scoreAwarded': false,
        'created_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you! Report submitted.')),
      );
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.flag_outlined, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.mosque.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What is the issue?',
              style: TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 8),
          ..._reasons.entries.map(
            (e) => RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(e.value, style: const TextStyle(fontSize: 13)),
              value: e.key,
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v!),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: Colors.orange),
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Submit Report'),
        ),
      ],
    );
  }
}

class _IconRoundBtn extends StatelessWidget {
  const _IconRoundBtn({required this.icon, this.onTap, this.color});
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE0E0E0)),
          color: const Color(0xFFF9F9F9),
        ),
        child: Icon(icon, size: 18, color: color ?? const Color(0xFF555555)),
      ),
    );
  }
}

class _TimingCell extends StatelessWidget {
  const _TimingCell({required this.label, required this.value, this.editMeta});

  final String label;
  final String? value;
  final PrayerEditMeta? editMeta;

  @override
  Widget build(BuildContext context) {
    final display =
        value == null ? '—' : formatPrayerStoredTime(_prayerKey(label), value!);
    final meta = editMeta;
    final content = Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF888888),
                  ),
                  maxLines: 1,
                ),
              ),
            ],
          ),
          Text(
            display,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111111),
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
    return content;
  }
}

String formatStoredTime(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return value;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return value;
  final period = hour >= 12 ? 'PM' : 'AM';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $period';
}

String formatPrayerStoredTime(String prayer, String value) {
  final normalized = normalizePrayerTimingInput(prayer, value);
  return formatStoredTime(normalized ?? value);
}

String? normalizeTimingInput(String value) {
  final text = value.trim().toUpperCase().replaceAll('.', '');
  if (text.isEmpty) return null;

  final match = RegExp(
    r'^(\d{1,2})(?::(\d{1,2}))?\s*(AM|PM)?$',
  ).firstMatch(text);
  if (match == null) return text;

  var hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2) ?? '0');
  final period = match.group(3);
  if (hour == null || minute == null) return text;
  if (minute < 0 || minute > 59) return text;

  if (period != null) {
    if (hour < 1 || hour > 12) return text;
    if (period == 'AM') {
      hour = hour == 12 ? 0 : hour;
    } else {
      hour = hour == 12 ? 12 : hour + 12;
    }
  } else if (hour < 0 || hour > 23) {
    return text;
  }

  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String? normalizePrayerTimingInput(String prayer, String value) {
  final normalized = normalizeTimingInput(value);
  if (normalized == null) return null;

  final key = _prayerKey(prayer);
  final parts = normalized.split(':');
  if (parts.length < 2) return normalized;
  var hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return normalized;

  if (_forceAmPrayerKeys.contains(key)) {
    if (hour == 12) hour = 0;
    if (hour > 12) hour -= 12;
  } else if (_forcePmPrayerKeys.contains(key)) {
    if (hour < 12) hour += 12;
  }

  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

const _forcePmPrayerKeys = {'zohar', 'asr', 'maghrib', 'isha', 'juma'};
const _forceAmPrayerKeys = {'fajr', 'eid_ul_fitr', 'eid_ul_azha'};

String _prayerKey(String value) {
  final key = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  if (key == 'zuhr' || key == 'dhuhr' || key == 'zuhur') return 'zohar';
  if (key == 'jumma' || key == 'jumuah') return 'juma';
  if (key == 'eid_fitr' || key == 'eidul_fitr') return 'eid_ul_fitr';
  if (key == 'eid_adha' || key == 'eid_azha' || key == 'eidul_azha') {
    return 'eid_ul_azha';
  }
  return key.replaceAll(RegExp(r'_+$'), '');
}

class _MosqueSearchDelegate extends SearchDelegate<MosqueResult?> {
  _MosqueSearchDelegate({required this.results});
  final List<MosqueResult> results;

  @override
  String get searchFieldLabel => 'Search mosque...';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
              icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final q = query.toLowerCase();
    final filtered = results
        .where(
          (r) =>
              r.mosque.name.toLowerCase().contains(q) ||
              r.mosque.area.toLowerCase().contains(q) ||
              r.mosque.address.toLowerCase().contains(q),
        )
        .toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No mosque found.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final mosque = filtered[index].mosque;
        return ListTile(
          leading: const Icon(Icons.mosque, color: Color(0xFF0F7C68)),
          title: Text(
            mosque.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(mosque.area),
          trailing: Text(
            mosque.distanceMeters < 1000
                ? '${mosque.distanceMeters}m'
                : '${(mosque.distanceMeters / 1000).toStringAsFixed(1)}km',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          onTap: () => close(context, filtered[index]),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.message,
    this.onViewAll,
    this.onWidenRadius,
    this.onAddMosque,
  });
  final String message;
  final VoidCallback? onViewAll;
  final VoidCallback? onWidenRadius;
  final VoidCallback? onAddMosque;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mosque_outlined, size: 40, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            if (onViewAll != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onViewAll,
                icon: const Icon(Icons.mosque_outlined),
                label: const Text('View all mosques'),
              ),
            ],
            if (onWidenRadius != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onWidenRadius,
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Widen search radius'),
              ),
            ],
            if (onAddMosque != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onAddMosque,
                icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                label: const Text('Add the first mosque here'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SeedingState extends StatelessWidget {
  const _SeedingState({required this.cityName});
  final String cityName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Finding mosques in $cityName...',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
