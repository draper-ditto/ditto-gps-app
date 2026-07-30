import 'package:ditto_gps/services/current_location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  final current = _position(33.7571, -84.3647);
  final cached = _position(33.7570, -84.3646);

  test('returns a fresh current position when available', () async {
    var lastKnownRequests = 0;
    final service = CurrentLocationService(
      loadCurrentPosition: () async => current,
      loadLastKnownPosition: () async {
        lastKnownRequests += 1;
        return cached;
      },
      checkLocationServiceEnabled: () async => true,
    );

    final result = await service.locate();

    expect(result.position, current);
    expect(result.isLastKnown, isFalse);
    expect(result.serviceReportedEnabled, isTrue);
    expect(lastKnownRequests, 0);
  });

  test('falls back to last-known position when a fresh fix fails', () async {
    final service = CurrentLocationService(
      loadCurrentPosition: () async => throw Exception('timed out'),
      loadLastKnownPosition: () async => cached,
      checkLocationServiceEnabled: () async => true,
    );

    final result = await service.locate();

    expect(result.position, cached);
    expect(result.isLastKnown, isTrue);
    expect(result.serviceReportedEnabled, isTrue);
  });

  test('Fire OS false-negative still returns its last-known Wi-Fi fix',
      () async {
    final service = CurrentLocationService(
      loadCurrentPosition: () async => throw Exception('service disabled'),
      loadLastKnownPosition: () async => cached,
      checkLocationServiceEnabled: () async => false,
    );

    final result = await service.locate();

    expect(result.position, cached);
    expect(result.isLastKnown, isTrue);
    expect(result.serviceReportedEnabled, isFalse);
  });

  test('Fire OS false-negative does not block a fresh Wi-Fi fix', () async {
    var lastKnownRequests = 0;
    final service = CurrentLocationService(
      loadCurrentPosition: () async => current,
      loadLastKnownPosition: () async {
        lastKnownRequests += 1;
        return cached;
      },
      checkLocationServiceEnabled: () async => false,
    );

    final result = await service.locate();

    expect(result.position, current);
    expect(result.isLastKnown, isFalse);
    expect(result.serviceReportedEnabled, isFalse);
    expect(lastKnownRequests, 0);
  });

  test('preserves the current-position error when no fallback exists',
      () async {
    final service = CurrentLocationService(
      loadCurrentPosition: () async => throw Exception('provider unavailable'),
      loadLastKnownPosition: () async => null,
      checkLocationServiceEnabled: () async => true,
    );

    await expectLater(
      service.locate(),
      throwsA(
        isA<CurrentLocationUnavailableException>().having(
          (error) => error.toString(),
          'message',
          contains('provider unavailable'),
        ),
      ),
    );
  });

  test('disabled guidance is deferred until current and fallback both fail',
      () async {
    final service = CurrentLocationService(
      loadCurrentPosition: () async => throw Exception('service disabled'),
      loadLastKnownPosition: () async => null,
      checkLocationServiceEnabled: () async => false,
    );

    await expectLater(
      service.locate(),
      throwsA(
        isA<CurrentLocationUnavailableException>()
            .having(
              (error) => error.serviceReportedEnabled,
              'serviceReportedEnabled',
              isFalse,
            )
            .having(
              (error) => error.toString(),
              'message',
              contains('service disabled'),
            ),
      ),
    );
  });

  test('fallback provider failure preserves the fresh-location diagnostic',
      () async {
    var currentRequests = 0;
    var fallbackRequests = 0;
    final service = CurrentLocationService(
      loadCurrentPosition: () async {
        currentRequests += 1;
        throw Exception('fresh location timed out');
      },
      loadLastKnownPosition: () async {
        fallbackRequests += 1;
        throw Exception('cache provider failed');
      },
      checkLocationServiceEnabled: () async => true,
    );

    await expectLater(
      service.locate(),
      throwsA(
        isA<CurrentLocationUnavailableException>()
            .having(
              (error) => error.serviceReportedEnabled,
              'serviceReportedEnabled',
              isTrue,
            )
            .having(
              (error) => error.toString(),
              'message',
              contains('fresh location timed out'),
            )
            .having(
              (error) => error.toString(),
              'message',
              isNot(contains('cache provider failed')),
            ),
      ),
    );
    expect(currentRequests, 1);
    expect(fallbackRequests, 1);
  });
}

Position _position(double latitude, double longitude) => Position(
      longitude: longitude,
      latitude: latitude,
      timestamp: DateTime.utc(2026, 7, 22),
      accuracy: 25,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
