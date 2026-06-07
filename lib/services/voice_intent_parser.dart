enum VoiceQueryType { prayerTime, nearestMosque, nextPrayer, earliestPrayer, unknown }

class VoiceIntent {
  const VoiceIntent({required this.type, this.prayerName, this.language = 'en'});
  final VoiceQueryType type;
  final String? prayerName;
  final String language; // 'hi' or 'en'
}

class VoiceIntentParser {
  static const _prayerKeywords = <String, List<String>>{
    'fajr': [
      'fajr', 'fajar', 'subah', 'subh', 'dawn', 'sehri', 'sahr', 'seheri',
      // STT variants: F→P phonetic confusion
      'pajr', 'pajar', 'fazar', 'pazar',
      'फजर', 'सुबह', 'फ़ज्र',
    ],
    'zohar': [
      'zohar', 'zuhr', 'zuhor', 'dhuhr', 'duhr', 'dopahar', 'noon', 'midday',
      'zawal', 'zohor', 'zuhur', 'dopehar',
      // STT often transcribes Z→J for Urdu/Arabic words
      'johar', 'juhar', 'juhr', 'johor', 'juhur', 'johor', 'juhor',
      'दोपहर', 'ज़ुहर', 'जुहर',
    ],
    'asr': [
      'asr', 'afternoon', 'chaasht', 'asar', 'ashar', 'असर', 'अस्र',
    ],
    'maghrib': [
      'maghrib', 'magrib', 'sunset', 'iftar', 'sham', 'shaam', 'iftaar',
      // STT variants
      'mugrib', 'mughrib', 'magred', 'mahrib',
      'मगरिब', 'मग़रिब', 'इफ्तार', 'शाम',
    ],
    'isha': [
      'isha', 'esha', 'raat', 'night',
      // STT variants
      'eisha', 'aisha', 'icha', 'ishah',
      'इशा', 'रात',
    ],
    'juma': [
      'juma', 'jumma', 'jumuah', "jumu'ah", 'friday', 'jumah', 'jumu',
      'जुमा', 'जुम्मा',
    ],
  };

  static const _nextKeywords = [
    'next', 'agla', 'agle', 'upcoming', 'abhi', 'kya hai', 'kab hai',
    'aaj ka', 'अगला', 'अभी', 'कब', 'आज',
  ];

  static const _earliestKeywords = [
    'earliest', 'first', 'sabse pehle', 'pehli', 'sabse jaldi', 'jaldi',
    'pahle', 'pehle', 'soonest', 'सबसे पहले', 'पहली', 'जल्दी',
  ];

  static const _mosqueKeywords = [
    'mosque', 'masjid', 'nearest', 'nearby', 'nazdeek', 'paas', 'distance',
    'dur', 'kitna', 'km', 'kilometer', 'close', 'pass mein', 'kareeb',
    'मस्जिद', 'मस्जिद', 'नज़दीक', 'पास', 'करीब',
  ];

  static const _timeKeywords = [
    'time', 'waqt', 'baje', 'baj', 'wakt', 'kitne', 'batao', 'tell', 'what',
    'bata', 'batana', 'वक़्त', 'वक्त', 'बताओ', 'समय',
  ];

  // Hindi-only words — if found, language is Hindi
  static const _hindiMarkers = [
    'ka', 'ki', 'ke', 'hai', 'hain', 'kab', 'kya', 'waqt', 'batao',
    'bata', 'mujhe', 'mera', 'meri', 'kitna', 'kitne', 'sab', 'paas',
    'nazdeek', 'abhi', 'agle', 'agla', 'pehle', 'sabse', 'jaldi',
    'namaz', 'namaaz', 'masjid',
  ];

  static String detectLanguage(String text) {
    final t = text.toLowerCase();
    // Devanagari Unicode range
    final hasDevanagari = RegExp(r'[ऀ-ॿ]').hasMatch(text);
    if (hasDevanagari) return 'hi';
    final words = t.split(RegExp(r'[\s,]+'));
    final hindiHits = words.where((w) => _hindiMarkers.contains(w)).length;
    return hindiHits >= 1 ? 'hi' : 'en';
  }

  static VoiceIntent parse(String text) {
    final t = text.toLowerCase().trim();
    final lang = detectLanguage(text);

    String? prayer;
    for (final entry in _prayerKeywords.entries) {
      if (entry.value.any((k) => t.contains(k))) {
        prayer = entry.key;
        break;
      }
    }

    final hasNext = _nextKeywords.any((k) => t.contains(k));
    final hasEarliest = _earliestKeywords.any((k) => t.contains(k));
    final hasMosque = _mosqueKeywords.any((k) => t.contains(k));
    final hasTime = _timeKeywords.any((k) => t.contains(k));

    if (hasEarliest && !hasMosque) {
      return VoiceIntent(
        type: VoiceQueryType.earliestPrayer,
        prayerName: prayer,
        language: lang,
      );
    }

    if (hasNext && prayer == null) {
      return VoiceIntent(type: VoiceQueryType.nextPrayer, language: lang);
    }

    if (prayer != null && (hasTime || !hasMosque)) {
      return VoiceIntent(
        type: VoiceQueryType.prayerTime,
        prayerName: prayer,
        language: lang,
      );
    }

    if (hasMosque) {
      return VoiceIntent(
        type: VoiceQueryType.nearestMosque,
        prayerName: prayer,
        language: lang,
      );
    }

    if (prayer != null) {
      return VoiceIntent(
        type: VoiceQueryType.prayerTime,
        prayerName: prayer,
        language: lang,
      );
    }

    if (t.contains('next') || t.contains('namaz') || t.contains('namaaz') ||
        t.contains('kab') || t.isEmpty) {
      return VoiceIntent(type: VoiceQueryType.nextPrayer, language: lang);
    }

    return VoiceIntent(type: VoiceQueryType.unknown, language: lang);
  }
}
