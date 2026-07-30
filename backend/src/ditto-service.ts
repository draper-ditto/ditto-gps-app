import {
  Authenticator,
  Ditto,
  DittoConfig,
  init,
  type QueryResult,
  type SyncSubscription,
} from '@dittolive/ditto';

import type { AppConfig } from './config.js';
import { hasDuplicateUsername, type UserPresence } from './presence.js';

const collection = 'user_presence';

export class DittoService {
  private ditto?: Ditto;
  private subscription?: SyncSubscription;

  async start(config: AppConfig['ditto']): Promise<void> {
    await init();
    const dittoConfig = new DittoConfig(config.databaseId, {
      mode: 'server',
      url: config.serverUrl,
    });
    const ditto = await Ditto.open(dittoConfig);
    ditto.deviceName = 'Draper TAK Node backend';
    this.ditto = ditto;

    await ditto.auth.setExpirationHandler(async (activeDitto, secondsRemaining) => {
      console.info(`Ditto credential refresh; ${secondsRemaining}s remaining`);
      const result = await activeDitto.auth.login(
        config.playgroundToken,
        Authenticator.DEVELOPMENT_PROVIDER,
      );
      if (result.error) throw result.error;
    });

    await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = false');
    this.subscription = ditto.sync.registerSubscription(
      `SELECT * FROM ${collection}`,
    );
    await ditto.sync.start();
  }

  async list(): Promise<UserPresence[]> {
    const result = await this.getDitto().store.execute(
      `SELECT * FROM ${collection} ORDER BY updatedAt DESC`,
    );
    return result.items
      .map((item) => item.value as unknown as UserPresence)
      .filter((person) => person.isDeleted !== true);
  }

  async upsert(presence: UserPresence): Promise<void> {
    await this.getDitto().store.execute(
      `INSERT INTO ${collection} DOCUMENTS (:presence)
       ON ID CONFLICT DO UPDATE_LOCAL_DIFF`,
      { presence: { ...presence } },
    );
  }

  async usernameTaken(username: string, excludingId: string): Promise<boolean> {
    return hasDuplicateUsername(await this.list(), username, excludingId);
  }

  async health(): Promise<{ connected: boolean; records: number }> {
    if (!this.ditto) return { connected: false, records: 0 };
    const result: QueryResult = await this.ditto.store.execute(
      `SELECT * FROM ${collection}`,
    );
    return { connected: true, records: result.items.length };
  }

  async close(): Promise<void> {
    this.subscription?.cancel();
    await this.ditto?.sync.stop();
    await this.ditto?.close();
  }

  private getDitto(): Ditto {
    if (!this.ditto) throw new Error('Ditto has not been initialized.');
    return this.ditto;
  }
}
