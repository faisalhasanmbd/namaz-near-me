import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has verified their phone number.
///
/// Session is persisted via SharedPreferences so it survives app restarts.
/// Phone numbers are stored only as a verified-session flag; Firebase Auth
/// remains the authoritative identity source.
class OtpSession {
  OtpSession._();

  static const _keyPhone = 'otp_verified_phone';
  static const _keyVerifiedAt = 'otp_verified_at_ms';
  static const _keyName = 'contributor_name';
  static const _validFor = Duration(days: 7);

  // In-memory cache populated by loadVerifiedPhone(); used by isVerifiedInMemory.
  static String? _cachedPhone;
  static DateTime? _cachedAt;

  /// Returns the verified phone number if the persisted session is still valid.
  static Future<String?> loadVerifiedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString(_keyPhone);
    final atMs = prefs.getInt(_keyVerifiedAt);
    if (phone != null && atMs != null) {
      final verifiedAt = DateTime.fromMillisecondsSinceEpoch(atMs);
      if (DateTime.now().difference(verifiedAt) < _validFor) {
        _cachedPhone = phone;
        _cachedAt = verifiedAt;
        return phone;
      }
      await _clearPrefs(prefs);
    }
    _cachedPhone = null;
    _cachedAt = null;
    return null;
  }

  /// Call this after a successful OTP verification.
  static Future<void> saveVerifiedPhone(String phone) async {
    final now = DateTime.now();
    _cachedPhone = phone;
    _cachedAt = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPhone, phone);
    await prefs.setInt(_keyVerifiedAt, now.millisecondsSinceEpoch);
  }

  /// Saves the contributor display name. Independent of the phone session —
  /// name is kept until explicitly changed, no expiry.
  static Future<void> saveName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, trimmed);
  }

  /// Returns the last saved contributor name, or null if never saved.
  static Future<String?> loadName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyName);
  }

  /// Explicitly clear the session.
  static Future<void> clear() async {
    _cachedPhone = null;
    _cachedAt = null;
    final prefs = await SharedPreferences.getInstance();
    await _clearPrefs(prefs);
  }

  static Future<void> _clearPrefs(SharedPreferences prefs) async {
    await prefs.remove(_keyPhone);
    await prefs.remove(_keyVerifiedAt);
    // Name is intentionally NOT cleared — it is device-level identity,
    // not tied to a single OTP session.
  }

  /// Whether a verified session is active right now (uses in-memory cache).
  /// Call [loadVerifiedPhone] at app start to warm the cache.
  static bool get isVerifiedInMemory =>
      _cachedPhone != null &&
      _cachedAt != null &&
      DateTime.now().difference(_cachedAt!) < _validFor;
}
