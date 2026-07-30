import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

typedef CheckLocationPermission = Future<LocationPermission> Function();
typedef RequestLocationPermission = Future<LocationPermission> Function();

class LocationPermissionFlow {
  const LocationPermissionFlow({
    required CheckLocationPermission checkPermission,
    required RequestLocationPermission requestPermission,
  })  : _checkPermission = checkPermission,
        _requestPermission = requestPermission;

  factory LocationPermissionFlow.geolocator() => const LocationPermissionFlow(
        checkPermission: Geolocator.checkPermission,
        requestPermission: Geolocator.requestPermission,
      );

  final CheckLocationPermission _checkPermission;
  final RequestLocationPermission _requestPermission;

  Future<LocationPermission> request({
    required Future<bool> Function() onDenied,
    required Future<void> Function() onBlocked,
  }) async {
    var permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }

    if (permission == LocationPermission.denied) {
      final retry = await onDenied();
      if (retry) permission = await _requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      await onBlocked();
    }
    return permission;
  }
}

bool canOpenLocationAppSettings({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return !isWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
}

bool canOpenLocationServiceSettings({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return !isWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
}

String locationServicesDisabledInstructions({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) {
    return 'Location services are unavailable. Allow Location in the browser '
        'site settings and in your computer privacy settings, then try again.';
  }
  return switch (platform) {
    TargetPlatform.android =>
      'Device location services are turned off. Open Location settings, turn '
          'on Location, return to Draper TAK, and tap Use current location '
          'again. Fire tablets use Wi-Fi-based location, so Wi-Fi must also '
          'remain enabled.',
    TargetPlatform.iOS =>
      'Device location services are turned off. Open Location settings, turn '
          'on Location Services, return to Draper TAK, and try again.',
    TargetPlatform.macOS =>
      'Open System Settings, then Privacy & Security > Location Services. Turn '
          'on Location Services and try again.',
    TargetPlatform.windows =>
      'Open Windows Settings, then Privacy & security > Location. Turn on '
          'Location services and try again.',
    TargetPlatform.linux ||
    TargetPlatform.fuchsia =>
      'Turn on location services in your system privacy settings and try again.',
  };
}

String locationUnavailableInstructions({
  required bool isWeb,
  required TargetPlatform platform,
  required Object error,
}) {
  final diagnostic = error.toString();
  if (!isWeb && platform == TargetPlatform.android) {
    return 'A current location fix was not available and this device has no '
        'last-known location. Keep Wi-Fi and device Location enabled, then try '
        'again. Many Fire tablets use Wi-Fi-based location instead of GPS. '
        'You can also enter coordinates manually.\n\nDetails: $diagnostic';
  }
  return 'A current or last-known location was not available. Check location '
      'services and try again, or enter coordinates manually.\n\n'
      'Details: $diagnostic';
}

String blockedLocationInstructions({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) {
    return 'Your browser has blocked location access for this site. Allow '
        'Location in the browser site settings, reload the page, and try again.';
  }
  return switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.iOS =>
      'Your device will no longer show the permission prompt. Open the app '
          'settings, allow location access for Draper TAK, return to the app, '
          'and tap Use current location again.',
    TargetPlatform.macOS =>
      'Open System Settings, then Privacy & Security > Location Services. '
          'Allow location access for Draper TAK and try again.',
    TargetPlatform.windows =>
      'Open Windows Settings, then Privacy & security > Location. Allow '
          'location access for Draper TAK and try again.',
    TargetPlatform.linux ||
    TargetPlatform.fuchsia =>
      'Allow location access for Draper TAK in your system privacy settings, '
          'then try again.',
  };
}
