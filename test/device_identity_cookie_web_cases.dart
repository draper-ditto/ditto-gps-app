import 'package:ditto_gps/services/device_identity_cookie.dart';
import 'package:flutter_test/flutter_test.dart';

void runDeviceIdentityCookieTests() {
  test('web identity cookie persists and can be cleared', () {
    const deviceId = '44444444-4444-4444-8444-444444444444';
    clearDeviceIdentityCookie();
    addTearDown(clearDeviceIdentityCookie);

    expect(readDeviceIdentityCookie(), isNull);
    writeDeviceIdentityCookie(deviceId);
    expect(readDeviceIdentityCookie(), deviceId);

    clearDeviceIdentityCookie();
    expect(readDeviceIdentityCookie(), isNull);
  });
}
