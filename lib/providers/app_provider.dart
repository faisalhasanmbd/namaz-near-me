import 'dart:collection';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/otp_session.dart';

/// Central app state. Wrap the widget tree with ChangeNotifierProvider<AppState>
/// and read with context.watch<AppState>() or context.read<AppState>().
class AppState extends ChangeNotifier {
  // ── City ──────────────────────────────────────────────────────────────────

  static const _keyCity = 'selected_city';

  String _selectedCity = 'Moradabad';
  String get selectedCity => _selectedCity;

  Future<void> loadCity() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyCity);
    if (saved != null && saved.isNotEmpty) {
      _selectedCity = saved;
      notifyListeners();
    }
  }

  Future<void> setCity(String city) async {
    if (city == _selectedCity) return;
    _selectedCity = city;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCity, city);
  }

  // ── OTP / verified phone ──────────────────────────────────────────────────

  String? _verifiedPhone;
  String? _contributorName;

  String? get verifiedPhone => _verifiedPhone;
  String? get contributorName => _contributorName;
  bool get isPhoneVerified => OtpSession.isVerifiedInMemory;

  Future<void> loadOtpSession() async {
    _verifiedPhone = await OtpSession.loadVerifiedPhone();
    // Load name from OtpSession; fall back to Firebase Auth display name
    final saved = await OtpSession.loadName();
    _contributorName = (saved != null && saved.isNotEmpty)
        ? saved
        : FirebaseAuth.instance.currentUser?.displayName;
    notifyListeners();
  }

  Future<void> markPhoneVerified(String phone) async {
    await OtpSession.saveVerifiedPhone(phone);
    _verifiedPhone = phone;
    notifyListeners();
  }

  Future<void> setContributorName(String name) async {
    await OtpSession.saveName(name);
    _contributorName = name.trim().isEmpty ? null : name.trim();
    notifyListeners();
  }

  Future<void> clearOtpSession() async {
    await OtpSession.clear();
    _verifiedPhone = null;
    notifyListeners();
  }

  // ── Favourites ────────────────────────────────────────────────────────────

  static const _keyFavourites = 'favourite_keys';

  final Set<String> _favouriteKeys = {};
  Set<String> get favouriteKeys => UnmodifiableSetView(_favouriteKeys);

  Future<void> loadFavourites() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_keyFavourites) ?? [];
    _favouriteKeys
      ..clear()
      ..addAll(saved);
    notifyListeners();
  }

  Future<void> toggleFavourite(String key) async {
    if (_favouriteKeys.contains(key)) {
      _favouriteKeys.remove(key);
    } else {
      _favouriteKeys.add(key);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyFavourites, _favouriteKeys.toList());
  }

  bool isFavourite(String key) => _favouriteKeys.contains(key);

  // ── Pinned mosque ─────────────────────────────────────────────────────────

  static const _keyPinnedMosque = 'pinned_mosque_key';

  String? _pinnedMosqueKey;
  String? get pinnedMosqueKey => _pinnedMosqueKey;

  Future<void> loadPinnedMosque() async {
    final prefs = await SharedPreferences.getInstance();
    _pinnedMosqueKey = prefs.getString(_keyPinnedMosque);
    notifyListeners();
  }

  Future<void> setPinnedMosque(String? key) async {
    _pinnedMosqueKey = key;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (key == null) {
      await prefs.remove(_keyPinnedMosque);
    } else {
      await prefs.setString(_keyPinnedMosque, key);
    }
  }

  bool isPinned(String key) => _pinnedMosqueKey == key;

  // ── Bootstrap (call once in main before runApp) ───────────────────────────

  Future<void> init() async {
    await Future.wait([
      loadCity(),
      loadOtpSession(),
      loadFavourites(),
      loadPinnedMosque(),
    ]);
  }
}
