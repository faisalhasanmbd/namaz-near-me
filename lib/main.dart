import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/sample_mosques.dart';
import 'models/daily_islamic_timings.dart';
import 'models/mosque.dart';
import 'services/islamic_timing_service.dart';
import 'services/jamaat_sorter.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'services/otp_session.dart';
import 'screens/suggest_edit_screen.dart';

// ── Eid detection ────────────────────────────────────────────────────────────
enum EidType { none, eidUlFitr, eidUlAdha }

class EidWindow {
  const EidWindow({required this.type, required this.daysUntilEid});
  final EidType type;
  final int daysUntilEid;
  bool get isEidDay => daysUntilEid == 0;
  bool get isBeforeEid => daysUntilEid > 0;
}

EidWindow getEidWindowStatus(DateTime date) {
  final h = _hijriFromDate(date);
  // Eid ul Fitr = 1 Shawwal (month 10), show from 25 Ramadan
  if (h[0] == 9 && h[1] >= 25) {
    return EidWindow(type: EidType.eidUlFitr, daysUntilEid: (30 - h[1]) + 1);
  }
  if (h[0] == 10 && h[1] <= 3) {
    return EidWindow(type: EidType.eidUlFitr, daysUntilEid: 1 - h[1]);
  }
  // Eid ul Adha = 10 Dhu al-Hijjah (month 12), show from 5th
  if (h[0] == 12 && h[1] >= 5 && h[1] <= 13) {
    return EidWindow(type: EidType.eidUlAdha, daysUntilEid: 10 - h[1]);
  }
  return const EidWindow(type: EidType.none, daysUntilEid: 999);
}

// Returns [month, day] of Hijri date for given Gregorian date
List<int> _hijriFromDate(DateTime date) {
  final jd = _gjd(date.year, date.month, date.day);
  final y = ((30 * (jd - 1948439.5) + 10646) / 10631).floor();
  final mo = _ijd(y, 1, 1);
  final m = ((jd - (29 + mo)) / 29.5).ceil() + 1;
  final month = m > 12 ? 12 : m;
  final day = (jd - _ijd(y, month, 1) + 1).floor();
  return [month, day];
}

double _gjd(int y, int mo, int d) {
  final a = ((14 - mo) / 12).floor();
  final yr = y + 4800 - a;
  final m = mo + 12 * a - 3;
  return d +
      ((153 * m + 2) / 5).floor() +
      365 * yr +
      (yr / 4).floor() -
      (yr / 100).floor() +
      (yr / 400).floor() -
      32045;
}

double _ijd(int y, int mo, int d) =>
    d +
    (29.5 * (mo - 1)).ceil() +
    (y - 1) * 354 +
    ((3 + 11 * y) / 30).floor() +
    1948439.5 -
    1;

// ─────────────────────────────────────────────────────────────────────────────

final ValueNotifier<Locale?> appLocaleNotifier = ValueNotifier<Locale?>(null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (error) {
    debugPrint('Firebase unavailable at startup: $error');
  }
  final prefs = await SharedPreferences.getInstance();
  final localeCode = prefs.getString('app_locale_code');
  appLocaleNotifier.value =
      localeCode == null || localeCode == 'system' ? null : Locale(localeCode);
  await NotificationService.instance.initialize();
  runApp(const NamazNearMeApp());
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

class _NearbyMosquesScreenState extends State<NearbyMosquesScreen> {
  String _selectedNamaz = 'all';
  int _radiusKm = 2;
  UserLocation _location = LocationService.moradabadCenter;
  bool _loadingLocation = true;
  CityInfo _selectedCity = indianCities.first;
  late final Stream<List<Mosque>> _mosquesStream;
  Set<String> _favouriteKeys = {};
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

  Stream<List<Mosque>> _watchMosques() async* {
    if (Firebase.apps.isEmpty) {
      yield List<Mosque>.from(sampleMosques);
      return;
    }
    try {
      yield* FirebaseFirestore.instance
          .collection('mosques')
          .snapshots()
          .map((snapshot) {
        final mergedByKey = {
          for (final mosque in sampleMosques) _mosqueKey(mosque.name): mosque,
        };
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final name = _readString(data['name']);
          if (name == null) continue;
          final key = _mosqueKey(name);
          if (_readBool(data['deleted']) || data['status'] == 'deleted') {
            mergedByKey.remove(key);
            continue;
          }
          mergedByKey[key] = _mosqueFromFirestore(data, mergedByKey[key]);
        }
        return mergedByKey.values.toList();
      });
    } catch (e) {
      debugPrint('Firestore error: \$e');
      yield List<Mosque>.from(sampleMosques);
    }
  }

  @override
  void initState() {
    super.initState();
    _mosquesStream = _watchMosques();
    _loadLocation();
    _loadAsrMethodPreference();
    _loadFavourites();
    _loadHijriDate();
    _loadHijriAdjustmentPermission();
    _startDateTicker();
  }

  @override
  void dispose() {
    _dateTicker?.cancel();
    super.dispose();
  }

  Future<void> _loadFavourites() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList('favourite_mosques') ?? [];
    if (mounted) setState(() => _favouriteKeys = keys.toSet());
  }

  Future<void> _loadAsrMethodPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt('asr_shadow_factor') ?? 2;
    if (!mounted) return;
    setState(() => _asrShadowFactor = value == 1 ? 1 : 2);
  }

  Future<void> _backfillMyContributorScore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final phone = user?.phoneNumber;
      final uid = user?.uid;
      final displayName = _cleanContributorName(user?.displayName);
      if (uid == null || phone == null) return;
      final prefs = await SharedPreferences.getInstance();
      final key = 'contributor_score_backfilled_$uid';
      if (prefs.getBool(key) == true) return;

      var score = 0;
      final logs = await FirebaseFirestore.instance
          .collection('contribution_logs')
          .where('phone', isEqualTo: phone)
          .get();
      score += logs.docs.length;

      final edits = await FirebaseFirestore.instance
          .collection('mosque_edits')
          .where('suggested_by_phone', isEqualTo: phone)
          .get();
      for (final doc in edits.docs) {
        final status = doc.data()['status'];
        if (status == 'approved' || status == 'applied') score++;
      }

      if (score > 0) {
        await FirebaseFirestore.instance
            .collection('top_contributors')
            .doc(uid)
            .set({
          'name': displayName,
          'score': score,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await prefs.setBool(key, true);
    } catch (error) {
      debugPrint('Contributor score backfill skipped: $error');
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('asr_shadow_factor', selected);
    if (!mounted) return;
    setState(() => _asrShadowFactor = selected);
  }

  Future<void> _toggleFavourite(String key) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favouriteKeys.contains(key)) {
        _favouriteKeys.remove(key);
      } else {
        _favouriteKeys.add(key);
      }
    });
    await prefs.setStringList('favourite_mosques', _favouriteKeys.toList());
  }

  String _mosqueUniqueKey(Mosque m) => m.placeId ?? m.name;

  Future<void> _loadHijriDate() async {
    var adjustment = 0;
    String? confirmedMonth;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('islamic_date_city')
          .doc(_cityDateKey(_selectedCity.name))
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
      _lastHijriLookupKey = _dateKey(lookupDate);
      _lastEnglishDateKey = _dateKey(DateTime.now());
    });
  }

  void _startDateTicker() {
    _lastEnglishDateKey = _dateKey(DateTime.now());
    _lastHijriLookupKey = _dateKey(IslamicTimingService(
      latitude: _selectedCity.latitude,
      longitude: _selectedCity.longitude,
      asrShadowFactor: _asrShadowFactor,
    ).hijriDateFor(DateTime.now()));
    _dateTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final englishKey = _dateKey(now);
      final hijriLookupKey = _dateKey(IslamicTimingService(
        latitude: _selectedCity.latitude,
        longitude: _selectedCity.longitude,
        asrShadowFactor: _asrShadowFactor,
      ).hijriDateFor(now));
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
    final location = await LocationService().currentOrFallback();
    final nearestCity = _nearestCityForLocation(location);
    if (!mounted) return;
    setState(() {
      _location = location;
      _selectedCity = nearestCity;
      _loadingLocation = false;
    });
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
    final selected = await showModalBottomSheet<CityInfo>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CitySearchSheet(selectedCity: _selectedCity),
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedCity = selected;
        _location = UserLocation(
          latitude: selected.latitude,
          longitude: selected.longitude,
          isCurrentLocation: false,
        );
        _loadingLocation = false;
      });
      _lastHijriLookupKey = null;
      _loadHijriDate();
    }
  }

  Future<void> _openLanguageSelector(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => const SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LanguageOptionTile(value: 'system', label: 'System default'),
            _LanguageOptionTile(value: 'en', label: 'English'),
            _LanguageOptionTile(value: 'ur', label: 'Urdu'),
            _LanguageOptionTile(value: 'ar', label: 'Arabic'),
            _LanguageOptionTile(value: 'fr', label: 'French'),
            _LanguageOptionTile(value: 'id', label: 'Indonesian'),
            _LanguageOptionTile(value: 'tr', label: 'Turkish'),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_locale_code', selected);
    appLocaleNotifier.value = selected == 'system' ? null : Locale(selected);
  }

  Future<void> _confirmHijriAdjustment(int adjustment) async {
    if (!_canAdjustHijri) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Only admins can adjust city Hijri date.')));
      }
      return;
    }
    final phone = await OtpSession.loadVerifiedPhone();
    if (phone == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Please verify your number first via Suggest Edit.')));
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
    final monthKey = _hijriMonthKey(correctedHijri);
    if (correctedHijri == null || monthKey == null) return;
    await FirebaseFirestore.instance
        .collection('islamic_date_city')
        .doc(_cityDateKey(_selectedCity.name))
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
    if (Firebase.apps.isEmpty) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _canAdjustHijri = false);
        return;
      }
      final doc = await FirebaseFirestore.instance
          .collection('admin_users')
          .doc(user.uid)
          .get();
      final isAdmin = (doc.data()?['is_admin'] == true);
      if (mounted) setState(() => _canAdjustHijri = isAdmin);
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
    final dailyTimings =
        islamicTimingService.today(hijriDateOverride: _hijriDateOverride);
    final autoMaghribJamaat = islamicTimingService.maghribJamaatTime();

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/namaz-near-me-icon.png',
          width: 42,
          height: 42,
          fit: BoxFit.contain,
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search mosque',
            onPressed: () => _openSearch(context),
          ),
          IconButton(
            tooltip: 'Change language',
            onPressed: () => _openLanguageSelector(context),
            icon: const Icon(Icons.language),
          ),
          IconButton(
            tooltip: 'Asr method',
            onPressed: () => _openAsrMethodSelector(context),
            icon: const Icon(Icons.schedule),
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
          if (useCompactActions)
            IconButton(
              tooltip: 'Update Prayer Times',
              onPressed: () => _openContributorScreen(context),
              icon: const Icon(Icons.edit_calendar),
            )
          else
            TextButton.icon(
              onPressed: () => _openContributorScreen(context),
              icon: const Icon(Icons.edit_calendar),
              label: const Text('Update'),
            ),
          IconButton(
            tooltip: _showFavouritesOnly
                ? 'Show all mosques'
                : 'Show favourites only',
            onPressed: () => setState(() {
              _showFavouritesOnly = !_showFavouritesOnly;
              _focusedMosqueKey = null;
            }),
            icon: Icon(_showFavouritesOnly ? Icons.star : Icons.star_border,
                color: _showFavouritesOnly ? Colors.amber : null),
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
            final mosques = snapshot.data ?? [];
            final mosquesWithAutoMaghrib = mosques
                .map((mosque) =>
                    _withAutoCalendarMaghrib(mosque, autoMaghribJamaat))
                .toList();
            final mosquesWithDistance = LocationService().applyDistances(
              mosquesWithAutoMaghrib,
              _location,
            );
            final visibleMosques = mosquesWithDistance
                .where((m) =>
                    m.distanceMeters <= _radiusKm * 1000 || !m.hasCoordinates)
                .toList();
            final filteredMosques = _showFavouritesOnly
                ? visibleMosques
                    .where((m) => _favouriteKeys.contains(_mosqueUniqueKey(m)))
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
                    .where((result) =>
                        _focusKeyForMosque(result.mosque) == _focusedMosqueKey)
                    .toList();

            return ListView(
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
                  onRefreshLocation: _loadLocation,
                  onRadiusChanged: (value) => setState(() => _radiusKm = value),
                  cityName: _selectedCity.name,
                ),
                const SizedBox(height: 16),
                _NamazFilter(
                  selectedNamaz: _selectedNamaz,
                  onSelected: (value) => setState(() => _selectedNamaz = value),
                ),
                const SizedBox(height: 16),
                _RewardsPreviewCard(
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RewardsScreen(
                        onBackfill: _backfillMyContributorScore,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (snapshot.hasError)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Live updates unavailable.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
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
                  const _EmptyState()
                else
                  for (final result in focusedResults) ...[
                    _MosqueCard(
                      result: result,
                      cityName: _selectedCity.name,
                      isFavourite: _favouriteKeys
                          .contains(_mosqueUniqueKey(result.mosque)),
                      onToggleFavourite: () =>
                          _toggleFavourite(_mosqueUniqueKey(result.mosque)),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LanguageOptionTile extends StatelessWidget {
  const _LanguageOptionTile({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.translate),
      title: Text(label),
      onTap: () => Navigator.of(context).pop(value),
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
          TextButton(
            onPressed: onViewAll,
            child: const Text('View all'),
          ),
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
  static const int _pillsPerPage = 4;

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
    const pillWidth = 64.0 + 6.0; // width + gap
    _scrollCtrl.animateTo(
      newPage * _pillsPerPage * pillWidth,
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
            const SnackBar(content: Text('Could not update. Check internet.')));
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              child: Row(children: [
                const Text('Moon date:',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
                const Spacer(),
                _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Row(children: [
                        _adjBtn('-1 day',
                            () => _submitOffset(widget.adjustment - 1)),
                        const SizedBox(width: 4),
                        _adjBtn(
                            'Correct', () => _submitOffset(widget.adjustment),
                            highlight: true),
                        const SizedBox(width: 4),
                        _adjBtn('+1 day',
                            () => _submitOffset(widget.adjustment + 1)),
                      ]),
              ]),
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
                        width: 72,
                        height: 72,
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 5),
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
                                    color: Colors.white70, fontSize: 8),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                displayLine1,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: isRange ? 9 : 11,
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
      onTap: enabled ? onTap : null,
      child: Container(
        width: 24,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 4),
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
  List<CityInfo> _filtered = indianCities;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    final ql = q.toLowerCase();
    setState(() {
      _filtered = indianCities
          .where((c) =>
              c.name.toLowerCase().contains(ql) ||
              c.state.toLowerCase().contains(ql))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, sc) => Column(children: [
        const SizedBox(height: 12),
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.black26, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _search,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search city or state...',
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: _onSearch,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
            child: ListView.builder(
          controller: sc,
          itemCount: _filtered.length,
          itemBuilder: (context, i) {
            final city = _filtered[i];
            final isSel = city.name == widget.selectedCity.name;
            return ListTile(
              leading: Icon(isSel ? Icons.location_on : Icons.location_city,
                  color: isSel ? const Color(0xFF0F7C68) : Colors.black45),
              title: Text(city.name,
                  style: TextStyle(
                      fontWeight: isSel ? FontWeight.w800 : FontWeight.normal,
                      color: isSel ? const Color(0xFF0F7C68) : null)),
              subtitle: Text(city.state),
              trailing: isSel
                  ? const Icon(Icons.check, color: Color(0xFF0F7C68))
                  : null,
              onTap: () => Navigator.of(context).pop(city),
            );
          },
        )),
      ]),
    );
  }
}

String _mosqueKey(String name) {
  return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String _mosqueDocId(String mosqueName, String cityName) {
  String clean(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  final base = '${clean(cityName)}-${clean(mosqueName)}'
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return base.isEmpty ? 'mosque-unknown' : base;
}

String _cityDateKey(String cityName) {
  return cityName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
}

String _dateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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

Mosque _mosqueFromFirestore(Map<String, dynamic> data, Mosque? existing) {
  final timings = _mergeTimings(data['timings'], existing?.timings, data);
  final updatedAt = _readDate(data['timing_updated_at']) ??
      _readDate(data['updated_at']) ??
      existing?.timingUpdatedAt ??
      DateTime.now();

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
      placeId: _readString(data["place_id"]),
    );
  }

  // If no coordinates, use city center as fallback
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
  final fallbackLat = cityMatch?.latitude;
  final fallbackLng = cityMatch?.longitude;

  return Mosque(
    name: _readString(data['name']) ?? 'Unnamed mosque',
    city: cityName,
    area: _readString(data['area']) ?? 'Area pending',
    address: _readString(data['address']) ?? 'Address pending',
    latitude: dataLat ?? fallbackLat,
    longitude: dataLng ?? fallbackLng,
    distanceMeters: 999999,
    timings: timings,
    isVerified: data['timing_verification_status'] == 'admin_verified' ||
        data['timing_verification_status'] == 'source_verified',
    timingVerificationStatus:
        _readString(data['timing_verification_status']) ?? 'source_verified',
    timingVerifiedByName: _readString(data['timing_verified_by_name']),
    timingVerifiedByPhone: _readString(data['timing_verified_by_phone']),
    timingUpdatedAt: updatedAt,
    placeId: _readString(data['place_id']),
  );
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
        fallback?.fajr,
    zohar: _readPrayerTiming('zohar', map['zohar']) ??
        _readPrayerTiming('zohar', flatData['timings.zohar']) ??
        fallback?.zohar,
    asr: _readPrayerTiming('asr', map['asr']) ??
        _readPrayerTiming('asr', flatData['timings.asr']) ??
        fallback?.asr,
    maghrib: _readPrayerTiming('maghrib', map['maghrib']) ??
        _readPrayerTiming('maghrib', flatData['timings.maghrib']) ??
        fallback?.maghrib,
    isha: _readPrayerTiming('isha', map['isha']) ??
        _readPrayerTiming('isha', flatData['timings.isha']) ??
        fallback?.isha,
    juma: _readPrayerTiming('juma', map['juma']) ??
        _readPrayerTiming('juma', flatData['timings.juma']) ??
        fallback?.juma,
    eidUlFitr: _readTiming(map['eid_ul_fitr']) ??
        _readTiming(flatData['timings.eid_ul_fitr']) ??
        fallback?.eidUlFitr,
    eidUlAzha: _readTiming(map['eid_ul_azha']) ??
        _readTiming(flatData['timings.eid_ul_azha']) ??
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

String? _readTiming(dynamic value) {
  return normalizeTimingInput(_readString(value) ?? '');
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

class ContributorSignupScreen extends StatefulWidget {
  const ContributorSignupScreen({
    super.key,
    required this.cityName,
    required this.mosques,
  });

  final String cityName;
  final List<Mosque> mosques;

  @override
  State<ContributorSignupScreen> createState() =>
      _ContributorSignupScreenState();
}

class _ContributorSignupScreenState extends State<ContributorSignupScreen> {
  static const _savedContributorNameKey = 'saved_contributor_name';
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _areaController = TextEditingController();
  final _newMosqueController = TextEditingController();
  final _addressController = TextEditingController();
  final _fajrController = TextEditingController();
  final _zoharController = TextEditingController();
  final _asrController = TextEditingController();
  final _maghribController = TextEditingController();
  final _ishaController = TextEditingController();
  final _jumaController = TextEditingController();
  final _eidUlFitrController = TextEditingController();
  final _eidUlAzhaController = TextEditingController();
  final _otpController = TextEditingController();

  String _role = 'Volunteer';
  String _maslak = 'Not specified';
  String _mosqueMode = 'existing';
  bool _shareContributorDetails = false;
  Mosque? _selectedMosque;
  bool _firebaseReady = false;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  bool _submitting = false;
  bool _otpSent = false;
  bool _phoneVerified = false;
  String? _verificationId;
  String? _pendingVerificationPhone;
  String? _verifiedPhone;
  String? _otpStatusMessage;
  Timer? _nameSaveTimer;

  List<Mosque> get _availableMosques {
    final source = widget.mosques.isEmpty ? sampleMosques : widget.mosques;
    final city = widget.cityName.toLowerCase().trim();
    return source.where((mosque) {
      final mosqueCity = mosque.city?.toLowerCase().trim();
      return mosqueCity != null && mosqueCity == city;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _cityController.text = widget.cityName;
    _selectedMosque = null;
    _nameController.addListener(_queueContributorNameSave);
    _loadSavedContributorName();
    _loadVerification();
  }

  Future<void> _loadSavedContributorName() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(_savedContributorNameKey)?.trim();
    if (!mounted || savedName == null || savedName.isEmpty) return;
    if (_nameController.text.trim().isEmpty) {
      _nameController.text = savedName;
    }
  }

  void _queueContributorNameSave() {
    _nameSaveTimer?.cancel();
    _nameSaveTimer = Timer(const Duration(milliseconds: 350), () async {
      await _saveContributorNameNow();
    });
  }

  Future<void> _saveContributorNameNow() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedContributorNameKey, name);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.displayName?.trim() != name) {
      try {
        await user.updateDisplayName(name);
      } catch (_) {}
    }
  }

  Future<void> _loadVerification() async {
    final phone = await OtpSession.loadVerifiedPhone();
    if (phone == null || !mounted) return;
    setState(() {
      _verifiedPhone = phone;
      _phoneController.text = phone;
      _phoneVerified = true;
      _otpStatusMessage = 'Mobile verified for this session.';
    });
  }

  void _syncAreaFromSelectedMosque() {
    final mosque = _selectedMosque;
    if (mosque == null) return;
    _areaController.text = mosque.area;
  }

  @override
  void dispose() {
    _nameSaveTimer?.cancel();
    _nameController.removeListener(_queueContributorNameSave);
    _nameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _areaController.dispose();
    _newMosqueController.dispose();
    _addressController.dispose();
    _fajrController.dispose();
    _zoharController.dispose();
    _asrController.dispose();
    _maghribController.dispose();
    _ishaController.dispose();
    _jumaController.dispose();
    _eidUlFitrController.dispose();
    _eidUlAzhaController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contribute — Add or Update Mosque')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Update timings or add a new mosque',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Verify your phone number, then update timings directly.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Your name *',
                  helperText: 'Required for leaderboard and certificate.',
                  border: OutlineInputBorder(),
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                enabled: !_phoneVerified && !_otpSent,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number (with country code)',
                  hintText: '+447911123456',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _normalizeE164Phone(value ?? '') == null
                    ? 'Enter a valid international phone number'
                    : null,
              ),
              const SizedBox(height: 10),
              _OtpVerificationPanel(
                otpController: _otpController,
                otpSent: _otpSent,
                phoneVerified: _phoneVerified,
                sendingOtp: _sendingOtp,
                verifyingOtp: _verifyingOtp,
                statusMessage: _otpStatusMessage,
                onSendOtp: _sendOtp,
                onVerifyOtp: _verifyOtp,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'Volunteer', child: Text('Volunteer')),
                  DropdownMenuItem(value: 'Muazzin', child: Text('Muazzin')),
                  DropdownMenuItem(value: 'Imam', child: Text('Imam')),
                ],
                onChanged: (value) => setState(() => _role = value ?? _role),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _areaController,
                      decoration: const InputDecoration(
                        labelText: 'Area',
                        border: OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _maslak,
                decoration: const InputDecoration(
                  labelText: 'School of Thought (Maslak)',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Not specified',
                    child: Text('Not specified'),
                  ),
                  DropdownMenuItem(value: 'Barelvi', child: Text('Barelvi')),
                  DropdownMenuItem(value: 'Deobandi', child: Text('Deobandi')),
                  DropdownMenuItem(
                    value: 'Ahl-e-Hadees',
                    child: Text('Ahl-e-Hadees'),
                  ),
                  DropdownMenuItem(value: 'Shia', child: Text('Shia')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (value) =>
                    setState(() => _maslak = value ?? _maslak),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'existing', label: Text('Existing')),
                  ButtonSegment(value: 'new', label: Text('New mosque')),
                ],
                selected: {_mosqueMode},
                onSelectionChanged: (values) {
                  setState(() {
                    _mosqueMode = values.first;
                    if (_mosqueMode == 'new') {
                      _selectedMosque = null;
                      _areaController.clear();
                    } else {
                      _selectedMosque = null;
                      _areaController.clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              if (_mosqueMode == 'existing')
                _MosqueSelectorField(
                  selectedMosque: _selectedMosque,
                  mosqueCount: _availableMosques.length,
                  onTap: _pickExistingMosque,
                )
              else ...[
                TextFormField(
                  controller: _newMosqueController,
                  decoration: const InputDecoration(
                    labelText: 'New mosque name',
                    border: OutlineInputBorder(),
                  ),
                  validator: _mosqueMode == 'new' ? _required : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address / landmark',
                    border: OutlineInputBorder(),
                  ),
                  validator: _mosqueMode == 'new' ? _required : null,
                ),
              ],
              if (_mosqueMode == 'existing') ...[
                const SizedBox(height: 8),
                Text(
                  'Showing ${_availableMosques.length} masjids from ${widget.cityName} listing.',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'New mosque will be submitted for ${widget.cityName}.',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Namaz timings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 10),
              _TimingInputGrid(
                fajrController: _fajrController,
                zoharController: _zoharController,
                asrController: _asrController,
                maghribController: _maghribController,
                ishaController: _ishaController,
                jumaController: _jumaController,
              ),
              const SizedBox(height: 16),
              Text(
                'Eid Namaz timings',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              const Text('Eid timings are annual — update once a year.',
                  style: TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: InkWell(
                  onTap: () async {
                    final p = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                        helpText: 'Eid ul Fitr',
                        builder: (context, child) => MediaQuery(
                            data: MediaQuery.of(context)
                                .copyWith(alwaysUse24HourFormat: false),
                            child: child!));
                    if (p != null) {
                      _eidUlFitrController.text =
                          '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}';
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Eid ul Fitr',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.access_time)),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _eidUlFitrController,
                      builder: (context, value, _) => Text(
                          value.text.isEmpty
                              ? 'Tap to set'
                              : formatStoredTime(value.text),
                          style: TextStyle(
                              color: value.text.isEmpty
                                  ? Colors.black38
                                  : Colors.black87,
                              fontSize: 15)),
                    ),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: InkWell(
                  onTap: () async {
                    final p = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                        helpText: 'Eid ul Azha',
                        builder: (context, child) => MediaQuery(
                            data: MediaQuery.of(context)
                                .copyWith(alwaysUse24HourFormat: false),
                            child: child!));
                    if (p != null) {
                      _eidUlAzhaController.text =
                          '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}';
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Eid ul Azha',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.access_time)),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _eidUlAzhaController,
                      builder: (context, value, _) => Text(
                          value.text.isEmpty
                              ? 'Tap to set'
                              : formatStoredTime(value.text),
                          style: TextStyle(
                              color: value.text.isEmpty
                                  ? Colors.black38
                                  : Colors.black87,
                              fontSize: 15)),
                    ),
                  ),
                )),
              ]),
              const SizedBox(height: 18),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _shareContributorDetails,
                title: const Text('Publicly show my name and number'),
                subtitle: const Text(
                  'Optional: only if you want namazis to contact you.',
                  style: TextStyle(fontSize: 12),
                ),
                onChanged: (value) =>
                    setState(() => _shareContributorDetails = value),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: const Icon(Icons.send),
                label: Text(_submitting ? 'Submitting...' : 'Submit update'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickExistingMosque() async {
    final selected = await showModalBottomSheet<Mosque>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MosquePickerSheet(
        mosques: _availableMosques,
        selectedMosque: _selectedMosque,
        cityName: widget.cityName,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedMosque = selected;
      _syncAreaFromSelectedMosque();
    });
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  Future<void> _ensureFirebase() async {
    if (_firebaseReady) return;
    await Firebase.initializeApp();
    _firebaseReady = true;
  }

  Future<void> _markPhoneVerified(String phone) async {
    final normalized = _normalizeE164Phone(phone);
    if (normalized == null) {
      throw FirebaseAuthException(code: 'invalid-phone-number');
    }
    await OtpSession.saveVerifiedPhone(normalized);
    await _saveContributorNameNow();
    if (!mounted) return;
    setState(() {
      _verifiedPhone = normalized;
      _phoneController.text = normalized;
      _phoneVerified = true;
      _otpSent = true;
      _otpStatusMessage = 'Mobile verified for this session.';
    });
  }

  Future<void> _sendOtp() async {
    final phone = _normalizeE164Phone(_phoneController.text);
    if (phone == null) {
      setState(() =>
          _otpStatusMessage = 'Enter a valid international phone number.');
      return;
    }
    await _saveContributorNameNow();

    setState(() {
      _sendingOtp = true;
      _otpStatusMessage = 'Sending OTP...';
    });

    try {
      await _ensureFirebase();
      _pendingVerificationPhone = phone;
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          await _markPhoneVerified(_firebaseAuthPhone() ?? phone);
        },
        verificationFailed: (error) {
          if (!mounted) return;
          setState(() {
            _otpStatusMessage =
                error.message ?? 'OTP failed. Check Firebase setup.';
          });
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _otpSent = true;
            _otpStatusMessage = 'OTP sent. Enter code to verify.';
          });
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (_) {
      setState(() {
        _otpStatusMessage =
            'Firebase is not configured yet. Add google-services.json and enable Phone Auth.';
      });
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_verificationId == null || _otpController.text.trim().isEmpty) {
      setState(() => _otpStatusMessage = 'Enter the OTP code.');
      return;
    }

    setState(() {
      _verifyingOtp = true;
      _otpStatusMessage = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      final phone = _firebaseAuthPhone() ?? _pendingVerificationPhone;
      if (phone == null) {
        throw FirebaseAuthException(code: 'missing-phone-number');
      }
      await _markPhoneVerified(phone);
    } on FirebaseAuthException catch (error) {
      setState(() {
        _otpStatusMessage = error.message ?? 'Invalid OTP.';
      });
    } finally {
      if (mounted) setState(() => _verifyingOtp = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final contributorName = _cleanContributorName(_nameController.text);
    _nameController.text = contributorName;
    await _saveContributorNameNow();
    if (!mounted) return;
    if (!_phoneVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verify mobile number with OTP first.')),
      );
      return;
    }
    final verifiedPhone =
        _verifiedPhone ?? await OtpSession.loadVerifiedPhone();
    if (!mounted) return;
    if (verifiedPhone == null || _normalizeE164Phone(verifiedPhone) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verify mobile number with OTP again.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final mosqueName = _mosqueMode == 'existing'
        ? _selectedMosque?.name ?? 'Selected mosque'
        : _newMosqueController.text.trim();

    try {
      await _ensureFirebase();
      final db = FirebaseFirestore.instance;
      final submittedTimings = <String, String>{
        if (normalizePrayerTimingInput('fajr', _fajrController.text) != null)
          'fajr': normalizePrayerTimingInput('fajr', _fajrController.text)!,
        if (normalizePrayerTimingInput('zohar', _zoharController.text) != null)
          'zohar': normalizePrayerTimingInput('zohar', _zoharController.text)!,
        if (normalizePrayerTimingInput('asr', _asrController.text) != null)
          'asr': normalizePrayerTimingInput('asr', _asrController.text)!,
        if (normalizePrayerTimingInput('maghrib', _maghribController.text) !=
            null)
          'maghrib':
              normalizePrayerTimingInput('maghrib', _maghribController.text)!,
        if (normalizePrayerTimingInput('isha', _ishaController.text) != null)
          'isha': normalizePrayerTimingInput('isha', _ishaController.text)!,
        if (normalizePrayerTimingInput('juma', _jumaController.text) != null)
          'juma': normalizePrayerTimingInput('juma', _jumaController.text)!,
        if (normalizeTimingInput(_eidUlFitrController.text) != null)
          'eid_ul_fitr': normalizeTimingInput(_eidUlFitrController.text)!,
        if (normalizeTimingInput(_eidUlAzhaController.text) != null)
          'eid_ul_azha': normalizeTimingInput(_eidUlAzhaController.text)!,
      };
      if (submittedTimings.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please enter at least one prayer time.')),
        );
        setState(() => _submitting = false);
        return;
      }

      final timingData = {
        if (_shareContributorDetails)
          'timing_verified_by_name': contributorName,
        if (_shareContributorDetails) 'timing_verified_by_phone': verifiedPhone,
        'timing_verification_status': 'source_verified',
        'contributor_contact_shared': _shareContributorDetails,
        'verified_by_phone_private': verifiedPhone,
        'verified_by_name_private': contributorName,
        'role': _role,
        'maslak': _maslak,
        'city': _cityController.text.trim(),
        'area': _areaController.text.trim(),
        'timing_updated_at': FieldValue.serverTimestamp(),
        if (_selectedMosque?.placeId != null)
          'place_id': _selectedMosque!.placeId!,
      };

      final city = _cityController.text.trim();
      final mosqueDocId = _mosqueDocId(mosqueName, city);
      final mosqueRef = db.collection('mosques').doc(mosqueDocId);
      if (_mosqueMode == 'existing' && _selectedMosque != null) {
        final updateData = {
          ...timingData,
          'name': mosqueName,
          'city': city,
          'timings': submittedTimings,
        };
        await mosqueRef.set({
          'address': _selectedMosque?.address ?? '',
          'latitude': _selectedMosque?.latitude,
          'longitude': _selectedMosque?.longitude,
          ...updateData,
        }, SetOptions(merge: true));
      } else {
        await mosqueRef.set({
          'name': mosqueName,
          'city': city,
          'address': _addressController.text.trim(),
          'timings': submittedTimings,
          ...timingData,
        }, SetOptions(merge: true));
      }

      await db.collection('contribution_logs').add({
        'name': contributorName,
        'phone': verifiedPhone,
        'uid': FirebaseAuth.instance.currentUser?.uid,
        'city': _cityController.text.trim(),
        'mosque_name': mosqueName,
        'mode': _mosqueMode,
        'created_at': FieldValue.serverTimestamp(),
      });

      final contributorUid = FirebaseAuth.instance.currentUser?.uid;
      if (contributorUid == null || contributorUid.isEmpty) {
        throw FirebaseAuthException(code: 'missing-user-id');
      }
      final topRef = db.collection('top_contributors').doc(contributorUid);
      await db.runTransaction((txn) async {
        final snap = await txn.get(topRef);
        final current = (snap.data()?['score'] as num?)?.toInt() ?? 0;
        txn.set(
            topRef,
            {
              'name': contributorName,
              'score': current + 1,
              'updated_at': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$mosqueName updated successfully! ✅')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not submit. Check Firebase setup and internet.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _normalizeE164Phone(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized)) {
      return normalized;
    }
    return null;
  }

  String? _firebaseAuthPhone() {
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    return phone == null ? null : _normalizeE164Phone(phone);
  }
}

class _MosqueSelectorField extends StatelessWidget {
  const _MosqueSelectorField({
    required this.selectedMosque,
    required this.mosqueCount,
    required this.onTap,
  });

  final Mosque? selectedMosque;
  final int mosqueCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mosque = selectedMosque;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Select mosque from current listing',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.search),
        ),
        child: mosque == null
            ? Text(
                mosqueCount == 0
                    ? 'No mosque in current listing'
                    : 'Search $mosqueCount masjids',
                style: const TextStyle(color: Colors.black54),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mosque.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${mosque.area} - ${_MosqueCard._distanceLabel(mosque)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MosquePickerSheet extends StatefulWidget {
  const _MosquePickerSheet({
    required this.mosques,
    required this.selectedMosque,
    required this.cityName,
  });

  final List<Mosque> mosques;
  final Mosque? selectedMosque;
  final String cityName;

  @override
  State<_MosquePickerSheet> createState() => _MosquePickerSheetState();
}

class _MosquePickerSheetState extends State<_MosquePickerSheet> {
  final _search = TextEditingController();
  late List<Mosque> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.mosques;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _filtered = widget.mosques.where((mosque) {
        if (query.isEmpty) return true;
        return mosque.name.toLowerCase().contains(query) ||
            mosque.area.toLowerCase().contains(query) ||
            mosque.address.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText:
                      'Search ${widget.cityName} mosques, areas or landmarks',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: _onSearch,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filtered.length} of ${widget.mosques.length} masjids',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('No mosque found.'))
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final mosque = _filtered[index];
                        final selected =
                            mosque.name == widget.selectedMosque?.name &&
                                mosque.area == widget.selectedMosque?.area;
                        return ListTile(
                          leading: Icon(
                            selected ? Icons.check_circle : Icons.mosque,
                            color: const Color(0xFF0F7C68),
                          ),
                          title: Text(
                            mosque.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.w900 : FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${mosque.area} - ${_MosqueCard._distanceLabel(mosque)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).pop(mosque),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _OtpVerificationPanel extends StatelessWidget {
  const _OtpVerificationPanel({
    required this.otpController,
    required this.otpSent,
    required this.phoneVerified,
    required this.sendingOtp,
    required this.verifyingOtp,
    required this.statusMessage,
    required this.onSendOtp,
    required this.onVerifyOtp,
  });

  final TextEditingController otpController;
  final bool otpSent;
  final bool phoneVerified;
  final bool sendingOtp;
  final bool verifyingOtp;
  final String? statusMessage;
  final VoidCallback onSendOtp;
  final VoidCallback onVerifyOtp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                phoneVerified ? Icons.verified : Icons.sms,
                color: const Color(0xFF0F7C68),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  phoneVerified ? 'Mobile verified' : 'OTP verification',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: sendingOtp || phoneVerified ? null : onSendOtp,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F7C68),
                  disabledBackgroundColor: Colors.black26,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                icon: sendingOtp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_to_mobile),
                label: Text(
                  sendingOtp
                      ? 'Sending...'
                      : otpSent
                          ? 'Resend OTP'
                          : 'Send OTP',
                ),
              ),
            ],
          ),
          if (otpSent && !phoneVerified) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'OTP code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: verifyingOtp ? null : onVerifyOtp,
                  child: Text(verifyingOtp ? 'Checking...' : 'Verify'),
                ),
              ],
            ),
          ],
          if (statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              statusMessage!,
              style: TextStyle(
                color: phoneVerified ? const Color(0xFF0F7C68) : Colors.black54,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimingInputGrid extends StatefulWidget {
  const _TimingInputGrid({
    required this.fajrController,
    required this.zoharController,
    required this.asrController,
    required this.maghribController,
    required this.ishaController,
    required this.jumaController,
  });

  final TextEditingController fajrController;
  final TextEditingController zoharController;
  final TextEditingController asrController;
  final TextEditingController maghribController;
  final TextEditingController ishaController;
  final TextEditingController jumaController;

  @override
  State<_TimingInputGrid> createState() => _TimingInputGridState();
}

class _TimingInputGridState extends State<_TimingInputGrid> {
  Future<void> _pick(
      BuildContext ctx, TextEditingController ctrl, String label) async {
    final p = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay.now(),
      helpText: label,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (p != null) {
      ctrl.text =
          '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = [
      ('Fajr', 'fajr', widget.fajrController),
      ('Zohar', 'zohar', widget.zoharController),
      ('Asr', 'asr', widget.asrController),
      ('Maghrib', 'maghrib', widget.maghribController),
      ('Isha', 'isha', widget.ishaController),
      ('Juma', 'juma', widget.jumaController),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: fields.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 76,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final field = fields[index];
        return InkWell(
          onTap: () => _pick(context, field.$3, field.$1),
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: field.$1,
              border: const OutlineInputBorder(),
              suffixIcon: const Icon(Icons.access_time),
            ),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: field.$3,
              builder: (context, value, _) => Text(
                value.text.isEmpty
                    ? 'Tap to set'
                    : formatPrayerStoredTime(field.$2, value.text),
                style: TextStyle(
                  color: value.text.isEmpty ? Colors.black38 : Colors.black87,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RewardsPreviewCard extends StatelessWidget {
  const _RewardsPreviewCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE4B4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, color: Color(0xFFB8860B)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Contributor Rewards, Stars and Certificates',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(onPressed: onOpen, child: const Text('Open')),
        ],
      ),
    );
  }
}

int _readContributorInt(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
  }
  return 0;
}

String _cleanContributorName(Object? value) {
  final name = value?.toString().trim() ?? '';
  return name.isEmpty ? 'Namaz Volunteer' : name;
}

const _namazAndroidAppUrl =
    'https://play.google.com/store/apps/details?id=com.food4u.namaznearme';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key, required this.onBackfill});

  final Future<void> Function() onBackfill;

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  static const _targetScore = 150;
  final _certificateKey = GlobalKey();
  var _sharingCertificate = false;

  @override
  void initState() {
    super.initState();
    widget.onBackfill();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contributor Rewards')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('top_contributors')
                .orderBy('score', descending: true)
                .limit(20)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const _EmptyRewardsState();
              }
              final topContributor = docs.first.data();
              final topName = _cleanContributorName(topContributor['name']);
              final topScore = _readContributorInt(topContributor, ['score']);
              final masjidCount = _readContributorInt(
                topContributor,
                ['masjids', 'masjidCount', 'mosques'],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ContributorHeroCard(
                    name: topName,
                    score: topScore,
                    masjidCount: masjidCount,
                    rank: 1,
                  ),
                  const SizedBox(height: 16),
                  const _RewardsSectionTitle('Your Progress'),
                  _ProgressRewardCard(score: topScore, target: _targetScore),
                  const SizedBox(height: 16),
                  const _RewardsSectionTitle('Achievements'),
                  _AchievementsGrid(score: topScore, masjidCount: masjidCount),
                  const SizedBox(height: 16),
                  const _RewardsSectionTitle('Leaderboard'),
                  for (var i = 0; i < docs.length; i++)
                    _LeaderboardTile(
                      rank: i + 1,
                      name: _cleanContributorName(docs[i].data()['name']),
                      score: _readContributorInt(docs[i].data(), ['score']),
                    ),
                  const SizedBox(height: 18),
                  _CertificateTemplateCard(
                    name: topName,
                    score: topScore,
                    masjidCount: masjidCount,
                    isSharing: _sharingCertificate,
                    onPreviewCertificate: () =>
                        _openCertificatePreview(topName, topScore, masjidCount),
                    onShareWhatsApp: () => _shareCertificateText(topName),
                    onCopyLink: _copyAppLink,
                    onOpenAppLink: _openAppLink,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _certificateShareText(String name) {
    return 'Jazakallah Khair to $name for helping keep masjid namaz timings accurate on Namaz Near Me.\n\nDownload Namaz Near Me:\n$_namazAndroidAppUrl';
  }

  Future<void> _shareCertificate(String name) async {
    if (_sharingCertificate) return;
    setState(() => _sharingCertificate = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final boundary = _certificateKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Certificate is not ready yet.');
      }
      final image = await boundary.toImage(pixelRatio: 4);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null) {
        throw StateError('Could not render certificate.');
      }
      final directory = await getTemporaryDirectory();
      final safeName = name
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final file = File(
        '${directory.path}/namaz-near-me-certificate-${safeName.isEmpty ? 'contributor' : safeName}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          title: 'Namaz Near Me Volunteer Appreciation',
          subject: 'Namaz Near Me Volunteer Appreciation',
          text: _certificateShareText(name),
          files: [
            XFile(
              file.path,
              mimeType: 'image/png',
              name: 'namaz-near-me-volunteer-certificate.png',
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Certificate share failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _sharingCertificate = false);
    }
  }

  Future<void> _shareCertificateText(String name) async {
    await SharePlus.instance.share(
      ShareParams(
        title: 'Namaz Near Me',
        text: _certificateShareText(name),
      ),
    );
  }

  Future<void> _copyAppLink() async {
    await Clipboard.setData(const ClipboardData(text: _namazAndroidAppUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('App download link copied.')),
    );
  }

  Future<void> _openAppLink() async {
    await launchUrl(
      Uri.parse(_namazAndroidAppUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openCertificatePreview(
    String name,
    int score,
    int masjidCount,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: .82,
            minChildSize: .55,
            maxChildSize: .95,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF6FBF9),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCCD8D5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Certificate Preview',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    RepaintBoundary(
                      key: _certificateKey,
                      child: _ShareableCertificate(
                        name: name,
                        score: score,
                        masjidCount: masjidCount,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _sharingCertificate
                          ? null
                          : () => _shareCertificate(name),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share Certificate'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F7C68),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _shareCertificateText(name),
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('WhatsApp'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openAppLink,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('App Link'),
                          ),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: _copyAppLink,
                      icon: const Icon(Icons.link),
                      label: const Text('Copy Android download link'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _EmptyRewardsState extends StatelessWidget {
  const _EmptyRewardsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFAF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6EEE8)),
      ),
      child: const Column(
        children: [
          Icon(Icons.workspace_premium, color: Color(0xFF0F7C68), size: 42),
          SizedBox(height: 10),
          Text('No contributors yet.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          SizedBox(height: 6),
          Text(
            'Approved timing updates will appear here as community rewards.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RewardsSectionTitle extends StatelessWidget {
  const _RewardsSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF555A60),
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

class _ContributorHeroCard extends StatelessWidget {
  const _ContributorHeroCard({
    required this.name,
    required this.score,
    required this.masjidCount,
    required this.rank,
  });

  final String name;
  final int score;
  final int masjidCount;
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F7C68), Color(0xFF128E78)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F7C68).withValues(alpha: .18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _InitialsAvatar(name: name, radius: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Top Contributor · Moradabad',
                      style: TextStyle(
                        color: Color(0xCCEFFFFB),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _HeroStat(value: '$score', label: 'Updates')),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStat(
                  value: masjidCount == 0 ? '—' : '$masjidCount',
                  label: 'Masjids',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _HeroStat(value: '#$rank', label: 'Rank')),
            ],
          ),
        ],
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name, required this.radius});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFBDEEE4).withValues(alpha: .42),
      child: Text(
        initials.isEmpty ? 'NN' : initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xDDEFFFFB),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRewardCard extends StatelessWidget {
  const _ProgressRewardCard({required this.score, required this.target});

  final int score;
  final int target;

  @override
  Widget build(BuildContext context) {
    final progress = (score / target).clamp(0.0, 1.0);
    final remaining = (target - score).clamp(0, target);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECEF)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE9A8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Gold Contributor',
                  style: TextStyle(
                    color: Color(0xFF80620A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Diamond at 150 ↗',
                style: TextStyle(
                  color: Color(0xFF7A7F85),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              color: const Color(0xFF0F7C68),
              backgroundColor: const Color(0xFFE8ECEF),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$score updates',
                style: const TextStyle(
                  color: Color(0xFF8A8F95),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                remaining == 0 ? 'Diamond unlocked' : '$remaining needed',
                style: const TextStyle(
                  color: Color(0xFF8A8F95),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AchievementsGrid extends StatelessWidget {
  const _AchievementsGrid({required this.score, required this.masjidCount});

  final int score;
  final int masjidCount;

  @override
  Widget build(BuildContext context) {
    final items = [
      _AchievementData(
        icon: '🕌',
        title: 'First Masjid',
        subtitle: masjidCount > 0 ? 'Completed' : 'Pending',
        completed: masjidCount > 0,
      ),
      _AchievementData(
        icon: '⭐',
        title: '10 Updates',
        subtitle: score >= 10 ? 'Completed' : '${10 - score} remaining',
        completed: score >= 10,
      ),
      _AchievementData(
        icon: '🏅',
        title: '100 Updates',
        subtitle: score >= 100 ? 'Completed' : '${100 - score} remaining',
        completed: score >= 100,
      ),
      _AchievementData(
        icon: '💎',
        title: '150 Updates',
        subtitle: score >= 150 ? 'Completed' : '${150 - score} remaining',
        completed: score >= 150,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 66,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) => _AchievementTile(items[index]),
    );
  }
}

class _AchievementData {
  const _AchievementData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.completed,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool completed;
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile(this.data);

  final _AchievementData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: data.completed ? const Color(0xFFE0F6EF) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: data.completed
              ? const Color(0xFF6FCBBB)
              : const Color(0xFFE8ECEF),
        ),
      ),
      child: Row(
        children: [
          Text(data.icon, style: const TextStyle(fontSize: 21)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: data.completed
                        ? const Color(0xFF0F7C68)
                        : const Color(0xFF3F444A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  data.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7A7F85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({
    required this.rank,
    required this.name,
    required this.score,
  });

  final int rank;
  final String name;
  final int score;

  @override
  Widget build(BuildContext context) {
    final stars = (score ~/ 3).clamp(1, 5);
    final rankColor = switch (rank) {
      1 => const Color(0xFFD99A00),
      2 => const Color(0xFF8A8F95),
      3 => const Color(0xFFC56F32),
      _ => const Color(0xFF0F7C68),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECEF)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: rankColor,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _InitialsAvatar(name: name, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$score pts',
                style: const TextStyle(
                  color: Color(0xFF0F7C68),
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '★' * stars,
                style: const TextStyle(color: Colors.amber, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CertificateTemplateCard extends StatelessWidget {
  const _CertificateTemplateCard({
    required this.name,
    required this.score,
    required this.masjidCount,
    required this.isSharing,
    required this.onPreviewCertificate,
    required this.onShareWhatsApp,
    required this.onCopyLink,
    required this.onOpenAppLink,
  });

  final String name;
  final int score;
  final int masjidCount;
  final bool isSharing;
  final VoidCallback onPreviewCertificate;
  final VoidCallback onShareWhatsApp;
  final VoidCallback onCopyLink;
  final VoidCallback onOpenAppLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _RewardsSectionTitle('Certificate'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8ECEF)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F6EF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.workspace_premium,
                      color: Color(0xFF0F7C68),
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Volunteer Appreciation',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '$name · $score updates',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF657078),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isSharing ? null : onPreviewCertificate,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Preview & Share Certificate'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F7C68),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onShareWhatsApp,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpenAppLink,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('App Link'),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: onCopyLink,
                icon: const Icon(Icons.link),
                label: const Text('Copy Android download link'),
              ),
              const Text(
                'Tip: Share Certificate opens the phone share sheet, so users can post it to WhatsApp Status, Facebook, Instagram, or save it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7A7F85), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShareableCertificate extends StatelessWidget {
  const _ShareableCertificate({
    required this.name,
    required this.score,
    required this.masjidCount,
  });

  final String name;
  final int score;
  final int masjidCount;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dateLabel = '${today.day} ${_monthName(today.month)} ${today.year}';
    return AspectRatio(
      aspectRatio: 1.24,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 620,
          height: 500,
          child: _CertificateCanvas(
            name: name,
            score: score,
            masjidCount: masjidCount,
            dateLabel: dateLabel,
          ),
        ),
      ),
    );
  }

  static String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }
}

class _CertificateCanvas extends StatelessWidget {
  const _CertificateCanvas({
    required this.name,
    required this.score,
    required this.masjidCount,
    required this.dateLabel,
  });

  final String name;
  final int score;
  final int masjidCount;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE8EA), width: 1.5),
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -18,
            top: -20,
            child: _CertificateShape(
              color: Color(0xFF2D93C7),
              size: 116,
              angle: .28,
              opacity: .70,
            ),
          ),
          const Positioned(
            right: 56,
            top: -22,
            child: _CertificateShape(
              color: Color(0xFF32B7AC),
              size: 82,
              angle: -.64,
              opacity: .55,
            ),
          ),
          const Positioned(
            left: -54,
            bottom: -34,
            child: _CertificateShape(
              color: Color(0xFF2D93C7),
              size: 142,
              angle: .18,
              opacity: .68,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/images/namaz-near-me-icon.png',
                        width: 42,
                        height: 42,
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NAMAZ NEAR ME',
                          style: TextStyle(
                            color: Color(0xFF59BFAF),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                          ),
                        ),
                        Text(
                          'Nearby masjids and jamaat timings',
                          style: TextStyle(
                            color: Color(0xFF8A939B),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Volunteer',
                  style: TextStyle(
                    color: Color(0xFF1B7DC3),
                    fontSize: 58,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w400,
                    letterSpacing: .5,
                  ),
                ),
                const Text(
                  'A P P R E C I A T I O N',
                  style: TextStyle(
                    color: Color(0xFF35ADA3),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'AWARDED TO',
                  style: TextStyle(
                    color: Color(0xFF7D858C),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 7),
                Container(height: 1.5, color: const Color(0xFFD6EDF8)),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1B7DC3),
                    fontSize: 42,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Container(height: 1.2, color: const Color(0xFFD6EDF8)),
                const SizedBox(height: 8),
                const Text(
                  'for outstanding contribution to the Muslim community through masjid updates on Namaz Near Me, helping people reach jamaat on time.',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF3E444A),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'May Allah accept this as sadqa-e-jariya. Ameen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF3E444A),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _CertificateFooterBlock(
                      title: 'DATE',
                      value: dateLabel,
                    ),
                    const Spacer(),
                    _CertificateSeal(score: score, masjidCount: masjidCount),
                    const Spacer(),
                    const _CertificateFooterBlock(
                      title: 'PRESENTED BY',
                      value: 'FOODOMATIC®\nMoradabad',
                      alignRight: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CertificateShape extends StatelessWidget {
  const _CertificateShape({
    required this.color,
    required this.size,
    required this.angle,
    required this.opacity,
  });

  final Color color;
  final double size;
  final double angle;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: size,
        height: size * .72,
        decoration: BoxDecoration(
          color: color.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _CertificateFooterBlock extends StatelessWidget {
  const _CertificateFooterBlock({
    required this.title,
    required this.value,
    this.alignRight = false,
  });

  final String title;
  final String value;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 98,
      child: Column(
        crossAxisAlignment:
            alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(height: 1.2, color: const Color(0xFFB9CDD0)),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: alignRight ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: Color(0xFF8B949C),
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            textAlign: alignRight ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: Color(0xFF343A40),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              height: 1.12,
            ),
          ),
        ],
      ),
    );
  }
}

class _CertificateSeal extends StatelessWidget {
  const _CertificateSeal({required this.score, required this.masjidCount});

  final int score;
  final int masjidCount;

  @override
  Widget build(BuildContext context) {
    final badgeLabel = score >= 150
        ? 'DIAMOND'
        : masjidCount > 0
            ? 'GOLD'
            : 'STARTER';
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF9F7),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF2AB5A8), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F7C68).withValues(alpha: .14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipOval(
            child: Image.asset(
              'assets/images/namaz-near-me-icon.png',
              width: 34,
              height: 34,
            ),
          ),
          Positioned(
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE9A8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeLabel,
                style: const TextStyle(
                  color: Color(0xFF80620A),
                  fontSize: 5.6,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationPanel extends StatelessWidget {
  const _LocationPanel({
    required this.radiusKm,
    required this.loadingLocation,
    required this.isCurrentLocation,
    required this.onRefreshLocation,
    required this.onRadiusChanged,
    required this.cityName,
  });

  final int radiusKm;
  final bool loadingLocation;
  final bool isCurrentLocation;
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2 km')),
                ButtonSegment(value: 10, label: Text('10 km')),
                ButtonSegment(value: 25, label: Text('All')),
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
  const _NamazFilter({
    required this.selectedNamaz,
    required this.onSelected,
  });

  final String selectedNamaz;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = {
      'all': 'All',
      'fajr': 'Fajr',
      'zohar': 'Zohar',
      'asr': 'Asr',
      'maghrib': 'Maghrib',
      'isha': 'Isha',
      'juma': 'Juma',
      'eid': 'Eid',
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((entry) {
        return ChoiceChip(
          label: Text(entry.value),
          selected: selectedNamaz == entry.key,
          onSelected: (_) => onSelected(entry.key),
        );
      }).toList(),
    );
  }
}

class _MosqueCard extends StatelessWidget {
  const _MosqueCard({
    required this.result,
    required this.cityName,
    required this.isFavourite,
    required this.onToggleFavourite,
  });

  final MosqueResult result;
  final String cityName;
  final bool isFavourite;
  final VoidCallback onToggleFavourite;

  @override
  Widget build(BuildContext context) {
    final mosque = result.mosque;
    final next = result.nextJamaat;
    final sourcePhone = mosque.timingVerifiedByPhone;
    final updateStamp = _formatUpdatedAt(mosque.timingUpdatedAt);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    mosque.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (mosque.isVerified)
                  const Icon(Icons.verified, color: Color(0xFF0F7C68)),
                IconButton(
                  tooltip: isFavourite ? 'Remove favourite' : 'Add favourite',
                  onPressed: onToggleFavourite,
                  icon: Icon(
                    isFavourite ? Icons.star : Icons.star_border,
                    color: isFavourite ? Colors.amber : Colors.black38,
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
                        const Text('starts in',
                            style: TextStyle(
                                fontSize: 10, color: Color(0xFF0F6E56))),
                        Text(next.startsIn,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F6E56),
                            )),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFD700)),
                ),
                child: Row(children: [
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
                ]),
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
                _TimingCell(label: 'Fajr', value: mosque.timings.fajr),
                _TimingCell(label: 'Zohar', value: mosque.timings.zohar),
                _TimingCell(label: 'Asr', value: mosque.timings.asr),
                _TimingCell(label: 'Maghrib', value: mosque.timings.maghrib),
                _TimingCell(label: 'Isha', value: mosque.timings.isha),
                _TimingCell(label: 'Juma', value: mosque.timings.juma),
                if (_shouldShowEid(EidType.eidUlFitr) &&
                    mosque.timings.eidUlFitr != null)
                  _TimingCell(
                      label: 'Eid ul Fitr', value: mosque.timings.eidUlFitr),
                if (_shouldShowEid(EidType.eidUlAdha) &&
                    mosque.timings.eidUlAzha != null)
                  _TimingCell(
                      label: 'Eid ul Azha', value: mosque.timings.eidUlAzha),
              ],
            ),
            const SizedBox(height: 12),
            // Verified badge + last update
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE1F5EE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 12, color: Color(0xFF0F6E56)),
                      SizedBox(width: 3),
                      Text('Verified',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF0F6E56),
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(updateStamp,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black45)),
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
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text('Navigate',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 8),
                _IconRoundBtn(
                    icon: Icons.chat_bubble_outline,
                    onTap: sourcePhone != null
                        ? () => _openWhatsApp(sourcePhone)
                        : null),
                const SizedBox(width: 6),
                _IconRoundBtn(
                    icon: Icons.phone_outlined,
                    onTap: sourcePhone != null
                        ? () => _callPhone(sourcePhone)
                        : null),
                const SizedBox(width: 6),
                _IconRoundBtn(
                    icon: Icons.share_outlined,
                    onTap: () => _shareTimingOnWhatsApp(mosque, next)),
                const SizedBox(width: 6),
                _IconRoundBtn(
                    icon: Icons.more_horiz,
                    onTap: () => _openMoreSheet(context, mosque, next)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static bool _shouldShowEid(EidType type) {
    final window = getEidWindowStatus(DateTime.now());
    return window.type == type;
  }

  static String? _eidBannerText() {
    final window = getEidWindowStatus(DateTime.now());
    if (window.type == EidType.none) return null;
    final name =
        window.type == EidType.eidUlFitr ? 'Eid ul Fitr' : 'Eid ul Adha';
    if (window.isEidDay) return 'Eid Mubarak! $name aaj hai';
    if (window.isBeforeEid) {
      final d = window.daysUntilEid;
      return '$name aane mein $d din baki';
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
    return value[0].toUpperCase() + value.substring(1);
  }

  static Future<void> _openMaps(Mosque mosque) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${mosque.latitude},${mosque.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> _openWhatsApp(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> _callPhone(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('tel:+$digits');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> _shareTimingOnWhatsApp(
      Mosque mosque, NextJamaat? next) async {
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
      BuildContext context, Mosque mosque) async {
    var selectedNamaz = 'fajr';
    var before = 10;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, MediaQuery.of(context).viewPadding.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Set reminder - ${mosque.name}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedNamaz,
                  decoration: const InputDecoration(
                    labelText: 'Namaz',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'fajr', child: Text('Fajr')),
                    DropdownMenuItem(value: 'zohar', child: Text('Zohar')),
                    DropdownMenuItem(value: 'asr', child: Text('Asr')),
                    DropdownMenuItem(value: 'maghrib', child: Text('Maghrib')),
                    DropdownMenuItem(value: 'isha', child: Text('Isha')),
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
                      final jamaat =
                          _nextDateTimeForStoredTime(selectedNamaz, storedTime);
                      final id =
                          (_mosqueKey(mosque.name).hashCode.abs() % 100000) +
                              selectedNamaz.hashCode.abs() % 1000 +
                              before;
                      await NotificationService.instance.schedulePrayerReminder(
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
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
    return target;
  }
}

class _IconRoundBtn extends StatelessWidget {
  const _IconRoundBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
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
        child: Icon(icon, size: 18, color: const Color(0xFF555555)),
      ),
    );
  }
}

void _openMoreSheet(BuildContext context, Mosque mosque, NextJamaat? next) {
  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.alarm_add),
            title: const Text('Set Reminder'),
            onTap: () {
              Navigator.pop(context);
              _MosqueCard._openReminderSheet(context, mosque);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Suggest edit'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SuggestEditScreen(mosque: mosque),
              ));
            },
          ),
        ],
      ),
    ),
  );
}

class _TimingCell extends StatelessWidget {
  const _TimingCell({required this.label, required this.value});
  final String label;
  final String? value;
  @override
  Widget build(BuildContext context) {
    final display =
        value == null ? '—' : formatPrayerStoredTime(_prayerKey(label), value!);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF888888)),
              maxLines: 1),
          Text(display,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111111)),
              maxLines: 1),
        ],
      ),
    );
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

  final match =
      RegExp(r'^(\d{1,2})(?::(\d{1,2}))?\s*(AM|PM)?$').firstMatch(text);
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

  if (key == 'fajr') {
    if (hour == 12) hour = 0;
    if (hour > 12) hour -= 12;
  } else if (_forcePmPrayerKeys.contains(key)) {
    if (hour < 12) hour += 12;
  }

  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

const _forcePmPrayerKeys = {'zohar', 'asr', 'maghrib', 'isha', 'juma'};

String _prayerKey(String value) {
  final key = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  if (key == 'zuhr' || key == 'dhuhr' || key == 'zuhur') return 'zohar';
  if (key == 'jumma' || key == 'jumuah') return 'juma';
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
      onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final q = query.toLowerCase();
    final filtered = results
        .where((r) =>
            r.mosque.name.toLowerCase().contains(q) ||
            r.mosque.area.toLowerCase().contains(q) ||
            r.mosque.address.toLowerCase().contains(q))
        .toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child:
              Text('No mosque found.', style: TextStyle(color: Colors.black54)),
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
          title: Text(mosque.name,
              style: const TextStyle(fontWeight: FontWeight.w700)),
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
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text('No mosques found in this radius.'),
      ),
    );
  }
}
