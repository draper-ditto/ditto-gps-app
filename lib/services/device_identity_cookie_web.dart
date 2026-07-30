import 'package:web/web.dart' as web;

const _cookieName = 'draper_tak_device_id';
const _cookieLifetimeSeconds = 60 * 60 * 24 * 365 * 10;

String? readDeviceIdentityCookie() {
  try {
    for (final cookie in web.document.cookie.split(';')) {
      final part = cookie.trim();
      final separator = part.indexOf('=');
      if (separator < 0 || part.substring(0, separator) != _cookieName) {
        continue;
      }
      return Uri.decodeComponent(part.substring(separator + 1));
    }
  } catch (_) {
    // Cookies may be disabled by browser policy. SharedPreferences remains the
    // origin-scoped fallback in that case.
  }
  return null;
}

void writeDeviceIdentityCookie(String deviceId) {
  try {
    web.document.cookie = '$_cookieName=${Uri.encodeComponent(deviceId)}; '
        'Path=/; Max-Age=$_cookieLifetimeSeconds; SameSite=Lax';
  } catch (_) {
    // Identity persistence still works for the current origin through
    // SharedPreferences when cookies are unavailable.
  }
}

void clearDeviceIdentityCookie() {
  try {
    web.document.cookie = '$_cookieName=; Path=/; Max-Age=0; SameSite=Lax';
  } catch (_) {}
}
