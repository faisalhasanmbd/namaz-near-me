import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/daily_islamic_timings.dart';

class IslamicTimingService {
  static const _lastHijriKey = 'hijri_last';

  static Future<String?> fetchHijriDateIndia({
    DateTime? date,
    int dayAdjustment = 0,
  }) async {
    final d = (date ?? DateTime.now()).add(Duration(days: dayAdjustment));
    final cacheKey = 'hijri_${d.year}_${d.month}_${d.day}';
    SharedPreferences? prefs;

    try {
      prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);
      if (cached != null) return cached;

      final url = Uri.parse(
          'https://api.aladhan.com/v1/gToH/${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final hijri = json['data']['hijri'];
        final day = int.parse(hijri['day'].toString());
        final month = int.parse(hijri['month']['number'].toString());
        final year = int.parse(hijri['year'].toString());
        const months = [
          'Muharram',
          'Safar',
          'Rabi al-Awwal',
          'Rabi al-Thani',
          'Jumada al-Awwal',
          'Jumada al-Thani',
          'Rajab',
          "Sha'ban",
          'Ramadan',
          'Shawwal',
          "Zi'Qadah",
          'Dhu al-Hijjah'
        ];
        final result = '$day ${months[month - 1]} $year AH';
        await prefs.setString(cacheKey, result);
        await prefs.setString(_lastHijriKey, result);
        return result;
      }
    } catch (_) {}

    // Offline fallback: return today's cached value or last known Hijri date
    try {
      prefs ??= await SharedPreferences.getInstance();
      return prefs.getString(cacheKey) ?? prefs.getString(_lastHijriKey);
    } catch (_) {}
    return null;
  }

  final double latitude;
  final double longitude;
  final int asrShadowFactor;
  static const _fajrAngle = -18.0;
  static const _ishaAngle = -18.0;

  IslamicTimingService({
    this.latitude = 28.8386,
    this.longitude = 78.7733,
    this.asrShadowFactor = 2,
  });

  DateTime hijriDateFor(DateTime date) {
    final currentMinutes = date.hour * 60 + date.minute;
    final sunsetToday = _solarTime(date, -0.833, beforeNoon: false);
    return currentMinutes >= sunsetToday
        ? date.add(const Duration(days: 1))
        : date;
  }

  /// Returns the Islamic day — which starts at Maghrib (sunset).
  /// If current time is after Maghrib, we show tomorrow's Gregorian date
  /// but the NEXT Islamic date (since Islamic day has begun).
  DailyIslamicTimings today({DateTime? now, String? hijriDateOverride}) {
    final date = now ?? DateTime.now();

    // Calculate sunset (Maghrib) for today
    final sunsetToday = _solarTime(date, -0.833, beforeNoon: false);

    // Islamic day starts at Maghrib — if we're past Maghrib, show next Islamic day
    final islamicDate = hijriDateFor(date);

    // Always calculate prayer times for TODAY (Gregorian) for accuracy
    final sunrise = _solarTime(date, -0.833, beforeNoon: true);
    final sunset = sunsetToday;
    final fajr = _solarTime(date, _fajrAngle, beforeNoon: true);
    final isha = _solarTime(date, _ishaAngle, beforeNoon: false);
    final zohar = _solarNoonMinutes(date).round();
    final asr = _asrTime(date, shadowFactor: asrShadowFactor);
    final sehriEnd = fajr - 6;
    final zawalStart = zohar - 10;
    final zawalEnd = zohar - 1;
    final tahajjudStart =
        _normalizeMinutes(isha + _nightLength(isha, fajr) ~/ 2);

    return DailyIslamicTimings(
      weekday: _weekday(date),
      englishDate: _englishDate(date),
      hijriDate: hijriDateOverride ?? _hijriDate(islamicDate),
      entries: [
        IslamicTimeEntry(label: 'Fajr', time: _formatTime(fajr)),
        IslamicTimeEntry(label: 'Sunrise', time: _formatTime(sunrise)),
        IslamicTimeEntry(
          label: 'Zawal',
          time: '${_formatTime(zawalStart)} – ${_formatTime(zawalEnd)}',
        ),
        IslamicTimeEntry(label: 'Zuhr', time: _formatTime(zohar)),
        IslamicTimeEntry(label: 'Asr', time: _formatTime(asr)),
        IslamicTimeEntry(label: 'Maghrib', time: _formatTime(sunset)),
        IslamicTimeEntry(label: 'Isha', time: _formatTime(isha)),
        IslamicTimeEntry(
          label: 'Tahajjud',
          time: '${_formatTime(tahajjudStart)} – ${_formatTime(fajr)}',
        ),
        IslamicTimeEntry(label: 'Roza Start', time: _formatTime(sehriEnd)),
        IslamicTimeEntry(label: 'Roza End', time: _formatTime(sunset)),
      ],
    );
  }

  String maghribJamaatTime({DateTime? now}) {
    final date = now ?? DateTime.now();
    final iftar = _solarTime(date, -0.833, beforeNoon: false);
    return _formatTime(iftar + 5);
  }

  double _solarNoonMinutes(DateTime date) {
    final day = _dayOfYear(date);
    final eqTime = _equationOfTime(day);
    return 720 - 4 * longitude - eqTime + date.timeZoneOffset.inMinutes;
  }

  int _solarTime(DateTime date, double altitude, {required bool beforeNoon}) {
    final day = _dayOfYear(date);
    final declination = _sunDeclination(day);
    final noon = _solarNoonMinutes(date);
    final hourAngle = _hourAngle(altitude, declination);
    final minutes = beforeNoon ? noon - hourAngle * 4 : noon + hourAngle * 4;
    return _normalizeMinutes(minutes.round());
  }

  int _asrTime(DateTime date, {required int shadowFactor}) {
    final day = _dayOfYear(date);
    final declination = _sunDeclination(day);
    final lat = _degToRad(latitude);
    final dec = _degToRad(declination);
    final angle =
        _radToDeg(math.atan(1 / (shadowFactor + math.tan((lat - dec).abs()))));
    final noon = _solarNoonMinutes(date);
    final hourAngle = _hourAngle(angle, declination);
    return _normalizeMinutes((noon + hourAngle * 4).round());
  }

  double _hourAngle(double altitude, double declination) {
    final lat = _degToRad(latitude);
    final dec = _degToRad(declination);
    final alt = _degToRad(altitude);
    final value = (math.sin(alt) - math.sin(lat) * math.sin(dec)) /
        (math.cos(lat) * math.cos(dec));
    return _radToDeg(math.acos(value.clamp(-1, 1)));
  }

  static int _nightLength(int isha, int fajr) =>
      fajr > isha ? fajr - isha : 24 * 60 - isha + fajr;

  static double _equationOfTime(int d) {
    final g = 2 * math.pi / 365 * (d - 1);
    return 229.18 *
        (0.000075 +
            0.001868 * math.cos(g) -
            0.032077 * math.sin(g) -
            0.014615 * math.cos(2 * g) -
            0.040849 * math.sin(2 * g));
  }

  static double _sunDeclination(int d) {
    final g = 2 * math.pi / 365 * (d - 1);
    return _radToDeg(0.006918 -
        0.399912 * math.cos(g) +
        0.070257 * math.sin(g) -
        0.006758 * math.cos(2 * g) +
        0.000907 * math.sin(2 * g) -
        0.002697 * math.cos(3 * g) +
        0.00148 * math.sin(3 * g));
  }

  static int _dayOfYear(DateTime date) =>
      date.difference(DateTime(date.year)).inDays + 1;
  static int _normalizeMinutes(int m) => ((m % 1440) + 1440) % 1440;

  static String _formatTime(int t) {
    final m = _normalizeMinutes(t);
    final h24 = m ~/ 60;
    final min = m % 60;
    final p = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12:${min.toString().padLeft(2, '0')} $p';
  }

  static String _englishDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_month(d.month)} ${d.year}';

  static String _hijriDate(DateTime date) {
    final h = _gregorianToHijri(date);
    return '${h.day} ${_hijriMonth(h.month)} ${h.year} AH';
  }

  /// Returns [month, day] of the Hijri date — used for Eid detection.
  static List<int> hijriMonthDay(DateTime date) {
    final h = _gregorianToHijri(date);
    return [h.month, h.day];
  }

  static _HijriDate _gregorianToHijri(DateTime date) {
    final jd = _gregorianToJulianDay(date.year, date.month, date.day);
    final y = ((30 * (jd - 1948439.5) + 10646) / 10631).floor();
    final mo = math.min(
        12, ((jd - (29 + _islamicToJulianDay(y, 1, 1))) / 29.5).ceil() + 1);
    final dy = (jd - _islamicToJulianDay(y, mo, 1) + 1).floor();
    return _HijriDate(year: y, month: mo, day: dy);
  }

  static double _gregorianToJulianDay(int y, int mo, int d) {
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

  static double _islamicToJulianDay(int y, int mo, int d) =>
      d +
      (29.5 * (mo - 1)).ceil() +
      (y - 1) * 354 +
      ((3 + 11 * y) / 30).floor() +
      1948439.5 -
      1;

  static String _weekday(DateTime d) => [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ][d.weekday - 1];

  static String _month(int m) => [
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
        'December'
      ][m - 1];

  static String _hijriMonth(int m) => [
        'Muharram',
        'Safar',
        'Rabi al-Awwal',
        'Rabi al-Thani',
        'Jumada al-Awwal',
        'Jumada al-Thani',
        'Rajab',
        "Sha'ban",
        'Ramadan',
        'Shawwal',
        "Zi'Qadah",
        'Dhu al-Hijjah'
      ][m - 1];

  static double _degToRad(double d) => d * math.pi / 180;
  static double _radToDeg(double r) => r * 180 / math.pi;
}

class _HijriDate {
  const _HijriDate(
      {required this.year, required this.month, required this.day});
  final int year;
  final int month;
  final int day;
}
