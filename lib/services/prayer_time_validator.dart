import 'islamic_timing_service.dart';

/// Validates that a prayer time (HH:MM 24h) falls within the allowed window
/// for that prayer, based on today's Islamic timings.
class PrayerTimeValidator {
  static const int minimumJamaatGapMinutes = 5;

  PrayerTimeValidator({required IslamicTimingService service, this.cityName = ''}) {
    final timings = service.today();
    _fajr = _parseEntry(timings, 'Fajr') ?? 270;
    _sunrise = _parseEntry(timings, 'Sunrise') ?? 360;
    _zawal = _parseEntry(timings, 'Zawal') ?? 720;
    _zohar = _parseEntry(timings, 'Zuhr') ?? 750;
    _asr = _parseEntry(timings, 'Asr') ?? 930;
    _maghrib = _parseEntry(timings, 'Maghrib') ?? 1110;
    _isha = _parseEntry(timings, 'Isha') ?? 1230;
  }

  PrayerTimeValidator.forTesting({
    required int fajr,
    required int sunrise,
    required int zawal,
    required int zohar,
    required int asr,
    required int maghrib,
    required int isha,
    this.cityName = '',
  })  : _fajr = fajr,
        _sunrise = sunrise,
        _zawal = zawal,
        _zohar = zohar,
        _asr = asr,
        _maghrib = maghrib,
        _isha = isha;

  final String cityName;
  late final int _fajr;
  late final int _sunrise;
  late final int _zawal;
  late final int _zohar;
  late final int _asr;
  late final int _maghrib;
  late final int _isha;

  String? validate(String prayer, String hhmm) {
    return validateDetailed(prayer, hhmm).isValid ? hhmm : null;
  }

  PrayerTimeValidationResult validateDetailed(String prayer, String hhmm) {
    final normalizedPrayer = _normalizePrayer(prayer);
    final min = _toMinutes(hhmm);
    if (min == null) {
      return PrayerTimeValidationResult.invalid(
        prayer: normalizedPrayer,
        time: hhmm,
        message:
            '${_title(normalizedPrayer)} time "$hhmm" is not a valid HH:MM time.',
      );
    }

    final window = _windowFor(normalizedPrayer);
    if (window == null) return PrayerTimeValidationResult.valid();
    if (_inRange(min, window.start, window.end)) {
      return PrayerTimeValidationResult.valid();
    }

    final cityPart = cityName.isNotEmpty ? ' in $cityName' : '';
    final start = _formatMinutes(window.start);
    final end = _formatMinutes(window.end);
    final endDesc = window.endLabel.isNotEmpty
        ? '${window.endLabel} $end'
        : end;
    final message =
        '${_title(normalizedPrayer)}$cityPart starts at $start and valid edit time '
        'is allowed until $endDesc. Your submitted time $hhmm is outside the allowed '
        'time window. Please enter a time between $start and $end.';

    return PrayerTimeValidationResult.invalid(
      prayer: normalizedPrayer,
      time: hhmm,
      message: message,
    );
  }

  // Islamic midnight: midpoint between Maghrib and tomorrow's Fajr.
  // May exceed 1440 (i.e. past 00:00) — _inRange handles the wrap.
  int get _islamicMidnight {
    final nightLength = (_fajr + 1440) - _maghrib;
    return _maghrib + (nightLength ~/ 2);
  }

  bool _inRange(int min, int start, int end) {
    if (end > 1440) {
      // Window crosses midnight — valid if after start OR within early-morning portion
      return min >= start || min <= (end - 1440);
    }
    if (start >= end) return false;
    return min >= start && min <= end;
  }

  _PrayerWindow? _windowFor(String prayer) {
    switch (prayer) {
      case 'fajr':
        return _PrayerWindow(
          start: _fajr + minimumJamaatGapMinutes,
          end: _sunrise,
          endLabel: 'Sunrise',
        );
      case 'zohar':
      case 'juma':
        return _PrayerWindow(
          start: _zohar + minimumJamaatGapMinutes,
          end: _asr - 10,
          endLabel: '10 minutes before Asr,',
        );
      case 'asr':
        return _PrayerWindow(
          start: _asr + minimumJamaatGapMinutes,
          end: _maghrib - 15,
          endLabel: '15 minutes before Maghrib,',
        );
      case 'maghrib':
        return _PrayerWindow(
          start: _maghrib + minimumJamaatGapMinutes,
          end: _isha - 10,
          endLabel: '10 minutes before Isha,',
        );
      case 'isha':
        return _PrayerWindow(
          start: _isha + minimumJamaatGapMinutes,
          end: _islamicMidnight,
          endLabel: 'Islamic midnight,',
        );
      case 'eid_ul_fitr':
      case 'eid_ul_azha':
        return _PrayerWindow(
          start: _fajr + 10,
          end: _zawal - 1,
          endLabel: 'before Zawal,',
        );
      default:
        return null;
    }
  }

  static int? _parseEntry(dynamic timings, String label) {
    try {
      final entry = timings.entries.firstWhere(
        (e) => e.label.startsWith(label),
      );
      final timePart = entry.time.split('–').first.trim();
      return _toMinutes24(timePart);
    } catch (_) {
      return null;
    }
  }

  static int? _toMinutes24(String s) {
    final clean = s.trim().toUpperCase();
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$').firstMatch(clean);
    if (match == null) return null;
    var h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final period = match.group(3);
    if (period == 'AM' && h == 12) h = 0;
    if (period == 'PM' && h != 12) h += 12;
    return h * 60 + m;
  }

  static int? _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  static String _formatMinutes(int minutes) {
    final normalized = minutes % (24 * 60);
    final hour = normalized ~/ 60;
    final minute = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static String _normalizePrayer(String prayer) {
    final key = prayer.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    if (key == 'zuhr' || key == 'dhuhr' || key == 'zuhur') return 'zohar';
    if (key == 'jumma' || key == 'jumuah' || key == 'jummah') return 'juma';
    if (key == 'eid_fitr' || key == 'eidul_fitr') return 'eid_ul_fitr';
    if (key == 'eid_adha' || key == 'eid_azha' || key == 'eidul_azha') {
      return 'eid_ul_azha';
    }
    return key.replaceAll(RegExp(r'_+$'), '');
  }

  static String _title(String prayer) {
    return switch (prayer) {
      'fajr' => 'Fajr',
      'zohar' => 'Zohar',
      'asr' => 'Asr',
      'maghrib' => 'Maghrib',
      'isha' => 'Isha',
      'juma' => 'Juma',
      'eid_ul_fitr' => 'Eid ul Fitr',
      'eid_ul_azha' => 'Eid ul Azha',
      _ => prayer,
    };
  }
}

class PrayerTimeValidationResult {
  const PrayerTimeValidationResult._({
    required this.isValid,
    this.prayer,
    this.time,
    this.message,
  });

  factory PrayerTimeValidationResult.valid() {
    return const PrayerTimeValidationResult._(isValid: true);
  }

  factory PrayerTimeValidationResult.invalid({
    required String prayer,
    required String time,
    required String message,
  }) {
    return PrayerTimeValidationResult._(
      isValid: false,
      prayer: prayer,
      time: time,
      message: message,
    );
  }

  final bool isValid;
  final String? prayer;
  final String? time;
  final String? message;
}

class _PrayerWindow {
  const _PrayerWindow({
    required this.start,
    required this.end,
    this.endLabel = '',
  });

  final int start;
  final int end;
  final String endLabel;
}
