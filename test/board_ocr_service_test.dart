import 'package:flutter_test/flutter_test.dart';
import 'package:namaz_near_me/services/board_ocr_service.dart';

void main() {
  test('reads Roman and Arabic LED board rows with jamat column last', () {
    final parsed = BoardOcrService.parseTextForTesting('''
FAJAR 4:45 5:00 فجر
ZUHAR 12:30 1:00 ظهر
ASR 4:45 5:00 عصر
MAGHRIB 6:13 6:16 مغرب
ISHA 7:45 8:00 عشاء
JUMAH 12:30 1:30 جمعه
''');

    expect(parsed, {
      'fajr': '05:00',
      'zohar': '01:00',
      'asr': '05:00',
      'maghrib': '06:16',
      'isha': '08:00',
      'juma': '01:30',
    });
  });

  test('reads Devanagari and Urdu slot board rows', () {
    final parsed = BoardOcrService.parseTextForTesting('''
फ़जर 6:00 فجر
ज़ोहर 2:00 ظہر
असर 4:00 عصر
मगरिब 5:25 مغرب
ईशा 8:00 عشاء
जुमा 1:30 جمعه
''');

    expect(parsed['fajr'], '06:00');
    expect(parsed['zohar'], '02:00');
    expect(parsed['asr'], '04:00');
    expect(parsed['maghrib'], '05:25');
    expect(parsed['isha'], '08:00');
    expect(parsed['juma'], '01:30');
  });

  test('reads Devanagari labels with Devanagari numerals', () {
    final parsed = BoardOcrService.parseTextForTesting('''
फ़जर ५:३०
ज़ोहर १:१५
असर ५:२५
मगरिब ६:५३
ईशा ८:२५
जुमा १:१५
''');

    expect(parsed['fajr'], '05:30');
    expect(parsed['zohar'], '01:15');
    expect(parsed['asr'], '05:25');
    expect(parsed['maghrib'], '06:53');
    expect(parsed['isha'], '08:25');
    expect(parsed['juma'], '01:15');
  });

  test('reads Gujarati labels and compact LED times', () {
    final parsed = BoardOcrService.parseTextForTesting('''
ફજર 555 فجر
ઝોહર 115 ظهر
અસર 520 عصر
મગરિબ 659 مغرب
ઈશા 815 عشاء
જુમા 145 جمعه
''');

    expect(parsed['fajr'], '05:55');
    expect(parsed['zohar'], '01:15');
    expect(parsed['asr'], '05:20');
    expect(parsed['maghrib'], '06:59');
    expect(parsed['isha'], '08:15');
    expect(parsed['juma'], '01:45');
  });

  test('reads Tamil mosque timing board labels', () {
    final parsed = BoardOcrService.parseTextForTesting('''
பஜர் FAJAR 5.10
லுஹர் ZUHAR 1.20
அஸர் ASAR 5.30
மக்ரிப் MAGRIB 6.45
இஷா ISHA 8.30
ஜும்ஆ JUM AA 1.15
''');

    expect(parsed['fajr'], '05:10');
    expect(parsed['zohar'], '01:20');
    expect(parsed['asr'], '05:30');
    expect(parsed['maghrib'], '06:45');
    expect(parsed['isha'], '08:30');
    expect(parsed['juma'], '01:15');
  });
}
