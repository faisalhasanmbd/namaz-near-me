import 'package:flutter_test/flutter_test.dart';
import 'package:namaz_near_me/services/islamic_timing_service.dart';

void main() {
  test('builds daily Islamic timing panel data', () {
    final timings = IslamicTimingService().today(now: DateTime(2026, 5, 15));

    expect(timings.weekday, 'Friday');
    expect(timings.englishDate, '15 May 2026');
    expect(timings.hijriDate, contains("Zi'Qadah"));
    expect(timings.entries.map((entry) => entry.label), contains('Zawal'));
    expect(timings.entries.map((entry) => entry.label), contains('Tahajjud'));
    expect(timings.entries.map((entry) => entry.label), contains('Roza Start'));
    expect(timings.entries.map((entry) => entry.label), contains('Roza End'));
    expect(timings.entries[timings.entries.length - 2].label, 'Roza Start');
    expect(timings.entries.last.label, 'Roza End');

    final zawal = timings.entries.firstWhere((entry) => entry.label == 'Zawal');
    final zohar = timings.entries.firstWhere((entry) => entry.label == 'Zuhr');
    expect(zawal.time.endsWith(zohar.time), isFalse);
  });

  test('keeps Gregorian date until midnight after Maghrib', () {
    final timings = IslamicTimingService().today(
      now: DateTime(2026, 5, 17, 22, 19),
      hijriDateOverride: "30 Zi'Qadah 1447 AH",
    );

    expect(timings.weekday, 'Sunday');
    expect(timings.hijriDate, contains("30 Zi'Qadah 1447 AH"));
    expect(timings.englishDate, '17 May 2026');
  });

  test('sets auto Maghrib jamaat five minutes after Maghrib Iftar', () {
    final service = IslamicTimingService();
    final date = DateTime(2026, 6, 2, 12);
    final timings = service.today(now: date);
    final iftar =
        timings.entries.firstWhere((entry) => entry.label == 'Roza End').time;

    expect(
      _timeToMinutes(service.maghribJamaatTime(now: date)),
      (_timeToMinutes(iftar) + 5) % (24 * 60),
    );
  });
}

int _timeToMinutes(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$').firstMatch(value);
  if (match == null) {
    throw FormatException('Unsupported time: $value');
  }
  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final period = match.group(3)!;
  if (period == 'AM') {
    hour = hour == 12 ? 0 : hour;
  } else {
    hour = hour == 12 ? 12 : hour + 12;
  }
  return hour * 60 + minute;
}
