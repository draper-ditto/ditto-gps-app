import 'package:ditto_gps/services/database_reset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reset deletes every unique non-empty presence ID', () async {
    final deleted = <String>[];

    final count = await deleteAllPresenceDocuments(
      loadIds: () async => ['device-1', ' device-2 ', null, '', 'device-1'],
      deleteById: (id) async => deleted.add(id),
    );

    expect(count, 2);
    expect(deleted, ['device-1', 'device-2']);
  });

  test('reset with an empty database performs no delete operations', () async {
    var deleteCalls = 0;

    final count = await deleteAllPresenceDocuments(
      loadIds: () async => const [],
      deleteById: (_) async => deleteCalls += 1,
    );

    expect(count, 0);
    expect(deleteCalls, 0);
  });

  test('reset surfaces deletion failures and stops processing', () async {
    final deleted = <String>[];

    await expectLater(
      deleteAllPresenceDocuments(
        loadIds: () async => ['device-1', 'device-2', 'device-3'],
        deleteById: (id) async {
          if (id == 'device-2') throw StateError('delete failed');
          deleted.add(id);
        },
      ),
      throwsStateError,
    );
    expect(deleted, ['device-1']);
  });
}
