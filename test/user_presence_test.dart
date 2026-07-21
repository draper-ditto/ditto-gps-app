import 'package:ditto_gps/models/user_presence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presence documents round-trip through Ditto-shaped JSON', () {
    final updatedAt = DateTime.utc(2026, 7, 20, 18, 0);
    final presence = UserPresence(
      id: 'device-1',
      username: 'Ada',
      latitude: 37.7749,
      longitude: -122.4194,
      status: 'Exploring',
      updatedAt: updatedAt,
    );

    final decoded = UserPresence.fromJson(presence.toJson());

    expect(decoded.id, 'device-1');
    expect(decoded.username, 'Ada');
    expect(decoded.latitude, 37.7749);
    expect(decoded.longitude, -122.4194);
    expect(decoded.status, 'Exploring');
    expect(
      decoded.updatedAt.millisecondsSinceEpoch,
      updatedAt.millisecondsSinceEpoch,
    );
  });
}
