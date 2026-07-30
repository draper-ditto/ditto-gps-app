import 'package:ditto_gps/services/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const cookieId = '11111111-1111-4111-8111-111111111111';
  const storedId = '22222222-2222-4222-8222-222222222222';
  const generatedId = '33333333-3333-4333-8333-333333333333';

  test('cookie identity wins across browser origins', () {
    expect(
      resolveDeviceIdentity(
        cookieId: cookieId,
        storedId: storedId,
        generatedId: generatedId,
      ),
      cookieId,
    );
  });

  test('existing stored identity is migrated when no cookie exists', () {
    expect(
      resolveDeviceIdentity(
        cookieId: null,
        storedId: storedId,
        generatedId: generatedId,
      ),
      storedId,
    );
  });

  test('new identity is generated when no persisted identity exists', () {
    expect(
      resolveDeviceIdentity(
        cookieId: null,
        storedId: null,
        generatedId: generatedId,
      ),
      generatedId,
    );
  });

  test('invalid persisted identities are ignored', () {
    expect(
      resolveDeviceIdentity(
        cookieId: 'bad',
        storedId: 'contains spaces and cookie syntax;=',
        generatedId: generatedId,
      ),
      generatedId,
    );
  });

  test('native persistence retains the same generated identity', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    final first = await loadOrCreateDeviceIdentity(preferences);
    final second = await loadOrCreateDeviceIdentity(preferences);

    expect(first, second);
    expect(preferences.getString(deviceIdentityPreferenceKey), first);
  });

  test('active current cookie identity remains authoritative', () {
    expect(
      recoverSyncedDeviceIdentity(
        currentId: cookieId,
        originStoredId: storedId,
        activeDeviceIds: const [cookieId, storedId],
      ),
      cookieId,
    );
  });

  test('active origin identity repairs a cookie with no active record', () {
    expect(
      recoverSyncedDeviceIdentity(
        currentId: cookieId,
        originStoredId: storedId,
        activeDeviceIds: const [storedId],
      ),
      storedId,
    );
  });

  test('identity is not guessed when neither candidate owns a record', () {
    expect(
      recoverSyncedDeviceIdentity(
        currentId: cookieId,
        originStoredId: storedId,
        activeDeviceIds: const [generatedId],
      ),
      cookieId,
    );
  });
}
