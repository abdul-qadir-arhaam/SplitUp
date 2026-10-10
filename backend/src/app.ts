import express from 'express';
import cors from 'cors';
import { requestId } from './middleware/requestId.js';
import { authMiddleware } from './middleware/auth.js';
import { idempotencyMiddleware } from './middleware/idempotency.js';
import { errorHandler } from './middleware/errorHandler.js';
import { appVersionRouter } from './modules/appVersion/routes.js';
import { ledgersRouter } from './modules/ledgers/routes.js';

export const app = express();

app.use(cors());
app.use(express.json());
app.use(requestId);

// Public health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
  });
});

// Version check endpoint
app.use(appVersionRouter);

// Authenticated and Idempotent v1 routes
app.use('/v1', authMiddleware, idempotencyMiddleware, ledgersRouter);

// Standardized error handler
app.use(errorHandler);
