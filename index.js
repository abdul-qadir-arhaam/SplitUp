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
    latest_version: '1.0.2',
    currentVersion: '1.0.2',
    build_number: 3,
    buildNumber: 3,
    min_supported_build: 1,
    minSupportedVersion: '1.0.0',
    download_url: 'https://split-up-two.vercel.app/downloads/splitup-v1.0.2.apk',
    downloadUrl: '/downloads/splitup-v1.0.2.apk',
    file_size_mb: 20.74,
    release_notes: 'SplitUp v1.0.2: In-app OTA updates, logo branding, adaptive launcher icon, and ultra-light 20.7 MB APK.',
  });
});

export default async function handler(req, res) {
  await ensureInitialized();
  return app(req, res);
}
