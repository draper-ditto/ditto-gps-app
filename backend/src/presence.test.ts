import { describe, expect, it } from 'vitest';

import { hasDuplicateUsername, validatePresence } from './presence.js';

describe('validatePresence', () => {
  it('normalizes a valid presence update', () => {
    const result = validatePresence({
      _id: 'device-1',
      username: '  Ada  ',
      latitude: 37.7749,
      longitude: -122.4194,
      status: ' Exploring ',
    });

    expect(result.errors).toEqual([]);
    expect(result.value).toMatchObject({
      _id: 'device-1',
      username: 'Ada',
      latitude: 37.7749,
      longitude: -122.4194,
      status: 'Exploring',
      isDeleted: false,
    });
    expect(result.value?.updatedAt).toEqual(expect.any(Number));
  });

  it('rejects coordinates outside their valid ranges', () => {
    const result = validatePresence({
      _id: 'device-1',
      username: 'Ada',
      latitude: 91,
      longitude: -181,
      status: 'Exploring',
    });

    expect(result.value).toBeUndefined();
    expect(result.errors).toContain('latitude must be between -90 and 90.');
    expect(result.errors).toContain('longitude must be between -180 and 180.');
  });

  it('requires a username and both coordinates', () => {
    const result = validatePresence({
      _id: 'device-1',
      username: '   ',
      status: 'Exploring',
    });

    expect(result.value).toBeUndefined();
    expect(result.errors).toContain('username is required.');
    expect(result.errors).toContain('latitude must be a finite number.');
    expect(result.errors).toContain('longitude must be a finite number.');
  });

  it('detects duplicate usernames case-insensitively but excludes the same device', () => {
    const people = [
      {
        _id: 'device-1',
        username: 'Ada',
        latitude: 37.7749,
        longitude: -122.4194,
        status: 'Exploring',
        updatedAt: Date.now(),
      },
    ];

    expect(hasDuplicateUsername(people, '  ADA ', 'device-2')).toBe(true);
    expect(hasDuplicateUsername(people, 'Ada', 'device-1')).toBe(false);
  });

  it('allows a username to be reused after a synchronized soft deletion', () => {
    const people = [
      {
        _id: 'device-1',
        username: 'Ada',
        latitude: 37.7749,
        longitude: -122.4194,
        status: 'Exploring',
        updatedAt: Date.now(),
        isDeleted: true,
      },
    ];

    expect(hasDuplicateUsername(people, 'Ada', 'device-2')).toBe(false);
  });
});
