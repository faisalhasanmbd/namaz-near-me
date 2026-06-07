import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class BoardOcrService {
  // ─── Public API ──────────────────────────────────────────────────────────

  static Future<Map<String, String?>> extractFromImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final combined = StringBuffer();

    // Pass 1: Latin (English digits + Roman text)
    try {
      final r = TextRecognizer(script: TextRecognitionScript.latin);
      final res = await r.processImage(inputImage);
      await r.close();
      if (res.text.isNotEmpty) combined.writeln(res.text);
    } catch (_) {}

    // Pass 2: Devanagari (Hindi digits ०-९ + Hindi prayer names)
    try {
      final r = TextRecognizer(script: TextRecognitionScript.devanagiri);
      final res = await r.processImage(inputImage);
      await r.close();
      if (res.text.isNotEmpty) combined.writeln(res.text);
    } catch (_) {}

    final text = combined.toString().trim();
    if (text.isEmpty) return {};
    return parseTextForTesting(text);
  }

  // ─── Text parsing (also exposed for unit tests) ───────────────────────────

  static Map<String, String?> parseTextForTesting(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final result = <String, String?>{};

    for (final line in lines) {
      final prayer = _detectPrayer(line);
      if (prayer == null) continue;
      if (result.containsKey(prayer)) continue;
      final time = _extractLastTime(line);
      if (time != null) result[prayer] = time;
    }
    return result;
  }

  // ─── Prayer label detection ───────────────────────────────────────────────

  static const _labels = <String, List<String>>{
    'fajr': [
      'fajr', 'fajar', 'fazar', 'subah', 'subh',
      'فجر', 'फ़जर', 'फजर', 'ফজর', 'பஜர்', 'ફજર',
    ],
    'zohar': [
      'zohar', 'zuhar', 'zuhr', 'zuhur', 'dhuhr', 'duhr', 'zohor',
      'johar', 'juhar', 'juhr',
      'ظهر', 'ظہر', 'ज़ोहर', 'जोहर', 'ज़ुहर', 'জুহর', 'லுஹர்', 'ઝોહર',
    ],
    'asr': [
      'asr', 'asar', 'ashar',
      'عصر', 'असर', 'অসর', 'அஸர்', 'અσρ', 'અسر',
    ],
    'maghrib': [
      'maghrib', 'magrib', 'mugrib', 'mughrib', 'mahrib',
      'مغرب', 'मगरिब', 'মাগরিব', 'மக்ரிப்', 'મગρиб',
    ],
    'isha': [
      'isha', 'esha', 'eisha',
      'عشاء', 'عشا', 'ईशा', 'এশা', 'இஷா', 'ઈশα',
    ],
    'juma': [
      'juma', 'jumma', 'jumuah', 'jumah', 'jum aa',
      "jumu'ah",
      'جمعه', 'جمعة', 'जुमा', 'জুমা', 'ஜும்ஆ', 'જुμα',
    ],
  };

  static String? _detectPrayer(String line) {
    final l = line.toLowerCase();
    for (final entry in _labels.entries) {
      if (entry.value.any((kw) => l.contains(kw.toLowerCase()))) {
        return entry.key;
      }
    }
    return null;
  }

  // ─── Time extraction ──────────────────────────────────────────────────────

  static final _timeRe = RegExp(
    r'([०-९\d]{1,2})[:\.]([०-९\d]{2})'  // 5:00 or Devanagari
    r'|'
    r'\b(\d{3,4})\b',                     // compact: 545 → 5:45
  );

  static String? _extractLastTime(String line) {
    final normalized = _replaceDevanagari(line);
    final matches = _timeRe.allMatches(normalized).toList();
    if (matches.isEmpty) return null;
    final last = matches.last;

    int h, m;
    if (last.group(3) != null) {
      final raw = last.group(3)!;
      if (raw.length == 3) {
        h = int.parse(raw.substring(0, 1));
        m = int.parse(raw.substring(1));
      } else {
        h = int.parse(raw.substring(0, 2));
        m = int.parse(raw.substring(2));
      }
    } else {
      h = int.parse(last.group(1)!);
      m = int.parse(last.group(2)!);
    }

    if (m >= 60) return null;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static String _replaceDevanagari(String s) {
    const dv = '०१२३४५६७८९';
    var r = s;
    for (var i = 0; i < dv.length; i++) {
      r = r.replaceAll(dv[i], '$i');
    }
    return r;
  }
}
