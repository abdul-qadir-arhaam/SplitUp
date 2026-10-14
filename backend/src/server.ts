import { app } from './app.js';
import { config } from './config/env.js';
import { logger } from './lib/logger.js';
import { initUserStore } from './modules/users/store.js';
import { initFriendsStore } from './modules/friends/store.js';
import { initNotificationsStore } from './modules/notifications/store.js';
import { initLedgersStore } from './modules/ledgers/db_sync.js';

// Load all data from Cloud MySQL into memory cache
await Promise.all([
  initUserStore(),
  initFriendsStore(),
  initNotificationsStore(),
  initLedgersStore(),
]);

app.listen(config.PORT, () => {
  logger.info(`SplitUp Backend running on port ${config.PORT} [${config.NODE_ENV}]`);
});
