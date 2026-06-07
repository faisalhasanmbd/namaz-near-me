import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../data/cities.dart';

/// Automatically seeds mosque data from OpenStreetMap the first time
/// a user opens a city that has no mosques in Firestore.
class CitySeederService {
  CitySeederService._();
  static final CitySeederService instance = CitySeederService._();

  final _seededThisSession = <String>{};

  /// Call this when mosque stream returns empty for a city.
  /// Does nothing if city was already seeded, or is currently seeding.
  Future<void> seedIfNeeded(CityInfo city) async {
    if (Firebase.apps.isEmpty) return;
    final key = city.name.toLowerCase();
    if (_seededThisSession.contains(key)) return;
    _seededThisSession.add(key); // prevent concurrent duplicate seeds

    try {
      final statusRef = FirebaseFirestore.instance
          .collection('city_seed_status')
          .doc(key);
      final status = await statusRef.get();

      // Already seeded before — don't re-seed
      if (status.exists && status.data()?['seeded'] == true) return;

      debugPrint('CitySeeder: seeding ${city.name} from OpenStreetMap...');
      await statusRef.set({
        'city': city.name,
        'seeding': true,
        'started_at': FieldValue.serverTimestamp(),
      });

      final mosques = await _fetchFromOSM(city);
      if (mosques.isEmpty) {
        await statusRef.set({
          'city': city.name,
          'seeded': true,
          'count': 0,
          'note': 'no_results_from_osm',
          'seeded_at': FieldValue.serverTimestamp(),
        });
        return;
      }

      int created = 0;
      for (final doc in mosques) {
        final id = _mosqueDocId(doc['name'] as String, city.name);
        final ref = FirebaseFirestore.instance.collection('mosques').doc(id);
        final snap = await ref.get();
        if (snap.exists) continue;
        await ref.set(doc);
        created++;
      }

      await statusRef.set({
        'city': city.name,
        'seeded': true,
        'count': created,
        'seeded_at': FieldValue.serverTimestamp(),
      });
      debugPrint('CitySeeder: seeded $created mosques for ${city.name}');
    } catch (e) {
      debugPrint('CitySeeder error for ${city.name}: $e');
      _seededThisSession.remove(key); // allow retry on next empty result
    }
  }

  Future<List<Map<String, dynamic>>> _fetchFromOSM(CityInfo city) async {
    const radiusMeters = 12000;
    final query = '''
[out:json][timeout:30];
(
  node["amenity"="place_of_worship"]["religion"="muslim"]
    (around:$radiusMeters,${city.latitude},${city.longitude});
  way["amenity"="place_of_worship"]["religion"="muslim"]
    (around:$radiusMeters,${city.latitude},${city.longitude});
);
out center tags;
''';

    final uri = Uri.parse('https://overpass-api.de/api/interpreter');
    final resp = await http.post(
      uri,
      body: {'data': query},
    ).timeout(const Duration(seconds: 40));

    if (resp.statusCode != 200) return [];

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final elements = (json['elements'] as List?) ?? [];

    final results = <Map<String, dynamic>>[];
    for (final el in elements) {
      final tags = (el['tags'] as Map?) ?? {};
      final name = (tags['name'] ??
              tags['name:en'] ??
              tags['name:ur'] ??
              tags['name:hi'] ??
              tags['name:ar'] ??
              '')
          .toString()
          .trim();
      if (name.isEmpty) continue;

      final elLat = (el['lat'] ?? el['center']?['lat']) as num?;
      final elLng = (el['lon'] ?? el['center']?['lon']) as num?;

      final doc = <String, dynamic>{
        'name': name,
        'city': city.name,
        'state': city.state,
        'country': city.country,
        'area': tags['addr:suburb'] ?? tags['addr:neighbourhood'] ?? '',
        'address': [
          tags['addr:housenumber'],
          tags['addr:street'],
        ].where((v) => v != null && v.toString().isNotEmpty).join(', '),
        'timing_verification_status': 'unverified',
        'source': 'openstreetmap',
        'osm_id': el['id']?.toString(),
        'uploaded_from': 'app_auto_seed',
        'created_at': FieldValue.serverTimestamp(),
      };

      if (elLat != null && elLng != null) {
        doc['latitude']  = elLat.toDouble();
        doc['longitude'] = elLng.toDouble();
      }
      if (tags['name:ar'] != null) doc['name_ar'] = tags['name:ar'];
      if (tags['name:en'] != null) doc['name_en'] = tags['name:en'];

      results.add(doc);
    }
    return results;
  }

  String _mosqueDocId(String name, String city) {
    String clean(String v) => v
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final base = '${clean(city)}-${clean(name)}'.replaceAll(RegExp(r'^-+|-+$'), '');
    return base.isEmpty ? 'mosque-unknown' : base;
  }
}
