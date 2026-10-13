import path from 'path';
import { fileURLToPath } from 'url';
import express from 'express';
import { app } from './backend/dist/app.js';
import { initUserStore } from './backend/dist/modules/users/store.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const websiteDir = path.join(__dirname, 'website');

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

// 1. Explicitly serve static assets from website directory
app.use(express.static(websiteDir));

// 2. Explicit root route -> website/index.html
app.get('/', (req, res) => {
  res.sendFile(path.join(websiteDir, 'index.html'));
});

// 3. Direct APK download routes
app.get(['/downloads/splitup-v1.0.2.apk', '/downloads/splitup.apk', '/downloads/app-release.apk'], (req, res) => {
  const apkPath = path.join(websiteDir, 'downloads', 'splitup-v1.0.2.apk');
  res.download(apkPath, 'SplitUp-v1.0.2.apk');
});

// 4. Version check endpoints
app.get(['/version', '/app/version'], (req, res) => {
  res.json({
    currentVersion: '1.0.2',
    buildNumber: 3,
    minSupportedVersion: '1.0.0',
    downloadUrl: '/downloads/splitup-v1.0.2.apk',
    releaseNotes: 'SplitUp v1.0.2: Brand logo system, adaptive launcher icon, splash screens, and ultra-light 20.5 MB APK.',
  });
});

export default async function handler(req, res) {
  await ensureInitialized();
  return app(req, res);
}
