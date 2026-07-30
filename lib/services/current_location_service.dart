import 'package:geolocator/geolocator.dart';

typedef LoadCurrentPosition = Future<Position> Function();
typedef LoadLastKnownPosition = Future<Position?> Function();
typedef CheckLocationServiceEnabled = Future<bool> Function();

class CurrentLocationFix {
  const CurrentLocationFix({
    required this.position,
    required this.isLastKnown,
    required this.serviceReportedEnabled,
  });

  final Position position;
  final bool isLastKnown;
  final bool serviceReportedEnabled;
}

class CurrentLocationService {
  const CurrentLocationService({
    required LoadCurrentPosition loadCurrentPosition,
    required LoadLastKnownPosition loadLastKnownPosition,
    required CheckLocationServiceEnabled checkLocationServiceEnabled,
  })  : _loadCurrentPosition = loadCurrentPosition,
        _loadLastKnownPosition = loadLastKnownPosition,
        _checkLocationServiceEnabled = checkLocationServiceEnabled;

  factory CurrentLocationService.geolocator() => CurrentLocationService(
        loadCurrentPosition: () => Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        ),
        loadLastKnownPosition: Geolocator.getLastKnownPosition,
        checkLocationServiceEnabled: Geolocator.isLocationServiceEnabled,
      );

  final LoadCurrentPosition _loadCurrentPosition;
  final LoadLastKnownPosition _loadLastKnownPosition;
  final CheckLocationServiceEnabled _checkLocationServiceEnabled;

  Future<CurrentLocationFix> locate() async {
    final serviceReportedEnabled = await _checkLocationServiceEnabled();
    try {
      return CurrentLocationFix(
        position: await _loadCurrentPosition(),
        isLastKnown: false,
        serviceReportedEnabled: serviceReportedEnabled,
      );
    } catch (currentError) {
      try {
        final lastKnown = await _loadLastKnownPosition();
        if (lastKnown != null) {
          return CurrentLocationFix(
            position: lastKnown,
            isLastKnown: true,
            serviceReportedEnabled: serviceReportedEnabled,
          );
        }
      } catch (_) {
        // Preserve the fresh-location failure as the most useful diagnostic.
      }
      throw CurrentLocationUnavailableException(
        cause: currentError,
        serviceReportedEnabled: serviceReportedEnabled,
      );
    }
  }
}

class CurrentLocationUnavailableException implements Exception {
  const CurrentLocationUnavailableException({
    required this.cause,
    required this.serviceReportedEnabled,
  });

  final Object cause;
  final bool serviceReportedEnabled;

  @override
  String toString() => cause.toString();
}
