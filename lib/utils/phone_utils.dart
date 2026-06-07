import 'dart:io';

class PhoneUtils {
  PhoneUtils._();

  // Returns E.164 phone number or null if invalid.
  // countryCode: 2-letter ISO code ('IN', 'PK', etc.) — auto-detected if omitted.
  static String? normalize(String raw, {String? countryCode}) {
    final s = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (s.isEmpty) return null;
    if (RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(s)) return s;
    final country = (countryCode ?? _deviceCountry()).toUpperCase();
    return _autoPrefix(s, country);
  }

  // Returns ISO-3166-1 alpha-2 country code from GPS coordinates.
  // Covers the primary countries this app is used in.
  static String countryFromLatLng(double lat, double lng) {
    if (lat >= 8.0 && lat <= 37.5 && lng >= 68.0 && lng <= 97.5) return 'IN';
    if (lat >= 23.5 && lat <= 37.0 && lng >= 60.5 && lng <= 77.5) return 'PK';
    if (lat >= 20.5 && lat <= 26.7 && lng >= 88.0 && lng <= 92.7) return 'BD';
    if (lat >= 22.6 && lat <= 26.1 && lng >= 51.0 && lng <= 56.4) return 'AE';
    if (lat >= 16.3 && lat <= 32.2 && lng >= 34.5 && lng <= 55.7) return 'SA';
    if (lat >= 49.9 && lat <= 60.9 && lng >= -8.7 && lng <= 1.8)  return 'GB';
    if (lat >= 24.4 && lat <= 49.4 && lng >= -125.0 && lng <= -66.9) return 'US';
    return _deviceCountry();
  }

  static String _deviceCountry() {
    try {
      final parts = Platform.localeName.split('_');
      if (parts.length >= 2) return parts.last.toUpperCase();
    } catch (_) {}
    return 'IN';
  }

  static String? _autoPrefix(String digits, String country) {
    switch (country) {
      case 'IN':
        if (RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) return '+91$digits';
      case 'PK':
        if (RegExp(r'^3\d{9}$').hasMatch(digits)) return '+92$digits';
      case 'BD':
        if (RegExp(r'^01[3-9]\d{8}$').hasMatch(digits)) return '+880$digits';
      case 'AE':
        final d = digits.startsWith('0') ? digits.substring(1) : digits;
        if (RegExp(r'^5\d{8}$').hasMatch(d)) return '+971$d';
      case 'SA':
        final d = digits.startsWith('0') ? digits.substring(1) : digits;
        if (RegExp(r'^5\d{8}$').hasMatch(d)) return '+966$d';
      case 'GB':
        final d = digits.startsWith('0') ? digits.substring(1) : digits;
        if (RegExp(r'^[7-9]\d{9}$').hasMatch(d)) return '+44$d';
      case 'US':
      case 'CA':
        if (RegExp(r'^[2-9]\d{9}$').hasMatch(digits)) return '+1$digits';
    }
    return null;
  }
}
