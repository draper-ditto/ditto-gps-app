import { describe, expect, it } from 'vitest';

import { validatePresence } from './presence.js';

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
});

