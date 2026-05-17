import 'dart:math' as math;
import '../models/daily_islamic_timings.dart';

class CityInfo {
  const CityInfo(
      {required this.name,
      required this.latitude,
      required this.longitude,
      required this.state});
  final String name;
  final double latitude;
  final double longitude;
  final String state;
}

const List<CityInfo> indianCities = [
  CityInfo(
      name: 'Moradabad',
      latitude: 28.8386,
      longitude: 78.7733,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Lucknow',
      latitude: 26.8467,
      longitude: 80.9462,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Kanpur',
      latitude: 26.4499,
      longitude: 80.3319,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Agra',
      latitude: 27.1767,
      longitude: 78.0081,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Varanasi',
      latitude: 25.3176,
      longitude: 82.9739,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Allahabad',
      latitude: 25.4358,
      longitude: 81.8463,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Bareilly',
      latitude: 28.3670,
      longitude: 79.4304,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Aligarh',
      latitude: 27.8974,
      longitude: 78.0880,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Meerut',
      latitude: 28.9845,
      longitude: 77.7064,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Saharanpur',
      latitude: 29.9640,
      longitude: 77.5461,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Gorakhpur',
      latitude: 26.7606,
      longitude: 83.3732,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Rampur',
      latitude: 28.8089,
      longitude: 79.0249,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Sambhal',
      latitude: 28.5906,
      longitude: 78.5685,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Amroha',
      latitude: 28.9042,
      longitude: 78.4677,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Muzaffarnagar',
      latitude: 29.4727,
      longitude: 77.7085,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Shahjahanpur',
      latitude: 27.8833,
      longitude: 79.9053,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Firozabad',
      latitude: 27.1591,
      longitude: 78.3957,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Mathura',
      latitude: 27.4924,
      longitude: 77.6737,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Budaun',
      latitude: 28.0368,
      longitude: 79.1268,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Hapur',
      latitude: 28.7300,
      longitude: 77.7757,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Etah',
      latitude: 27.5595,
      longitude: 78.6703,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Mainpuri',
      latitude: 27.2356,
      longitude: 79.0232,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Sitapur',
      latitude: 27.5622,
      longitude: 80.6820,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Hardoi',
      latitude: 27.3956,
      longitude: 80.1288,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Jhansi',
      latitude: 25.4484,
      longitude: 78.5685,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Ghaziabad',
      latitude: 28.6692,
      longitude: 77.4538,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Noida',
      latitude: 28.5355,
      longitude: 77.3910,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Lakhimpur',
      latitude: 27.9488,
      longitude: 80.7814,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Bahraich',
      latitude: 27.5742,
      longitude: 81.5956,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Faizabad',
      latitude: 26.7752,
      longitude: 82.1453,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Azamgarh',
      latitude: 26.0673,
      longitude: 83.1832,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Bijnor',
      latitude: 29.3724,
      longitude: 78.1360,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Pilibhit',
      latitude: 28.6312,
      longitude: 79.8039,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Etawah',
      latitude: 26.7849,
      longitude: 79.0228,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Fatehpur',
      latitude: 25.9300,
      longitude: 80.8120,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Sultanpur',
      latitude: 26.2648,
      longitude: 82.0727,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Gonda',
      latitude: 27.1303,
      longitude: 81.9607,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Balrampur',
      latitude: 27.4252,
      longitude: 82.1769,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Deoria',
      latitude: 26.5021,
      longitude: 83.7761,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Jaunpur',
      latitude: 25.7461,
      longitude: 82.6837,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Mirzapur',
      latitude: 25.1459,
      longitude: 82.5690,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Ghazipur',
      latitude: 25.5780,
      longitude: 83.5810,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Mau',
      latitude: 25.9429,
      longitude: 83.5598,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Pratapgarh',
      latitude: 25.8975,
      longitude: 81.9908,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Raebareli',
      latitude: 26.2350,
      longitude: 81.2404,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Modinagar',
      latitude: 28.8317,
      longitude: 77.5773,
      state: 'Uttar Pradesh'),
  CityInfo(
      name: 'Delhi', latitude: 28.6139, longitude: 77.2090, state: 'Delhi'),
  CityInfo(
      name: 'Gurugram',
      latitude: 28.4595,
      longitude: 77.0266,
      state: 'Haryana'),
  CityInfo(
      name: 'Faridabad',
      latitude: 28.4089,
      longitude: 77.3178,
      state: 'Haryana'),
  CityInfo(
      name: 'Nuh', latitude: 28.1041, longitude: 77.0019, state: 'Haryana'),
  CityInfo(
      name: 'Palwal', latitude: 28.1444, longitude: 77.3300, state: 'Haryana'),
  CityInfo(
      name: 'Jaipur',
      latitude: 26.9124,
      longitude: 75.7873,
      state: 'Rajasthan'),
  CityInfo(
      name: 'Jodhpur',
      latitude: 26.2389,
      longitude: 73.0243,
      state: 'Rajasthan'),
  CityInfo(
      name: 'Ajmer', latitude: 26.4499, longitude: 74.6399, state: 'Rajasthan'),
  CityInfo(
      name: 'Alwar', latitude: 27.5530, longitude: 76.6346, state: 'Rajasthan'),
  CityInfo(
      name: 'Bharatpur',
      latitude: 27.2152,
      longitude: 77.4941,
      state: 'Rajasthan'),
  CityInfo(
      name: 'Tonk', latitude: 26.1663, longitude: 75.7885, state: 'Rajasthan'),
  CityInfo(
      name: 'Patna', latitude: 25.5941, longitude: 85.1376, state: 'Bihar'),
  CityInfo(name: 'Gaya', latitude: 24.7955, longitude: 85.0002, state: 'Bihar'),
  CityInfo(
      name: 'Muzaffarpur',
      latitude: 26.1197,
      longitude: 85.3910,
      state: 'Bihar'),
  CityInfo(
      name: 'Darbhanga', latitude: 26.1542, longitude: 85.8918, state: 'Bihar'),
  CityInfo(
      name: 'Purnia', latitude: 25.7771, longitude: 87.4753, state: 'Bihar'),
  CityInfo(
      name: 'Araria', latitude: 26.1480, longitude: 87.4718, state: 'Bihar'),
  CityInfo(
      name: 'Kishanganj',
      latitude: 26.0944,
      longitude: 87.9416,
      state: 'Bihar'),
  CityInfo(
      name: 'Katihar', latitude: 25.5395, longitude: 87.5741, state: 'Bihar'),
  CityInfo(
      name: 'Bhagalpur', latitude: 25.2425, longitude: 86.9842, state: 'Bihar'),
  CityInfo(
      name: 'Sitamarhi', latitude: 26.5931, longitude: 85.4900, state: 'Bihar'),
  CityInfo(
      name: 'Madhubani', latitude: 26.3533, longitude: 86.0787, state: 'Bihar'),
  CityInfo(
      name: 'Samastipur',
      latitude: 25.8610,
      longitude: 85.7810,
      state: 'Bihar'),
  CityInfo(
      name: 'Mumbai',
      latitude: 19.0760,
      longitude: 72.8777,
      state: 'Maharashtra'),
  CityInfo(
      name: 'Pune',
      latitude: 18.5204,
      longitude: 73.8567,
      state: 'Maharashtra'),
  CityInfo(
      name: 'Nagpur',
      latitude: 21.1458,
      longitude: 79.0882,
      state: 'Maharashtra'),
  CityInfo(
      name: 'Aurangabad',
      latitude: 19.8762,
      longitude: 75.3433,
      state: 'Maharashtra'),
  CityInfo(
      name: 'Nashik',
      latitude: 19.9975,
      longitude: 73.7898,
      state: 'Maharashtra'),
  CityInfo(
      name: 'Malegaon',
      latitude: 20.5579,
      longitude: 74.5287,
      state: 'Maharashtra'),
  CityInfo(
      name: 'Nanded',
      latitude: 19.1383,
      longitude: 77.3210,
      state: 'Maharashtra'),
  CityInfo(
      name: 'Bhiwandi',
      latitude: 19.2967,
      longitude: 73.0630,
      state: 'Maharashtra'),
  CityInfo(
      name: 'Bangalore',
      latitude: 12.9716,
      longitude: 77.5946,
      state: 'Karnataka'),
  CityInfo(
      name: 'Mysore',
      latitude: 12.2958,
      longitude: 76.6394,
      state: 'Karnataka'),
  CityInfo(
      name: 'Hubli', latitude: 15.3647, longitude: 75.1240, state: 'Karnataka'),
  CityInfo(
      name: 'Gulbarga',
      latitude: 17.3297,
      longitude: 76.8343,
      state: 'Karnataka'),
  CityInfo(
      name: 'Bidar', latitude: 17.9104, longitude: 77.5199, state: 'Karnataka'),
  CityInfo(
      name: 'Bijapur',
      latitude: 16.8302,
      longitude: 75.7100,
      state: 'Karnataka'),
  CityInfo(
      name: 'Hyderabad',
      latitude: 17.3850,
      longitude: 78.4867,
      state: 'Telangana'),
  CityInfo(
      name: 'Warangal',
      latitude: 17.9784,
      longitude: 79.5941,
      state: 'Telangana'),
  CityInfo(
      name: 'Nizamabad',
      latitude: 18.6725,
      longitude: 78.0941,
      state: 'Telangana'),
  CityInfo(
      name: 'Kurnool',
      latitude: 15.8281,
      longitude: 78.0373,
      state: 'Andhra Pradesh'),
  CityInfo(
      name: 'Nellore',
      latitude: 14.4426,
      longitude: 79.9865,
      state: 'Andhra Pradesh'),
  CityInfo(
      name: 'Chennai',
      latitude: 13.0827,
      longitude: 80.2707,
      state: 'Tamil Nadu'),
  CityInfo(
      name: 'Vellore',
      latitude: 12.9165,
      longitude: 79.1325,
      state: 'Tamil Nadu'),
  CityInfo(
      name: 'Trichy',
      latitude: 10.7905,
      longitude: 78.7047,
      state: 'Tamil Nadu'),
  CityInfo(
      name: 'Madurai',
      latitude: 9.9252,
      longitude: 78.1198,
      state: 'Tamil Nadu'),
  CityInfo(
      name: 'Kozhikode',
      latitude: 11.2588,
      longitude: 75.7804,
      state: 'Kerala'),
  CityInfo(
      name: 'Malappuram',
      latitude: 11.0510,
      longitude: 76.0711,
      state: 'Kerala'),
  CityInfo(
      name: 'Thrissur', latitude: 10.5276, longitude: 76.2144, state: 'Kerala'),
  CityInfo(
      name: 'Kochi', latitude: 9.9312, longitude: 76.2673, state: 'Kerala'),
  CityInfo(
      name: 'Thiruvananthapuram',
      latitude: 8.5241,
      longitude: 76.9366,
      state: 'Kerala'),
  CityInfo(
      name: 'Kolkata',
      latitude: 22.5726,
      longitude: 88.3639,
      state: 'West Bengal'),
  CityInfo(
      name: 'Murshidabad',
      latitude: 24.1800,
      longitude: 88.2700,
      state: 'West Bengal'),
  CityInfo(
      name: 'Malda',
      latitude: 25.0108,
      longitude: 88.1415,
      state: 'West Bengal'),
  CityInfo(
      name: 'Howrah',
      latitude: 22.5958,
      longitude: 88.2636,
      state: 'West Bengal'),
  CityInfo(
      name: 'Guwahati', latitude: 26.1445, longitude: 91.7362, state: 'Assam'),
  CityInfo(
      name: 'Silchar', latitude: 24.8333, longitude: 92.7789, state: 'Assam'),
  CityInfo(
      name: 'Bhopal',
      latitude: 23.2599,
      longitude: 77.4126,
      state: 'Madhya Pradesh'),
  CityInfo(
      name: 'Indore',
      latitude: 22.7196,
      longitude: 75.8577,
      state: 'Madhya Pradesh'),
  CityInfo(
      name: 'Jabalpur',
      latitude: 23.1815,
      longitude: 79.9864,
      state: 'Madhya Pradesh'),
  CityInfo(
      name: 'Ujjain',
      latitude: 23.1765,
      longitude: 75.7885,
      state: 'Madhya Pradesh'),
  CityInfo(
      name: 'Gwalior',
      latitude: 26.2183,
      longitude: 78.1828,
      state: 'Madhya Pradesh'),
  CityInfo(
      name: 'Ahmedabad',
      latitude: 23.0225,
      longitude: 72.5714,
      state: 'Gujarat'),
  CityInfo(
      name: 'Surat', latitude: 21.1702, longitude: 72.8311, state: 'Gujarat'),
  CityInfo(
      name: 'Vadodara',
      latitude: 22.3072,
      longitude: 73.1812,
      state: 'Gujarat'),
  CityInfo(
      name: 'Bharuch', latitude: 21.7051, longitude: 72.9959, state: 'Gujarat'),
  CityInfo(
      name: 'Anand', latitude: 22.5645, longitude: 72.9289, state: 'Gujarat'),
  CityInfo(
      name: 'Ludhiana', latitude: 30.9010, longitude: 75.8573, state: 'Punjab'),
  CityInfo(
      name: 'Amritsar', latitude: 31.6340, longitude: 74.8723, state: 'Punjab'),
  CityInfo(
      name: 'Jalandhar',
      latitude: 31.3260,
      longitude: 75.5762,
      state: 'Punjab'),
  CityInfo(
      name: 'Srinagar', latitude: 34.0837, longitude: 74.7973, state: 'J&K'),
  CityInfo(name: 'Jammu', latitude: 32.7357, longitude: 74.8691, state: 'J&K'),
  CityInfo(
      name: 'Anantnag', latitude: 33.7311, longitude: 75.1487, state: 'J&K'),
  CityInfo(name: 'Sopore', latitude: 34.2996, longitude: 74.4710, state: 'J&K'),
  CityInfo(
      name: 'Baramulla', latitude: 34.2094, longitude: 74.3429, state: 'J&K'),
  CityInfo(
      name: 'Dehradun',
      latitude: 30.3165,
      longitude: 78.0322,
      state: 'Uttarakhand'),
  CityInfo(
      name: 'Haridwar',
      latitude: 29.9457,
      longitude: 78.1642,
      state: 'Uttarakhand'),
  CityInfo(
      name: 'Roorkee',
      latitude: 29.8543,
      longitude: 77.8880,
      state: 'Uttarakhand'),
];

class IslamicTimingService {
  final double latitude;
  final double longitude;
  static const _timezoneOffsetMinutes = 330;
  static const _fajrAngle = -18.0;
  static const _ishaAngle = -18.0;

  IslamicTimingService({this.latitude = 28.8386, this.longitude = 78.7733});

  DailyIslamicTimings today({DateTime? now}) {
    final date = now ?? DateTime.now();
    final sunrise = _solarTime(date, -0.833, beforeNoon: true);
    final sunset = _solarTime(date, -0.833, beforeNoon: false);
    final fajr = _solarTime(date, _fajrAngle, beforeNoon: true);
    final isha = _solarTime(date, _ishaAngle, beforeNoon: false);
    final zohar = _solarNoonMinutes(date).round();
    final asr = _asrTime(date, shadowFactor: 2);
    final sehriEnd = fajr - 6;
    final zawalStart = zohar - 10;
    final zawalEnd = zohar - 1;
    final tahajjudStart =
        _normalizeMinutes(isha + _nightLength(isha, fajr) ~/ 2);
    return DailyIslamicTimings(
      weekday: _weekday(date),
      englishDate: _englishDate(date),
      hijriDate: _hijriDate(date),
      entries: [
        IslamicTimeEntry(label: 'Khatm Sehri', time: _formatTime(sehriEnd)),
        IslamicTimeEntry(label: 'Waqt Fajr', time: _formatTime(fajr)),
        IslamicTimeEntry(label: 'Sunrise', time: _formatTime(sunrise)),
        IslamicTimeEntry(
          label: 'Zawal',
          time: '${_formatTime(zawalStart)} - ${_formatTime(zawalEnd)}',
        ),
        IslamicTimeEntry(label: 'Waqt Zohar', time: _formatTime(zohar)),
        IslamicTimeEntry(label: 'Waqt Asr', time: _formatTime(asr)),
        IslamicTimeEntry(label: 'Maghrib/Iftar', time: _formatTime(sunset)),
        IslamicTimeEntry(label: 'Waqt Isha', time: _formatTime(isha)),
        IslamicTimeEntry(
          label: 'Tahajjud',
          time: '${_formatTime(tahajjudStart)} - ${_formatTime(fajr)}',
        ),
        IslamicTimeEntry(
          label: 'Roza',
          time: '${_formatTime(sehriEnd)} - ${_formatTime(sunset)}',
        ),
      ],
    );
  }

  double _solarNoonMinutes(DateTime date) {
    final day = _dayOfYear(date);
    final eqTime = _equationOfTime(day);
    return 720 - 4 * longitude - eqTime + _timezoneOffsetMinutes;
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
    return '$h12:${min.toString().padLeft(2, "0")} $p';
  }

  static String _englishDate(DateTime d) {
    return '${d.day.toString().padLeft(2, "0")} ${_month(d.month)} ${d.year}';
  }

  static String _hijriDate(DateTime date) {
    final h = _gregorianToHijri(date);
    return '${h.day} ${_hijriMonth(h.month)} ${h.year}';
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
        'Shaaban',
        'Ramadan',
        'Shawwal',
        "Zi'Qadah",
        'Zil Hijjah'
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
