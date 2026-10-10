import { app } from './app.js';
import { config } from './config/env.js';
import { logger } from './lib/logger.js';

app.listen(config.PORT, () => {
  logger.info(`SplitUp Backend running on port ${config.PORT} [${config.NODE_ENV}]`);
});
