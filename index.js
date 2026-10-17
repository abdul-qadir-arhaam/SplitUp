import path from 'path';
import { fileURLToPath } from 'url';
import express from 'express';
import { app } from './backend/dist/app.js';
import { initUserStore } from './backend/dist/modules/users/store.js';
import { initFriendsStore } from './backend/dist/modules/friends/store.js';
import { initNotificationsStore } from './backend/dist/modules/notifications/store.js';
import { initLedgersStore } from './backend/dist/modules/ledgers/db_sync.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const websiteDir = path.join(__dirname, 'website');

let initialized = false;
let initPromise = null;

async function ensureInitialized() {
  if (initialized) return;
  if (!initPromise) {
    initPromise = Promise.all([
      initUserStore(),
      initFriendsStore(),
      initNotificationsStore(),
      initLedgersStore(),
    ])
      .then(() => {
        initialized = true;
      })
      .catch((err) => {
        console.error('[Vercel Serverless] Error initializing stores from MySQL:', err);
        initialized = true;
      });
  }
  await initPromise;
}


// 1. Explicitly serve static assets from website directory
app.use(express.static(websiteDir));

// 2. Explicit root route -> website/index.html
app.get('/', (req, res) => {
  res.sendFile(path.join(websiteDir, 'index.html'));
});

// 3. Direct APK download routes
app.get(['/downloads/splitup-v1.0.8.apk', '/downloads/splitup-v1.0.7.apk', '/downloads/splitup-v1.0.5.apk', '/downloads/splitup-v1.0.4.apk', '/downloads/splitup-v1.0.2.apk', '/downloads/splitup.apk', '/downloads/app-release.apk'], (req, res) => {
  const apkPath = path.join(websiteDir, 'downloads', 'splitup-v1.0.8.apk');
  res.download(apkPath, 'SplitUp-v1.0.8.apk');
});

// 4. Version check endpoints
app.get(['/version', '/app/version'], (req, res) => {
  res.json({
    latest_version: '1.0.8',
    currentVersion: '1.0.8',
    build_number: 2010,
    buildNumber: 2010,
    min_supported_build: 1,
    minSupportedVersion: '1.0.0',
    download_url: 'https://split-up-two.vercel.app/downloads/splitup-v1.0.8.apk',
    downloadUrl: '/downloads/splitup-v1.0.8.apk',
    file_size_mb: 20.74,
    release_notes: 'SplitUp v1.0.8: Instant group persistence across cold starts, fixed back-navigation group deletion, and enhanced net balance sync.',
  });
});

export default async function handler(req, res) {
  await ensureInitialized();
  return app(req, res);
}
