import 'package:flutter_test/flutter_test.dart';
import 'package:namaz_near_me/services/islamic_timing_service.dart';

void main() {
  test('builds daily Islamic timing panel data', () {
    final timings = IslamicTimingService().today(now: DateTime(2026, 5, 15));

    expect(timings.weekday, 'Friday');
    expect(timings.englishDate, '15 May 2026');
    expect(timings.hijriDate, contains("Zi'Qadah"));
    expect(
        timings.entries.map((entry) => entry.label), contains('Khatm Sehri'));
    expect(timings.entries.map((entry) => entry.label), contains('Zawal'));
    expect(timings.entries.map((entry) => entry.label), contains('Tahajjud'));
    expect(timings.entries.map((entry) => entry.label), contains('Roza'));

    final zawal = timings.entries.firstWhere((entry) => entry.label == 'Zawal');
    final zohar =
        timings.entries.firstWhere((entry) => entry.label == 'Waqt Zohar');
    expect(zawal.time.endsWith(zohar.time), isFalse);
  });
}
