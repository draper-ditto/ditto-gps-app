import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'device_identity_cookie.dart';

const deviceIdentityPreferenceKey = 'presence_device_id';

class DeviceIdentitySeed {
  const DeviceIdentitySeed({
    required this.deviceId,
    required this.originStoredId,
  });

  final String deviceId;
  final String? originStoredId;
}

Future<String> loadOrCreateDeviceIdentity(
  SharedPreferences preferences,
) async {
  return (await loadDeviceIdentitySeed(preferences)).deviceId;
}

Future<DeviceIdentitySeed> loadDeviceIdentitySeed(
  SharedPreferences preferences,
) async {
  final cookieId = readDeviceIdentityCookie();
  final storedId = preferences.getString(deviceIdentityPreferenceKey);
  final deviceId = resolveDeviceIdentity(
    cookieId: cookieId,
    storedId: storedId,
    generatedId: const Uuid().v4(),
  );

  final validStoredId = _validDeviceId(storedId);
  if (validStoredId == null || validStoredId == deviceId) {
    await persistDeviceIdentity(preferences, deviceId);
  } else if (readDeviceIdentityCookie() != deviceId) {
    writeDeviceIdentityCookie(deviceId);
  }

  return DeviceIdentitySeed(
    deviceId: deviceId,
    originStoredId: validStoredId,
  );
}

Future<void> persistDeviceIdentity(
  SharedPreferences preferences,
  String deviceId,
) async {
  final validId = _validDeviceId(deviceId);
  if (validId == null) throw ArgumentError.value(deviceId, 'deviceId');
  if (preferences.getString(deviceIdentityPreferenceKey) != validId) {
    await preferences.setString(deviceIdentityPreferenceKey, validId);
  }
  if (readDeviceIdentityCookie() != validId) {
    writeDeviceIdentityCookie(validId);
  }
}

@visibleForTesting
String resolveDeviceIdentity({
  required String? cookieId,
  required String? storedId,
  required String generatedId,
}) {
  return _validDeviceId(cookieId) ??
      _validDeviceId(storedId) ??
      _validDeviceId(generatedId) ??
      (throw ArgumentError.value(
        generatedId,
        'generatedId',
        'Invalid device ID',
      ));
}

String recoverSyncedDeviceIdentity({
  required String currentId,
  required String? originStoredId,
  required Iterable<String> activeDeviceIds,
}) {
  final activeIds = activeDeviceIds.toSet();
  if (activeIds.contains(currentId)) return currentId;

  final storedId = _validDeviceId(originStoredId);
  if (storedId != null && activeIds.contains(storedId)) return storedId;
  return currentId;
}

String? _validDeviceId(String? candidate) {
  final value = candidate?.trim();
  if (value == null || value.length < 8 || value.length > 128) return null;
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) return null;
  return value;
}
