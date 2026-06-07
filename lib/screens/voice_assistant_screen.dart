import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/islamic_timing_service.dart';
import '../models/mosque.dart';
import '../services/location_service.dart';

const _kWitToken = String.fromEnvironment('WIT_TOKEN');
const _kWitVersion = '20260607';

class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({
    super.key,
    required this.mosques,
    required this.userLocation,
    required this.cityName,
    required this.radiusKm,
  });

  final List<Mosque> mosques;
  final UserLocation userLocation;
  final String cityName;
  final double radiusKm;

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

enum _AssistantState { idle, listening, processing, responding }

enum _Lang { hindi, english }

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen>
    with SingleTickerProviderStateMixin {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  _AssistantState _state = _AssistantState.idle;
  String _recognizedText = '';
  String _responseText = '';
  bool _sttAvailable = false;
  String _sttLocale = 'en_IN';
  bool _processingLock = false;
  String _currentTtsLang = 'hi-IN';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initStt();
    _initTts();
  }

  Future<void> _initStt() async {
    _sttAvailable = await _stt.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') &&
            _state == _AssistantState.listening) {
          _onListeningDone();
        }
      },
      onError: (_) {
        if (mounted) setState(() => _state = _AssistantState.idle);
      },
    );
    if (_sttAvailable) {
      final locales = await _stt.locales();
      final ids = locales.map((l) => l.localeId).toList();
      // en_IN handles both English and Hinglish in Roman script.
      // hi_IN transliterates English words to Devanagari, breaking Wit.ai matching.
      if (ids.any((id) => id.startsWith('en_IN') || id.startsWith('en-IN'))) {
        _sttLocale = ids.firstWhere(
            (id) => id.startsWith('en_IN') || id.startsWith('en-IN'));
      } else if (ids.any((id) => id.startsWith('en'))) {
        _sttLocale = ids.firstWhere((id) => id.startsWith('en'));
      } else if (ids.any((id) => id.startsWith('hi'))) {
        _sttLocale = ids.firstWhere((id) => id.startsWith('hi'));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('hi-IN');
    try {
      // Use hi-IN-x-hd-network (best Hindi voice on Android) if available
      final dynamic raw = await _tts.getVoices;
      if (raw is List) {
        final hdVoice = raw.whereType<Map>().firstWhere(
              (v) =>
                  (v['name'] as String? ?? '')
                      .toLowerCase()
                      .contains('x-hid-network') ||
                  (v['name'] as String? ?? '').toLowerCase() ==
                      'hi-in-x-hid-network',
              orElse: () => {},
            );
        if ((hdVoice['name'] as String? ?? '').isNotEmpty) {
          await _tts.setVoice({
            'name': hdVoice['name'] as String,
            'locale': hdVoice['locale'] as String? ?? 'hi-IN'
          });
        }
      }
    } catch (_) {}
    await _tts.setPitch(0.75);
    await _tts.setSpeechRate(0.46);
    await _tts.setVolume(1.0);
    _tts.setCompletionHandler(() {
      if (mounted && _state == _AssistantState.responding) {
        setState(() => _state = _AssistantState.idle);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stt.stop();
    _tts.stop();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_state == _AssistantState.listening) {
      await _stt.stop();
      await _onListeningDone();
      return;
    }
    if (!_sttAvailable) {
      await _speakAndShow('Microphone not available.', _Lang.english);
      return;
    }
    await _tts.stop();
    setState(() {
      _state = _AssistantState.listening;
      _recognizedText = '';
      _responseText = '';
    });
    await _stt.listen(
      onResult: (result) {
        if (mounted) setState(() => _recognizedText = result.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        localeId: _sttLocale,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
      ),
    );
  }

  Future<void> _onListeningDone() async {
    if (_processingLock) return;
    _processingLock = true;
    await _stt.stop();
    final query = _recognizedText.trim();
    if (query.isEmpty) {
      _processingLock = false;
      setState(() => _state = _AssistantState.idle);
      return;
    }
    setState(() => _state = _AssistantState.processing);
    await _processWithWit(query);
    _processingLock = false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIT.AI PROCESSING
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _processWithWit(String query) async {
    if (_kWitToken.isEmpty) {
      await _processLocally(query);
      return;
    }
    try {
      final uri = Uri.parse('https://api.wit.ai/message').replace(
        queryParameters: {'v': _kWitVersion, 'q': query},
      );
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $_kWitToken'},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200)
        throw Exception('status ${response.statusCode}');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final intents = (data['intents'] as List<dynamic>?) ?? [];
      final intent = intents.isNotEmpty
          ? ((intents[0] as Map)['name'] as String? ?? '')
          : '';
      final confidence = intents.isNotEmpty
          ? ((intents[0] as Map)['confidence'] as num? ?? 0).toDouble()
          : 0.0;

      // Extract prayer_name entity value if present
      final entities = (data['entities'] as Map<String, dynamic>?) ?? {};
      final prayerList = entities['prayer_name:prayer_name'] as List<dynamic>?;
      final prayerName = (prayerList?.isNotEmpty == true)
          ? ((prayerList![0] as Map)['value'] as String? ?? '').toLowerCase()
          : '';

      // If confidence too low or no intent, fall back to keywords
      if (intent.isEmpty || confidence < 0.6) {
        await _processLocally(query);
        return;
      }

      await _handleIntent(intent, prayerName, query);
    } catch (e) {
      debugPrint('[Wit.ai] $e — using keyword fallback');
      await _processLocally(query);
    }
  }

  Future<void> _handleIntent(String intent, String prayer, String raw) async {
    final lang = _detectLang(raw.toLowerCase());
    final ctx = _buildContext();

    switch (intent) {
      case 'navigate_mosque':
        final r = await _navigateToMosque(ctx.sorted, lang);
        await _speakAndShow(r, lang);

      case 'get_prayer_time':
        final name = _prayerDisplayName(prayer);
        final time = ctx.pt[prayer];
        final r = _prayerTime(name, time, ctx.sorted, lang);
        await _speakAndShow(r, lang);

      case 'next_prayer':
        await _speakAndShow(_nextPrayer(ctx.pt, ctx.sorted, lang), lang);

      case 'nearby_mosques':
        await _speakAndShow(_nearbyList(ctx.sorted, lang), lang);

      case 'get_hijri_date':
        final date = ctx.today.hijriDate;
        await _speakAndShow(
          _r(lang, 'Aaj ki Islamic tarikh $date hai.',
              'Today\'s Islamic date is $date.'),
          lang,
        );

      case 'all_prayer_times':
        await _speakAndShow(_allTimes(ctx.pt, lang), lang);

      case 'greeting':
        await _speakAndShow(
          _r(
              lang,
              'Wa alaikum assalam! Namaz ka waqt, qareeb ki masjid, ya navigation — kya chahiye?',
              'Wa alaikum assalam! Ask me prayer times, nearby mosques, or navigation.'),
          lang,
        );

      default:
        await _processLocally(raw);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KEYWORD FALLBACK (when offline or Wit.ai confidence low)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _processLocally(String query) async {
    final q = query.toLowerCase();
    final lang = _detectLang(q);
    final ctx = _buildContext();
    String response;

    if (_has(q, [
      'navigate',
      'navigation',
      'directions',
      'direction',
      'le chalo',
      'le ja',
      'jaana hai',
      'jana hai',
      'maps pe',
      'map mein',
      'map me',
      'rasta',
      'raasta',
      'नेविगेट',
      'ले चलो',
      'ले जाओ',
      'रास्ता'
    ])) {
      response = await _navigateToMosque(ctx.sorted, lang);
    } else if (_has(q, [
      'hijri',
      'hijra',
      'islamic date',
      'islamik date',
      'islamic calendar',
      'aaj ki tarikh',
      'hijri tarikh',
      'islamik tarikh',
      'हिज्री',
      'तारीख'
    ])) {
      response = _r(lang, 'Aaj ki Islamic tarikh ${ctx.today.hijriDate} hai.',
          'Today\'s Islamic date is ${ctx.today.hijriDate}.');
    } else if (_has(q, [
      'agli',
      'agle',
      'next',
      'kaunsi',
      'konsi',
      'abhi',
      'upcoming',
      'kitni der',
      'how long',
      'how soon',
      'when is next',
      'अगली',
      'अगले'
    ])) {
      response = _nextPrayer(ctx.pt, ctx.sorted, lang);
    } else if (_has(q, [
      'fajr',
      'fajar',
      'fazr',
      'pajr',
      'subah',
      'morning prayer',
      'फज्र',
      'फजर',
      'सुबह'
    ])) {
      response = _prayerTime('Fajr', ctx.pt['fajr'], ctx.sorted, lang);
    } else if (_has(q, [
      'juma',
      'jumma',
      'jummah',
      'jumah',
      'friday',
      'jumme',
      'जुमा',
      'जुम्मा'
    ])) {
      response = _prayerTime(
          'Juma', ctx.jumaTime ?? ctx.pt['zohar'], ctx.sorted, lang);
    } else if (_has(q, [
      'zohar',
      'zuhr',
      'zuhur',
      'johar',
      'juhar',
      'dopahar',
      'dhuhr',
      'noon prayer',
      'ज़ोहर',
      'जोहर',
      'दोपहर'
    ])) {
      response = _prayerTime('Zohar', ctx.pt['zohar'], ctx.sorted, lang);
    } else if (_has(
        q, ['asr', 'asar', 'asur', 'late afternoon', 'असर', 'अस्र'])) {
      response = _prayerTime('Asr', ctx.pt['asr'], ctx.sorted, lang);
    } else if (_has(q, [
      'maghrib',
      'magrib',
      'mughrib',
      'mugrib',
      'shaam',
      'sunset prayer',
      'मग्रिब',
      'मग़रिब',
      'शाम'
    ])) {
      response = _prayerTime('Maghrib', ctx.pt['maghrib'], ctx.sorted, lang);
    } else if (_has(q, [
      'isha',
      'esha',
      'eisha',
      'raat ki namaz',
      'night prayer',
      'इशा',
      'ईशा',
      'रात'
    ])) {
      response = _prayerTime('Isha', ctx.pt['isha'], ctx.sorted, lang);
    } else if (_has(q, [
      'nearby',
      'qareeb',
      'paas',
      'nazdik',
      'masajid',
      'mosques',
      'list',
      '2',
      '3',
      'teen',
      'near me',
      'around',
      'aas paas',
      'नज़दीक',
      'क़रीब',
      'मस्जिदें'
    ])) {
      response = _nearbyList(ctx.sorted, lang);
    } else if (_has(q, [
      'masjid',
      'mosque',
      'nearest mosque',
      'sabse qareeb',
      'kahan hai',
      'where is',
      'timings',
      'schedule',
      'मस्जिद',
      'नियरेस्ट',
      'सबसे क़रीब'
    ])) {
      response = _mosqueDetail(ctx.sorted, lang);
    } else if (_has(q, [
      'sab',
      'all',
      'tamam',
      'schedule',
      'timetable',
      'awqat',
      'all times',
      'full schedule'
    ])) {
      response = _allTimes(ctx.pt, lang);
    } else if (_has(q, [
      'assalam',
      'salam',
      'hello',
      'hey',
      'hi',
      'sun raha',
      'सलाम',
      'हेलो'
    ])) {
      response = _r(
          lang,
          'Wa alaikum assalam! Namaz ka waqt, qareeb ki masjid, ya navigation — kya chahiye?',
          'Wa alaikum assalam! Ask me prayer times, nearby mosques, or navigation.');
    } else if (_has(
        q, ['waqt', 'time', 'kab', 'kitne', 'baje', 'when', 'batao'])) {
      response = _nextPrayer(ctx.pt, ctx.sorted, lang);
    } else {
      response = _r(
          lang,
          'Fajr, Zohar, Asr, Maghrib ya Isha ka waqt puchho — ya "masjid le chalo" bolo.',
          'Ask Fajr, Zohar, Asr, Maghrib or Isha time — or say "navigate to mosque".');
    }

    await _speakAndShow(response, lang);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTEXT BUILDER
  // ═══════════════════════════════════════════════════════════════════════════

  _QueryContext _buildContext() {
    final service = IslamicTimingService(
      latitude: widget.userLocation.latitude,
      longitude: widget.userLocation.longitude,
    );
    final today = service.today();
    final Map<String, String> pt = {};
    for (final e in today.entries) {
      final lbl = e.label.toLowerCase();
      if (lbl == 'fajr')
        pt['fajr'] = e.time;
      else if (lbl == 'zuhr')
        pt['zohar'] = e.time;
      else if (lbl == 'asr')
        pt['asr'] = e.time;
      else if (lbl.startsWith('maghrib'))
        pt['maghrib'] = e.time;
      else if (lbl == 'isha') pt['isha'] = e.time;
    }
    final sorted = [...widget.mosques]
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    String? jumaTime;
    for (final m in sorted) {
      if ((m.timings.juma ?? '').isNotEmpty) {
        jumaTime = m.timings.juma;
        break;
      }
    }
    return _QueryContext(
        today: today, pt: pt, sorted: sorted, jumaTime: jumaTime);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESPONSE BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _navigateToMosque(List<Mosque> sorted, _Lang lang) async {
    if (sorted.isEmpty) {
      return _r(lang, 'Aapke qareeb koi masjid nahi mili.',
          'No mosque found near you.');
    }
    final m = sorted.first;
    final dist = m.hasCoordinates
        ? '${(m.distanceMeters / 1000).toStringAsFixed(1)} km'
        : '';
    if (m.hasCoordinates) {
      final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${m.latitude},${m.longitude}',
      );
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return _r(
      lang,
      'Theek hai! ${m.name} ki taraf navigation shuru ho rahi hai — $dist door hai.',
      'Navigating to ${m.name}, $dist away. Maps is opening.',
    );
  }

  String _prayerTime(
      String name, String? time, List<Mosque> sorted, _Lang lang) {
    String? mosqueTime, mosqueName;
    final key = name.toLowerCase();
    for (final m in sorted.take(3)) {
      final t = m.timings.byName(key);
      if ((t ?? '').isNotEmpty) {
        mosqueTime = t;
        mosqueName = m.name;
        break;
      }
    }
    final display = mosqueTime ?? time;
    if ((display ?? '').isEmpty || display == '—') {
      return _r(lang, '$name ka waqt abhi available nahi.',
          '$name time not available.');
    }
    if (mosqueTime != null && mosqueName != null) {
      return _r(
        lang,
        '$name aaj $display baje hai — $mosqueName masjid ka waqt.',
        '$name today is at $display — from $mosqueName mosque.',
      );
    }
    return _r(
      lang,
      '$name ka waqt aaj ${widget.cityName} mein $display hai.',
      '$name time today in ${widget.cityName} is $display.',
    );
  }

  String _nextPrayer(Map<String, String> pt, List<Mosque> sorted, _Lang lang) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    const order = [
      ('Fajr', 'fajr'),
      ('Zohar', 'zohar'),
      ('Asr', 'asr'),
      ('Maghrib', 'maghrib'),
      ('Isha', 'isha')
    ];
    for (final (name, key) in order) {
      final time = pt[key];
      if ((time ?? '').isEmpty || time == '—') continue;
      final parts = time!.split(':');
      if (parts.length < 2) continue;
      final pMin =
          (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
      if (pMin > nowMin) {
        final diff = pMin - nowMin;
        final h = diff ~/ 60;
        final m = diff % 60;
        String? mosqueT;
        for (final ms in sorted.take(3)) {
          final t = ms.timings.byName(key);
          if ((t ?? '').isNotEmpty) {
            mosqueT = t;
            break;
          }
        }
        final extra = mosqueT != null
            ? _r(lang, ' Masjid mein $mosqueT baje.', ' Mosque time: $mosqueT.')
            : '';
        if (h > 0) {
          return _r(
              lang,
              'Agli namaz $name hai — $time baje, $h ghante $m minute mein.$extra',
              'Next prayer is $name at $time, in ${h}h ${m}m.$extra');
        }
        return _r(
            lang,
            'Agli namaz $name hai — $time baje, sirf $m minute mein!$extra',
            'Next prayer is $name at $time, just ${m}m away!$extra');
      }
    }
    return _r(
        lang,
        'Aaj ki tamam namazein ho gayi.${pt['fajr'] != null ? ' Kal Fajr ${pt['fajr']} baje.' : ''}',
        'All prayers done for today.${pt['fajr'] != null ? ' Tomorrow Fajr at ${pt['fajr']}.' : ''}');
  }

  String _nearbyList(List<Mosque> sorted, _Lang lang) {
    if (sorted.isEmpty) {
      return _r(lang, 'Koi masjid nahi mili.', 'No mosques found near you.');
    }
    final top = sorted.take(3).toList();
    final nums = _r(
      lang,
      ['Pehli', 'Doosri', 'Teesri'],
      ['First', 'Second', 'Third'],
    ) as List<String>;
    final parts = <String>[];
    for (var i = 0; i < top.length; i++) {
      final m = top[i];
      final dist = m.hasCoordinates
          ? '${(m.distanceMeters / 1000).toStringAsFixed(1)} km'
          : '';
      parts.add('${nums[i]}: ${m.name}${dist.isNotEmpty ? ", $dist" : ""}');
    }
    final intro = _r(lang, '${top.length} masajid qareeb hain. ',
        '${top.length} mosques near you. ');
    return intro + parts.join('. ') + '.';
  }

  String _mosqueDetail(List<Mosque> sorted, _Lang lang) {
    if (sorted.isEmpty)
      return _r(lang, 'Koi masjid nahi mili.', 'No mosque found.');
    final m = sorted.first;
    final dist = m.hasCoordinates
        ? '${(m.distanceMeters / 1000).toStringAsFixed(1)} km'
        : '';
    final t = m.timings;
    final tp = <String>[];
    if ((t.fajr ?? '').isNotEmpty) tp.add('Fajr ${t.fajr}');
    if ((t.zohar ?? '').isNotEmpty) tp.add('Zohar ${t.zohar}');
    if ((t.asr ?? '').isNotEmpty) tp.add('Asr ${t.asr}');
    if ((t.maghrib ?? '').isNotEmpty) tp.add('Maghrib ${t.maghrib}');
    if ((t.isha ?? '').isNotEmpty) tp.add('Isha ${t.isha}');
    if ((t.juma ?? '').isNotEmpty) tp.add('Juma ${t.juma}');
    if (tp.isEmpty) {
      return _r(
          lang,
          '${m.name}${dist.isNotEmpty ? " ($dist door)" : ""} — timings abhi available nahi.',
          '${m.name}${dist.isNotEmpty ? " ($dist away)" : ""} — timings not available yet.');
    }
    return '${m.name}${dist.isNotEmpty ? " ($dist)" : ""}: ${tp.join(", ")}.';
  }

  String _allTimes(Map<String, String> pt, _Lang lang) {
    final p = <String>[];
    if ((pt['fajr'] ?? '').isNotEmpty) p.add('Fajr ${pt['fajr']}');
    if ((pt['zohar'] ?? '').isNotEmpty) p.add('Zohar ${pt['zohar']}');
    if ((pt['asr'] ?? '').isNotEmpty) p.add('Asr ${pt['asr']}');
    if ((pt['maghrib'] ?? '').isNotEmpty) p.add('Maghrib ${pt['maghrib']}');
    if ((pt['isha'] ?? '').isNotEmpty) p.add('Isha ${pt['isha']}');
    if (p.isEmpty)
      return _r(lang, 'Waqt available nahi.', 'Times not available.');
    return _r(lang, 'Aaj ke awqat: ', 'Today\'s times: ') + p.join('. ') + '.';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool _has(String q, List<String> kw) => kw.any((k) => q.contains(k));

  _Lang _detectLang(String q) {
    if (RegExp(r'[؀-ۿऀ-ॿ]').hasMatch(q)) return _Lang.hindi;
    const eng = [
      'what',
      'when',
      'where',
      'time',
      'prayer',
      'mosque',
      'navigate',
      'nearest',
      'find',
      'show',
      'tell',
      'is',
      'how',
      'direction',
      'today',
      'date',
      'next',
      'morning',
      'evening',
      'night',
      'afternoon',
      'open',
      'map',
      'me',
      'my'
    ];
    final count = q.split(RegExp(r'\s+')).where((w) => eng.contains(w)).length;
    return count >= 1 ? _Lang.english : _Lang.hindi;
  }

  dynamic _r(_Lang lang, dynamic hindi, dynamic english) =>
      lang == _Lang.english ? english : hindi;

  String _prayerDisplayName(String key) {
    const names = {
      'fajr': 'Fajr',
      'zohar': 'Zohar',
      'asr': 'Asr',
      'maghrib': 'Maghrib',
      'isha': 'Isha',
      'juma': 'Juma',
    };
    return names[key] ?? key;
  }

  Future<void> _speakAndShow(String text, _Lang lang) async {
    if (!mounted) return;
    setState(() {
      _responseText = text;
      _state = _AssistantState.responding;
    });
    await _tts.stop();
    final target = lang == _Lang.english ? 'en-IN' : 'hi-IN';
    if (_currentTtsLang != target) {
      _currentTtsLang = target;
      await _tts.setLanguage(target);
    }
    await _tts.speak(text);
  }

  String get _statusLabel => switch (_state) {
        _AssistantState.listening => 'Sun raha hoon...',
        _AssistantState.processing => 'Samajh raha hoon...',
        _AssistantState.responding => 'Bol raha hoon...',
        _AssistantState.idle =>
          _sttAvailable ? 'Mic dabao aur puchho' : 'Microphone unavailable',
      };

  // ═══════════════════════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isListening = _state == _AssistantState.listening;
    final isProcessing = _state == _AssistantState.processing;

    return Scaffold(
      backgroundColor: const Color(0xFF0A5C4A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Voice Assistant', style: TextStyle(fontSize: 16)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 8),
              const _HintCard(),
              const Spacer(),
              if (_recognizedText.isNotEmpty)
                _BubbleText(text: '"$_recognizedText"', isUser: true),
              if (isProcessing)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: _TypingIndicator(),
                )
              else if (_responseText.isNotEmpty) ...[
                const SizedBox(height: 12),
                _BubbleText(text: _responseText, isUser: false),
              ],
              const Spacer(),
              Text(_statusLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: isProcessing ? null : _toggleListening,
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, child) => Transform.scale(
                    scale: isListening ? _pulseAnim.value : 1.0,
                    child: child,
                  ),
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: isListening
                          ? Colors.red.shade600
                          : isProcessing
                              ? Colors.white.withValues(alpha: 0.5)
                              : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isListening ? Colors.red : Colors.white)
                              .withValues(alpha: 0.35),
                          blurRadius: 24,
                          spreadRadius: 6,
                        )
                      ],
                    ),
                    child: Icon(
                      isListening
                          ? Icons.stop_rounded
                          : isProcessing
                              ? Icons.hourglass_top_rounded
                              : Icons.mic_rounded,
                      color:
                          isListening ? Colors.white : const Color(0xFF0A5C4A),
                      size: 38,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Data class ──────────────────────────────────────────────────────────────

class _QueryContext {
  const _QueryContext({
    required this.today,
    required this.pt,
    required this.sorted,
    required this.jumaTime,
  });
  final dynamic today;
  final Map<String, String> pt;
  final List<Mosque> sorted;
  final String? jumaTime;
}

// ─── Hint card ───────────────────────────────────────────────────────────────

class _HintCard extends StatelessWidget {
  const _HintCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kuch aise puch sakte ho:',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          for (final hint in [
            '"Agli namaz kab hai?"',
            '"Nearest mosque le chalo"',
            '"What time is Fajr?"',
            '"Qareeb ki 3 masajid batao"',
            '"Aaj ki hijri tarikh?"',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('• $hint',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

// ─── Typing indicator ────────────────────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          _Dot(delay: 0),
          SizedBox(width: 4),
          _Dot(delay: 200),
          SizedBox(width: 4),
          _Dot(delay: 400),
        ]),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.delay});
  final int delay;
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
                color: Color(0xFF0A5C4A), shape: BoxShape.circle)),
      ),
    );
  }
}

// ─── Chat bubbles ────────────────────────────────────────────────────────────

class _BubbleText extends StatelessWidget {
  const _BubbleText({required this.text, required this.isUser});
  final String text;
  final bool isUser;
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? Colors.white.withValues(alpha: 0.18) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(text,
            style: TextStyle(
              color: isUser ? Colors.white : const Color(0xFF0A5C4A),
              fontSize: isUser ? 14 : 15,
              fontStyle: isUser ? FontStyle.italic : FontStyle.normal,
              fontWeight: isUser ? FontWeight.normal : FontWeight.w600,
            )),
      ),
    );
  }
}
