import 'package:flutter_test/flutter_test.dart';
import 'package:namaz_near_me/main.dart';
import 'package:namaz_near_me/services/prayer_time_validator.dart';

void main() {
  // Test timings:
  //   Fajr    04:30  (270 min)   window: 04:35 – 06:00
  //   Sunrise 06:00  (360 min)
  //   Zawal   12:00  (720 min)
  //   Zohar   12:15  (735 min)   window: 12:20 – 15:50  (Asr - 10 = 15:50)
  //   Asr     16:00  (960 min)   window: 16:05 – 18:15  (Maghrib - 15 = 18:15)
  //   Maghrib 18:30  (1110 min)  window: 18:35 – 19:50  (Isha - 10 = 19:50)
  //   Isha    20:00  (1200 min)  window: 20:05 – 23:30 (Islamic midnight)
  //   Islamic midnight = Maghrib(1110) + nightLength(600)/2 = 1410 = 23:30
  final validator = PrayerTimeValidator.forTesting(
    fajr: 4 * 60 + 30,
    sunrise: 6 * 60,
    zawal: 12 * 60,
    zohar: 12 * 60 + 15,
    asr: 16 * 60,
    maghrib: 18 * 60 + 30,
    isha: 20 * 60,
    cityName: 'Moradabad',
  );

  // ── Fajr: Fajr + 5 min → Sunrise ────────────────────────────────────────
  test('validates Fajr from 5 minutes after Fajr until sunrise', () {
    expect(validator.validate('fajr', '04:34'), isNull);   // before minimum jamaat gap
    expect(validator.validate('fajr', '04:35'), '04:35'); // Fajr + 5
    expect(validator.validate('fajr', '05:00'), '05:00'); // mid-window
    expect(validator.validate('fajr', '06:00'), '06:00'); // sunrise (inclusive)
    expect(validator.validate('fajr', '06:01'), isNull);  // after sunrise
  });

  // ── Zohar: Zohar + 5 min → Asr − 10 min ─────────────────────────────────
  test('validates Zohar before Asr minus 10 minutes', () {
    expect(validator.validate('zohar', '12:19'), isNull);   // before minimum jamaat gap
    expect(validator.validate('zohar', '12:20'), '12:20'); // Zohar + 5
    expect(validator.validate('zohar', '15:50'), '15:50'); // Asr-10 boundary
    expect(validator.validate('zohar', '15:51'), isNull);  // past Asr-10
  });

  // ── Juma: same window as Zohar ───────────────────────────────────────────
  test('Juma follows Zohar window (Zohar + 5 min to Asr minus 10 min)', () {
    expect(validator.validate('juma', '12:19'), isNull);
    expect(validator.validate('juma', '12:20'), '12:20');
    expect(validator.validate('juma', '15:50'), '15:50');
    expect(validator.validate('juma', '15:51'), isNull);
  });

  // ── Asr: Asr + 5 min → Maghrib − 15 min ─────────────────────────────────
  test('validates Asr before Maghrib minus 15 minutes', () {
    expect(validator.validate('asr', '16:04'), isNull);   // before minimum jamaat gap
    expect(validator.validate('asr', '16:05'), '16:05'); // Asr + 5
    expect(validator.validate('asr', '18:15'), '18:15'); // Maghrib-15 boundary
    expect(validator.validate('asr', '18:16'), isNull);  // past Maghrib-15
  });

  // ── Maghrib: Maghrib + 5 min → Isha − 10 min ────────────────────────────
  test('validates Maghrib before Isha minus 10 minutes', () {
    expect(validator.validate('maghrib', '18:34'), isNull);   // before minimum jamaat gap
    expect(validator.validate('maghrib', '18:35'), '18:35'); // Maghrib + 5
    expect(validator.validate('maghrib', '19:50'), '19:50'); // Isha-10 boundary
    expect(validator.validate('maghrib', '19:51'), isNull);  // past Isha-10
  });

  // ── Isha: Isha + 5 min → Islamic midnight (23:30 for these test timings) ─
  test('validates Isha from 5 minutes after Isha until Islamic midnight', () {
    expect(validator.validate('isha', '20:04'), isNull);   // before minimum jamaat gap
    expect(validator.validate('isha', '20:05'), '20:05'); // Isha + 5
    expect(validator.validate('isha', '22:51'), '22:51'); // mid-window (was old boundary)
    expect(validator.validate('isha', '23:30'), '23:30'); // Islamic midnight (inclusive)
    expect(validator.validate('isha', '23:31'), isNull);  // past Islamic midnight
  });

  // ── Eid: 10 min after Fajr → before Zawal ───────────────────────────────
  test('validates Eid from 10 minutes after Fajr until before Zawal', () {
    expect(validator.validate('eid_ul_fitr', '04:39'), isNull);
    expect(validator.validate('eid_ul_fitr', '04:40'), '04:40');
    expect(validator.validate('eid_ul_fitr', '11:59'), '11:59');
    expect(validator.validate('eid_ul_fitr', '12:00'), isNull);
    expect(validator.validate('eid_ul_azha', '11:59'), '11:59');
    expect(validator.validate('eid_ul_azha', '12:00'), isNull);
  });

  // ── Error message contains city, prayer name, start, end, submitted time ─
  test('error message includes city name and window boundaries', () {
    final result = validator.validateDetailed('fajr', '06:01');
    expect(result.isValid, isFalse);
    expect(result.message, contains('Fajr'));
    expect(result.message, contains('Moradabad'));
    expect(result.message, contains('04:35'));
    expect(result.message, contains('Sunrise'));
    expect(result.message, contains('06:00'));
    expect(result.message, contains('06:01'));
  });

  test('Zohar error message references Asr boundary', () {
    final result = validator.validateDetailed('zohar', '15:51');
    expect(result.isValid, isFalse);
    expect(result.message, contains('Zohar'));
    expect(result.message, contains('Moradabad'));
    expect(result.message, contains('12:20'));
    expect(result.message, contains('15:50'));
    expect(result.message, contains('10 minutes before Asr'));
  });

  test('Isha error message shows Islamic midnight as max', () {
    final result = validator.validateDetailed('isha', '23:31');
    expect(result.isValid, isFalse);
    expect(result.message, contains('Isha'));
    expect(result.message, contains('23:30'));
    expect(result.message, contains('Islamic midnight'));
  });

  // ── Prayer name normalisation ─────────────────────────────────────────────
  test('normalizes Fajr and Eid as AM, all other listed prayers as PM', () {
    expect(normalizePrayerTimingInput('fajr', '6:00'), '06:00');
    expect(normalizePrayerTimingInput('eid_ul_fitr', '8:00'), '08:00');
    expect(normalizePrayerTimingInput('eid_ul_azha', '8:15'), '08:15');
    expect(normalizePrayerTimingInput('zohar', '1:15'), '13:15');
    expect(normalizePrayerTimingInput('juma', '1:30'), '13:30');
    expect(normalizePrayerTimingInput('asr', '5:00'), '17:00');
    expect(normalizePrayerTimingInput('maghrib', '6:45'), '18:45');
    expect(normalizePrayerTimingInput('isha', '8:30'), '20:30');
  });
}
