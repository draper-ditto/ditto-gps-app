import 'dotenv/config';

import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';

import { loadConfig } from './config.js';
import { DittoService } from './ditto-service.js';
import { validatePresence } from './presence.js';

const config = loadConfig();
const ditto = new DittoService();
await ditto.start(config.ditto);

const server = createServer(async (request, response) => {
  setCorsHeaders(response);
  if (request.method === 'OPTIONS') {
    response.writeHead(204).end();
    return;
  }

  try {
    const url = new URL(request.url ?? '/', `http://${request.headers.host ?? 'localhost'}`);
    if (request.method === 'GET' && url.pathname === '/health') {
      sendJson(response, 200, await ditto.health());
      return;
    }

    if (request.method === 'GET' && url.pathname === '/api/ditto-config') {
      sendJson(response, 200, config.ditto);
      return;
    }

    if (request.method === 'GET' && url.pathname === '/api/presence') {
      sendJson(response, 200, { data: await ditto.list() });
      return;
    }

    if (request.method === 'POST' && url.pathname === '/api/presence') {
      const validation = validatePresence(await readJson(request));
      if (!validation.value) {
        sendJson(response, 400, { errors: validation.errors });
        return;
      }
      if (await ditto.usernameTaken(validation.value.username, validation.value._id)) {
        sendJson(response, 409, { errors: ['username is already in use.'] });
        return;
      }
      await ditto.upsert(validation.value);
      sendJson(response, 200, { data: validation.value });
      return;
    }

    sendJson(response, 404, { error: 'Not found' });
  } catch (error) {
    console.error(error);
    sendJson(response, 500, { error: 'Internal server error' });
  }
});

server.listen(config.port, () => {
  console.info(`Draper TAK backend listening on http://localhost:${config.port}`);
});

async function shutdown(): Promise<void> {
  server.close();
  await ditto.close();
  process.exit(0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

function setCorsHeaders(response: ServerResponse): void {
  response.setHeader('Access-Control-Allow-Origin', config.allowedOrigin);
  response.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  response.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
}

function sendJson(response: ServerResponse, status: number, value: unknown): void {
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  response.end(JSON.stringify(value));
}

async function readJson(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let length = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    length += buffer.length;
    if (length > 32_768) throw new Error('Request body is too large.');
    chunks.push(buffer);
  }
  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
}
