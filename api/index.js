import { app } from '../backend/dist/app.js';
import { initUserStore } from '../backend/dist/modules/users/store.js';

let initialized = false;
let initPromise = null;

async function ensureInitialized() {
  if (initialized) return;
  if (!initPromise) {
    initPromise = initUserStore()
      .then(() => {
        initialized = true;
      })
      .catch((err) => {
        console.error('[Vercel Serverless] Error initializing user store from MySQL:', err);
        initialized = true;
      });
  }
  await initPromise;
}

export default async function handler(req, res) {
  await ensureInitialized();
  return app(req, res);
}
