export interface AppConfig {
  port: number;
  allowedOrigin: string;
  ditto: {
    databaseId: string;
    serverUrl: string;
    playgroundToken: string;
  };
}

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

export function loadConfig(): AppConfig {
  const portValue = process.env.PORT ?? '8080';
  const port = Number.parseInt(portValue, 10);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`PORT must be a valid TCP port, received: ${portValue}`);
  }

  return {
    port,
    allowedOrigin: process.env.ALLOWED_ORIGIN?.trim() || '*',
    ditto: {
      databaseId: required('DITTO_DATABASE_ID'),
      serverUrl: required('DITTO_SERVER_URL'),
      playgroundToken: required('DITTO_PLAYGROUND_TOKEN'),
    },
  };
}

