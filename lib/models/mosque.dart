class NamazTiming {
  const NamazTiming({
    this.fajr,
    this.zohar,
    this.asr,
    this.maghrib,
    this.isha,
    this.juma,
    this.eidUlFitr,
    this.eidUlAzha,
  });

  final String? fajr;
  final String? zohar;
  final String? asr;
  final String? maghrib;
  final String? isha;
  final String? juma;
  final String? eidUlFitr;
  final String? eidUlAzha;

  String? byName(String namaz) {
    switch (namaz) {
      case 'fajr':
        return fajr;
      case 'zohar':
        return zohar;
      case 'asr':
        return asr;
      case 'maghrib':
        return maghrib;
      case 'isha':
        return isha;
      case 'juma':
        return juma;
      case 'eid':
        return eidUlFitr ?? eidUlAzha;
      case 'eid_ul_fitr':
        return eidUlFitr;
      case 'eid_ul_azha':
        return eidUlAzha;
      default:
        return null;
    }
  }
}

class PrayerEditMeta {
  const PrayerEditMeta({
    required this.name,
    required this.updatedAt,
    this.phone,
    this.value,
  });

  final String name;
  final DateTime updatedAt;
  final String? phone;
  final String? value;
}

class Mosque {
  const Mosque({
    required this.name,
    this.city,
    required this.area,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.hasOwnCoordinates = false,
    required this.distanceMeters,
    required this.timings,
    required this.isVerified,
    required this.timingVerificationStatus,
    this.timingVerifiedByName,
    this.timingVerifiedByPhone,
    required this.timingUpdatedAt,
    this.addedByName,
    this.addedByPhone,
    this.addedAt,
    this.prayerEditMeta = const {},
    this.placeId,
    this.firestoreDocId,
    this.needsReview = false,
  });

  final String name;
  final String? city;
  final String area;
  final String address;
  final double? latitude;
  final double? longitude;
  final bool hasOwnCoordinates;
  final int distanceMeters;
  final NamazTiming timings;
  final bool isVerified;
  final String timingVerificationStatus;
  final String? timingVerifiedByName;
  final String? timingVerifiedByPhone;
  final DateTime timingUpdatedAt;
  final String? addedByName;
  final String? addedByPhone;
  final DateTime? addedAt;
  final Map<String, PrayerEditMeta> prayerEditMeta;
  final String? placeId;
  final String? firestoreDocId;
  final bool needsReview;

  bool get hasCoordinates => hasOwnCoordinates && latitude != null && longitude != null;
  bool get hasAnyTiming {
    return timings.fajr != null ||
        timings.zohar != null ||
        timings.asr != null ||
        timings.maghrib != null ||
        timings.isha != null ||
        timings.juma != null;
  }

  Mosque withDistance(int distanceMeters) {
    return Mosque(
      name: name,
      city: city,
      area: area,
      address: address,
      latitude: latitude,
      longitude: longitude,
      hasOwnCoordinates: hasOwnCoordinates,
      distanceMeters: distanceMeters,
      timings: timings,
      isVerified: isVerified,
      timingVerificationStatus: timingVerificationStatus,
      timingVerifiedByName: timingVerifiedByName,
      timingVerifiedByPhone: timingVerifiedByPhone,
      timingUpdatedAt: timingUpdatedAt,
      addedByName: addedByName,
      addedByPhone: addedByPhone,
      addedAt: addedAt,
      prayerEditMeta: prayerEditMeta,
      placeId: placeId,
      firestoreDocId: firestoreDocId,
      needsReview: needsReview,
    );
  }

  Mosque copyWith({
    String? name,
    String? city,
    String? area,
    String? address,
    double? latitude,
    double? longitude,
    bool? hasOwnCoordinates,
    int? distanceMeters,
    NamazTiming? timings,
    bool? isVerified,
    String? timingVerificationStatus,
    String? timingVerifiedByName,
    String? timingVerifiedByPhone,
    DateTime? timingUpdatedAt,
    String? addedByName,
    String? addedByPhone,
    DateTime? addedAt,
    Map<String, PrayerEditMeta>? prayerEditMeta,
    String? placeId,
    String? firestoreDocId,
    bool? needsReview,
  }) {
    return Mosque(
      name: name ?? this.name,
      city: city ?? this.city,
      area: area ?? this.area,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      hasOwnCoordinates: hasOwnCoordinates ?? this.hasOwnCoordinates,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      timings: timings ?? this.timings,
      isVerified: isVerified ?? this.isVerified,
      timingVerificationStatus:
          timingVerificationStatus ?? this.timingVerificationStatus,
      timingVerifiedByName: timingVerifiedByName ?? this.timingVerifiedByName,
      timingVerifiedByPhone:
          timingVerifiedByPhone ?? this.timingVerifiedByPhone,
      timingUpdatedAt: timingUpdatedAt ?? this.timingUpdatedAt,
      addedByName: addedByName ?? this.addedByName,
      addedByPhone: addedByPhone ?? this.addedByPhone,
      addedAt: addedAt ?? this.addedAt,
      prayerEditMeta: prayerEditMeta ?? this.prayerEditMeta,
      placeId: placeId ?? this.placeId,
      firestoreDocId: firestoreDocId ?? this.firestoreDocId,
      needsReview: needsReview ?? this.needsReview,
    );
  }
}

class NextJamaat {
  const NextJamaat({
    required this.namaz,
    required this.time,
    required this.minutesUntil,
  });

  final String namaz;
  final String time;
  final int minutesUntil;

  String get startsIn {
    if (minutesUntil < 60) return '$minutesUntil min';
    final hours = minutesUntil ~/ 60;
    final minutes = minutesUntil % 60;
    if (minutes == 0) return '$hours hr';
    return '$hours hr $minutes min';
  }
}

class MosqueResult {
  const MosqueResult({required this.mosque, this.nextJamaat});

  final Mosque mosque;
  final NextJamaat? nextJamaat;
}
