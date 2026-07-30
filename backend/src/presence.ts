export interface UserPresence {
  _id: string;
  username: string;
  latitude: number;
  longitude: number;
  status: string;
  updatedAt: number;
  isDeleted?: boolean;
}

export interface ValidationResult {
  value?: UserPresence;
  errors: string[];
}

export function normalizeUsername(username: string): string {
  return username.trim().toLocaleLowerCase('en-US');
}

export function hasDuplicateUsername(
  people: UserPresence[],
  username: string,
  excludingId: string,
): boolean {
  const normalized = normalizeUsername(username);
  return people.some(
    (person) =>
      person.isDeleted !== true &&
      person._id !== excludingId &&
      normalizeUsername(person.username) === normalized,
  );
}

export function validatePresence(input: unknown): ValidationResult {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    return { errors: ['Request body must be a JSON object.'] };
  }

  const body = input as Record<string, unknown>;
  const errors: string[] = [];
  const id = readString(body._id, '_id', 80, errors);
  const username = readString(body.username, 'username', 48, errors);
  const status = readString(body.status, 'status', 120, errors);
  const latitude = readCoordinate(body.latitude, 'latitude', -90, 90, errors);
  const longitude = readCoordinate(body.longitude, 'longitude', -180, 180, errors);

  if (errors.length > 0 || id === undefined || username === undefined ||
      status === undefined || latitude === undefined || longitude === undefined) {
    return { errors };
  }

  return {
    errors,
    value: {
      _id: id,
      username,
      latitude,
      longitude,
      status,
      updatedAt: Date.now(),
      isDeleted: false,
    },
  };
}

function readString(
  value: unknown,
  field: string,
  maxLength: number,
  errors: string[],
): string | undefined {
  if (typeof value !== 'string' || value.trim().length === 0) {
    errors.push(`${field} is required.`);
    return undefined;
  }
  const clean = value.trim();
  if (clean.length > maxLength) {
    errors.push(`${field} must be ${maxLength} characters or fewer.`);
    return undefined;
  }
  return clean;
}

function readCoordinate(
  value: unknown,
  field: string,
  min: number,
  max: number,
  errors: string[],
): number | undefined {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    errors.push(`${field} must be a finite number.`);
    return undefined;
  }
  if (value < min || value > max) {
    errors.push(`${field} must be between ${min} and ${max}.`);
    return undefined;
  }
  return value;
}
