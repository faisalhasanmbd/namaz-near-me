import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const _apiKey = String.fromEnvironment('GOOGLE_PLACES_API_KEY', defaultValue: '');

class PlacesMosque {
  const PlacesMosque({
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.rating,
  });
  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final double? rating;
}

class PlacesService {
  static Future<List<PlacesMosque>> nearbyMosques({
    required double latitude,
    required double longitude,
    int radiusMeters = 10000,
  }) async {
    if (_apiKey.isEmpty) {
      debugPrint(
        'PlacesService disabled: GOOGLE_PLACES_API_KEY not provided via --dart-define.',
      );
      return [];
    }
    final url = Uri.parse('https://places.googleapis.com/v1/places:searchNearby');
    final body = json.encode({
      'includedTypes': ['mosque'],
      'maxResultCount': 20,
      'locationRestriction': {
        'circle': {
          'center': {
            'latitude': latitude,
            'longitude': longitude,
          },
          'radius': radiusMeters.toDouble(),
        }
      }
    });

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'places.displayName,places.formattedAddress,places.location,places.id,places.rating',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      debugPrint('Status: ${response.statusCode}');
      debugPrint(
        'Body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}',
      );
      if (response.statusCode != 200) {
        return [];
      }

      final data = json.decode(response.body);
      final results = data['places'] as List? ?? [];

      return results
          .where((place) {
            final loc = place['location'];
            return loc != null &&
                loc['latitude'] != null &&
                loc['longitude'] != null;
          })
          .map((place) {
            final loc = place['location'];
            return PlacesMosque(
              placeId: place['id'] ?? '',
              name: place['displayName']?['text'] ?? 'Mosque',
              address: place['formattedAddress'] ?? '',
              latitude: (loc['latitude'] as num).toDouble(),
              longitude: (loc['longitude'] as num).toDouble(),
              rating: (place['rating'] as num?)?.toDouble(),
            );
          })
          .toList();
    } catch (e) {
      debugPrint('Places error: $e');
      return [];
    }
  }
}
