String mosqueKey(String name) {
  return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String mosqueDocId(String mosqueName, String cityName, {String area = ''}) {
  String clean(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  final parts = [clean(cityName), clean(area), clean(mosqueName)]
      .where((s) => s.isNotEmpty)
      .join('-');
  final base = parts.replaceAll(RegExp(r'^-+|-+$'), '');
  return base.isEmpty ? 'mosque-unknown' : base;
}

String cityDateKey(String cityName) {
  return cityName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
}

String cityContributorDocId(String cityName, String uid) {
  return '${cityDateKey(cityName)}_$uid';
}

bool sameCity(String? left, String right) {
  return (left ?? '').toLowerCase().trim() == right.toLowerCase().trim();
}

String dateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
