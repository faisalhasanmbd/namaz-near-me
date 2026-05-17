class IslamicTimeEntry {
  const IslamicTimeEntry({
    required this.label,
    required this.time,
  });

  final String label;
  final String time;
}

class DailyIslamicTimings {
  const DailyIslamicTimings({
    required this.weekday,
    required this.englishDate,
    required this.hijriDate,
    required this.entries,
  });

  final String weekday;
  final String englishDate;
  final String hijriDate;
  final List<IslamicTimeEntry> entries;
}
