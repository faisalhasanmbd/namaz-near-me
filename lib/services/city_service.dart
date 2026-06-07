import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../data/cities.dart';

class CityService {
  CityService._();
  static final CityService instance = CityService._();

  // Merged list: hardcoded + user-added from Firestore
  List<CityInfo> _cities = indianCities;
  List<CityInfo> get all => _cities;

  // Load user-added cities from Firestore and merge with hardcoded list
  Future<void> load() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('cities')
          .where('approved', isEqualTo: true)
          .get();
      final fromFirestore = snap.docs.map((d) {
        final data = d.data();
        return CityInfo(
          name: data['name'] as String? ?? d.id,
          latitude: (data['latitude'] as num).toDouble(),
          longitude: (data['longitude'] as num).toDouble(),
          state: data['state'] as String? ?? '',
          country: data['country'] as String? ?? 'India',
        );
      }).toList();

      // Merge: hardcoded first (preserves known cities), then any Firestore-only cities
      final knownNames = indianCities.map((c) => c.name.toLowerCase()).toSet();
      final newCities = fromFirestore
          .where((c) => !knownNames.contains(c.name.toLowerCase()))
          .toList();
      _cities = [...indianCities, ...newCities]
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      // Keep hardcoded list on error — app still works
    }
  }

  // Phone-verified user adds a new city — goes live immediately
  Future<void> addCity({
    required String name,
    required String state,
    required String country,
    required double latitude,
    required double longitude,
    required String verifiedPhone,
  }) async {
    final docId = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    await FirebaseFirestore.instance.collection('cities').doc(docId).set({
      'name': name.trim(),
      'state': state.trim(),
      'country': country.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'added_by_phone_private': verifiedPhone,
      'added_at': FieldValue.serverTimestamp(),
      'approved': true, // phone verified = trusted, no admin needed
    });
    // Update local list immediately
    final city = CityInfo(
      name: name.trim(),
      state: state.trim(),
      country: country.trim(),
      latitude: latitude,
      longitude: longitude,
    );
    final knownNames = _cities.map((c) => c.name.toLowerCase()).toSet();
    if (!knownNames.contains(city.name.toLowerCase())) {
      _cities = [..._cities, city]..sort((a, b) => a.name.compareTo(b.name));
    }
  }
}
