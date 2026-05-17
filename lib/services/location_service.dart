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
      );

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
      if (!mosque.hasCoordinates) return mosque.withDistance(999999);
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
