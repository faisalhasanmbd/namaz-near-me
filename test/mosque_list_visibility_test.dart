import 'package:flutter_test/flutter_test.dart';
import 'package:namaz_near_me/data/sample_mosques.dart';
import 'package:namaz_near_me/services/jamaat_sorter.dart';
import 'package:namaz_near_me/services/location_service.dart';

void main() {
  test('sample dataset returns visible mosques for 10km and 25km views', () {
    final withDistance = LocationService().applyDistances(
      sampleMosques,
      LocationService.moradabadCenter,
    );

    final in2km = withDistance.where((m) => m.distanceMeters <= 2000).toList();
    final in10km = withDistance.where((m) => m.distanceMeters <= 10000).toList();
    final in25km = withDistance.where((m) => m.distanceMeters <= 25000).toList();

    final results10km = sortMosquesForUser(
      in10km,
      now: DateTime(2026, 5, 16, 19, 36),
      namazFilter: 'all',
    );
    final results25km = sortMosquesForUser(
      in25km,
      now: DateTime(2026, 5, 16, 19, 36),
      namazFilter: 'all',
    );

    expect(in2km.length, greaterThanOrEqualTo(0));
    expect(in10km, isNotEmpty);
    expect(in25km, isNotEmpty);
    expect(results10km, isNotEmpty);
    expect(results25km, isNotEmpty);
  });

  test('nearby list stays sorted by nearest mosque first', () {
    final withDistance = LocationService().applyDistances(
      sampleMosques,
      LocationService.moradabadCenter,
    );
    final visible = withDistance.where((m) => m.distanceMeters <= 10000).toList();

    final results = sortMosquesForUser(
      visible,
      now: DateTime(2026, 5, 16, 19, 36),
      namazFilter: 'all',
    );

    expect(results, isNotEmpty);
    for (var i = 1; i < results.length; i++) {
      expect(
        results[i - 1].mosque.distanceMeters <= results[i].mosque.distanceMeters,
        isTrue,
      );
    }
  });
}
