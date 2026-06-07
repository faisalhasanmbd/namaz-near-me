import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/mosque.dart';

class UserLocation {
  const UserLocation({
    required this.latitude,
    required this.longitude,
    required this.isCurrentLocation,
  });

  final double latitude;
  final double longitude;
  final bool isCurrentLocation;
}

class LocationService {
  static const moradabadCenter = UserLocation(
    latitude: 28.8386,
    longitude: 78.7733,
    isCurrentLocation: false,
  );

  /// Returns null if GPS is off (caller should prompt user to enable it).
  /// Returns UserLocation if location obtained or fell back to city center.
  Future<bool> isLocationServiceEnabled() => Geolocator.isLocationServiceEnabled();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  Future<UserLocation> currentOrFallback() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return moradabadCenter;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return moradabadCenter;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 10));

      return UserLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        isCurrentLocation: true,
      );
    } catch (_) {
      return moradabadCenter;
    }
  }

  List<Mosque> applyDistances(List<Mosque> mosques, UserLocation location) {
    return mosques.map((mosque) {
      if (mosque.latitude == null || mosque.longitude == null) return mosque.withDistance(999999);
      final meters = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        mosque.latitude!,
        mosque.longitude!,
      ).round();
      return mosque.withDistance(meters);
    }).toList();
  }
}
