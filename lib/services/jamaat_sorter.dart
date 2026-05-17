import '../models/mosque.dart';

const namazOrder = ['fajr', 'zohar', 'asr', 'maghrib', 'isha'];

int? _timeToMinutes(String? value) {
  if (value == null || !value.contains(':')) return null;
  final parts = value.split(':');
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  if (hours == null || minutes == null) return null;
  return hours * 60 + minutes;
}

NextJamaat? nextJamaatFor(
  NamazTiming timings, {
  required int currentMinutes,
  String namazFilter = 'all',
}) {
  final names = namazFilter == 'all'
      ? namazOrder
      : namazFilter == 'friday_all'
          ? ['fajr', 'juma', 'asr', 'maghrib', 'isha']
          : [namazFilter];
  final upcoming = <NextJamaat>[];

  for (final namaz in names) {
    final time = timings.byName(namaz);
    final timeMinutes = _timeToMinutes(time);
    if (time == null || timeMinutes == null) continue;

    final minutesUntil = timeMinutes >= currentMinutes
        ? timeMinutes - currentMinutes
        : 24 * 60 - currentMinutes + timeMinutes;

    upcoming.add(
      NextJamaat(
        namaz: namaz,
        time: time,
        minutesUntil: minutesUntil,
      ),
    );
  }

  if (upcoming.isEmpty) return null;
  upcoming.sort((a, b) => a.minutesUntil.compareTo(b.minutesUntil));
  return upcoming.first;
}

List<MosqueResult> sortMosquesForUser(
  List<Mosque> mosques, {
  required DateTime now,
  String namazFilter = 'all',
}) {
  final currentMinutes = now.hour * 60 + now.minute;
  final activeNamazFilter =
      namazFilter == 'all' && now.weekday == DateTime.friday
          ? 'friday_all'
          : namazFilter;

  final results = mosques
      .where((mosque) =>
          namazFilter == 'all' || mosque.timings.byName(namazFilter) != null)
      .map((mosque) {
    final next = nextJamaatFor(
      mosque.timings,
      currentMinutes: currentMinutes,
      namazFilter: activeNamazFilter,
    );
    return MosqueResult(mosque: mosque, nextJamaat: next);
  }).toList();

  results.sort((a, b) {
    final byDistance =
        a.mosque.distanceMeters.compareTo(b.mosque.distanceMeters);
    if (byDistance != 0) return byDistance;

    final aNext = a.nextJamaat;
    final bNext = b.nextJamaat;

    if (aNext != null && bNext == null) return -1;
    if (aNext == null && bNext != null) return 1;

    if (aNext != null && bNext != null) {
      final byTime = aNext.minutesUntil.compareTo(bNext.minutesUntil);
      if (byTime != 0) return byTime;
    }

    final byUpdated =
        b.mosque.timingUpdatedAt.compareTo(a.mosque.timingUpdatedAt);
    if (byUpdated != 0) return byUpdated;

    if (a.mosque.isVerified == b.mosque.isVerified) return 0;
    return b.mosque.isVerified ? 1 : -1;
  });

  return results;
}
