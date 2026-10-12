import { app } from './app.js';
import { config } from './config/env.js';
import { logger } from './lib/logger.js';
import { initUserStore } from './modules/users/store.js';

// Load all users from Cloud MySQL into memory cache
await initUserStore();

app.listen(config.PORT, () => {
  logger.info(`SplitUp Backend running on port ${config.PORT} [${config.NODE_ENV}]`);
});
