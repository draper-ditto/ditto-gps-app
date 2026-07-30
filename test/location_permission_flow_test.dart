import 'package:ditto_gps/services/location_permission_flow.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  test('already granted permission does not request or show UI', () async {
    var requests = 0;
    var deniedPrompts = 0;
    var blockedPrompts = 0;
    final flow = LocationPermissionFlow(
      checkPermission: () async => LocationPermission.whileInUse,
      requestPermission: () async {
        requests += 1;
        return LocationPermission.whileInUse;
      },
    );

    final result = await flow.request(
      onDenied: () async {
        deniedPrompts += 1;
        return false;
      },
      onBlocked: () async => blockedPrompts += 1,
    );

    expect(result, LocationPermission.whileInUse);
    expect(requests, 0);
    expect(deniedPrompts, 0);
    expect(blockedPrompts, 0);
  });

  test('always permission does not request foreground permission again',
      () async {
    var requests = 0;
    final flow = LocationPermissionFlow(
      checkPermission: () async => LocationPermission.always,
      requestPermission: () async {
        requests += 1;
        return LocationPermission.always;
      },
    );

    final result = await flow.request(
      onDenied: () async => false,
      onBlocked: () async {},
    );

    expect(result, LocationPermission.always);
    expect(requests, 0);
  });

  test('undetermined browser permission is returned without native prompts',
      () async {
    var requests = 0;
    var deniedPrompts = 0;
    var blockedPrompts = 0;
    final flow = LocationPermissionFlow(
      checkPermission: () async => LocationPermission.unableToDetermine,
      requestPermission: () async {
        requests += 1;
        return LocationPermission.unableToDetermine;
      },
    );

    final result = await flow.request(
      onDenied: () async {
        deniedPrompts += 1;
        return false;
      },
      onBlocked: () async => blockedPrompts += 1,
    );

    expect(result, LocationPermission.unableToDetermine);
    expect(requests, 0);
    expect(deniedPrompts, 0);
    expect(blockedPrompts, 0);
  });

  test('initial denial requests system permission once', () async {
    var requests = 0;
    final flow = LocationPermissionFlow(
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async {
        requests += 1;
        return LocationPermission.always;
      },
    );

    final result = await flow.request(
      onDenied: () async => false,
      onBlocked: () async {},
    );

    expect(result, LocationPermission.always);
    expect(requests, 1);
  });

  test('denied permission can be requested again after user confirms',
      () async {
    var requests = 0;
    var deniedPrompts = 0;
    final flow = LocationPermissionFlow(
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async {
        requests += 1;
        return requests == 1
            ? LocationPermission.denied
            : LocationPermission.whileInUse;
      },
    );

    final result = await flow.request(
      onDenied: () async {
        deniedPrompts += 1;
        return true;
      },
      onBlocked: () async {},
    );

    expect(result, LocationPermission.whileInUse);
    expect(requests, 2);
    expect(deniedPrompts, 1);
  });

  test('declining the second prompt preserves denied result', () async {
    var requests = 0;
    final flow = LocationPermissionFlow(
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async {
        requests += 1;
        return LocationPermission.denied;
      },
    );

    final result = await flow.request(
      onDenied: () async => false,
      onBlocked: () async {},
    );

    expect(result, LocationPermission.denied);
    expect(requests, 1);
  });

  test('blocked permission displays settings guidance', () async {
    var blockedPrompts = 0;
    final flow = LocationPermissionFlow(
      checkPermission: () async => LocationPermission.deniedForever,
      requestPermission: () async => LocationPermission.deniedForever,
    );

    final result = await flow.request(
      onDenied: () async => false,
      onBlocked: () async => blockedPrompts += 1,
    );

    expect(result, LocationPermission.deniedForever);
    expect(blockedPrompts, 1);
  });

  test('denied retry that becomes blocked displays settings guidance',
      () async {
    var requests = 0;
    var blockedPrompts = 0;
    final flow = LocationPermissionFlow(
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async {
        requests += 1;
        return requests == 1
            ? LocationPermission.denied
            : LocationPermission.deniedForever;
      },
    );

    final result = await flow.request(
      onDenied: () async => true,
      onBlocked: () async => blockedPrompts += 1,
    );

    expect(result, LocationPermission.deniedForever);
    expect(requests, 2);
    expect(blockedPrompts, 1);
  });

  test('initial permission request that becomes blocked opens guidance once',
      () async {
    var requests = 0;
    var deniedPrompts = 0;
    var blockedPrompts = 0;
    final flow = LocationPermissionFlow(
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async {
        requests += 1;
        return LocationPermission.deniedForever;
      },
    );

    final result = await flow.request(
      onDenied: () async {
        deniedPrompts += 1;
        return false;
      },
      onBlocked: () async => blockedPrompts += 1,
    );

    expect(result, LocationPermission.deniedForever);
    expect(requests, 1);
    expect(deniedPrompts, 0);
    expect(blockedPrompts, 1);
  });

  test('app settings can only open directly on native Android and iOS', () {
    expect(
      canOpenLocationAppSettings(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      isTrue,
    );
    expect(
      canOpenLocationAppSettings(isWeb: false, platform: TargetPlatform.iOS),
      isTrue,
    );
    expect(
      canOpenLocationAppSettings(isWeb: true, platform: TargetPlatform.android),
      isFalse,
    );
    expect(
      canOpenLocationAppSettings(isWeb: false, platform: TargetPlatform.macOS),
      isFalse,
    );
  });

  test('location service settings open directly on native Android and iOS', () {
    expect(
      canOpenLocationServiceSettings(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      isTrue,
    );
    expect(
      canOpenLocationServiceSettings(
        isWeb: false,
        platform: TargetPlatform.iOS,
      ),
      isTrue,
    );
    expect(
      canOpenLocationServiceSettings(
        isWeb: true,
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
  });

  test('blocked instructions are platform-specific', () {
    expect(
      blockedLocationInstructions(
        isWeb: true,
        platform: TargetPlatform.macOS,
      ),
      contains('browser site settings'),
    );
    expect(
      blockedLocationInstructions(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      contains('Open the app settings'),
    );
    expect(
      blockedLocationInstructions(
        isWeb: false,
        platform: TargetPlatform.macOS,
      ),
      contains('System Settings'),
    );
    expect(
      blockedLocationInstructions(
        isWeb: false,
        platform: TargetPlatform.windows,
      ),
      contains('Windows Settings'),
    );
    expect(
      blockedLocationInstructions(
        isWeb: false,
        platform: TargetPlatform.linux,
      ),
      contains('system privacy settings'),
    );
  });

  test('disabled Android instructions explain Fire Wi-Fi location', () {
    final instructions = locationServicesDisabledInstructions(
      isWeb: false,
      platform: TargetPlatform.android,
    );

    expect(instructions, contains('Open Location settings'));
    expect(instructions, contains('Fire tablets'));
    expect(instructions, contains('Wi-Fi'));
  });

  test('disabled web instructions route users to browser and system privacy',
      () {
    final instructions = locationServicesDisabledInstructions(
      isWeb: true,
      platform: TargetPlatform.android,
    );

    expect(instructions, contains('browser site settings'));
    expect(instructions, contains('computer privacy settings'));
    expect(instructions, isNot(contains('Fire tablets')));
  });

  test('disabled iOS instructions route users to Location Services', () {
    final instructions = locationServicesDisabledInstructions(
      isWeb: false,
      platform: TargetPlatform.iOS,
    );

    expect(instructions, contains('Location Services'));
    expect(instructions, contains('return to Draper TAK'));
  });

  test('unavailable Android instructions preserve copyable diagnostics', () {
    final instructions = locationUnavailableInstructions(
      isWeb: false,
      platform: TargetPlatform.android,
      error: StateError('timed out'),
    );

    expect(instructions, contains('last-known location'));
    expect(instructions, contains('Wi-Fi-based location'));
    expect(instructions, contains('timed out'));
  });

  test('unavailable web instructions avoid Fire-specific advice', () {
    final instructions = locationUnavailableInstructions(
      isWeb: true,
      platform: TargetPlatform.android,
      error: StateError('browser provider failed'),
    );

    expect(instructions, contains('current or last-known location'));
    expect(instructions, contains('browser provider failed'));
    expect(instructions, isNot(contains('Fire tablets')));
  });
}
