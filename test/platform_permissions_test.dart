import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final debugManifest = File(
    'android/app/src/debug/AndroidManifest.xml',
  ).readAsStringSync();

  test('Android manifest has one root and one application element', () {
    expect(RegExp(r'<manifest(?:\s|>)').allMatches(manifest), hasLength(1));
    expect(RegExp(r'<application(?:\s|>)').allMatches(manifest), hasLength(1));
    expect(manifest, contains('android:label="Draper TAK"'));
  });

  test('Android manifest declares GPS and network permissions', () {
    for (final permission in [
      'android.permission.INTERNET',
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.ACCESS_COARSE_LOCATION',
      'android.permission.ACCESS_FINE_LOCATION',
    ]) {
      expect(manifest, contains('android:name="$permission"'));
    }
  });

  test('Android manifest declares Ditto Bluetooth and Wi-Fi permissions', () {
    for (final permission in [
      'android.permission.ACCESS_WIFI_STATE',
      'android.permission.CHANGE_WIFI_STATE',
      'android.permission.CHANGE_WIFI_MULTICAST_STATE',
      'android.permission.BLUETOOTH_ADVERTISE',
      'android.permission.BLUETOOTH_CONNECT',
      'android.permission.BLUETOOTH_SCAN',
      'android.permission.NEARBY_WIFI_DEVICES',
    ]) {
      expect(manifest, contains('android:name="$permission"'));
    }
    expect(
      RegExp(
        r'android:name="android\.permission\.BLUETOOTH_SCAN"[\s\S]*?android:usesPermissionFlags="neverForLocation"',
      ).hasMatch(manifest),
      isTrue,
    );
  });

  test('GPS permissions are not capped to an obsolete Android SDK', () {
    for (final permission in [
      'ACCESS_COARSE_LOCATION',
      'ACCESS_FINE_LOCATION',
    ]) {
      final declaration = RegExp(
        '<uses-permission\\s+android:name="android\\.permission\\.$permission"[^>]*?/>',
      ).firstMatch(manifest)?.group(0);
      expect(declaration, isNotNull);
      expect(declaration, isNot(contains('android:maxSdkVersion=')));
      expect(declaration, contains('tools:remove="android:maxSdkVersion"'));
    }
  });

  test('cleartext traffic is restricted to Android debug builds', () {
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(debugManifest, contains('android:usesCleartextTraffic="true"'));
    expect(
      debugManifest,
      contains('tools:replace="android:usesCleartextTraffic"'),
    );
  });
}
