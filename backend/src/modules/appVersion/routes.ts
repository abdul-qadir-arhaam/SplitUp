import { Router } from 'express';

export const appVersionRouter = Router();

appVersionRouter.get('/app/version', (req, res) => {
  res.json({
    latest_version: '1.0.9',
    currentVersion: '1.0.9',
    build_number: 2011,
    buildNumber: 2011,
    min_supported_build: 1,
    minSupportedVersion: '1.0.0',
    download_url: 'https://split-up-two.vercel.app/downloads/splitup-v1.0.9.apk',
    downloadUrl: '/downloads/splitup-v1.0.9.apk',
    file_size_mb: 20.8,
    release_notes: 'SplitUp v1.0.9: Live database-backed settlement confirmation, actionable notifications, trip expense editing, double-tap protection, and zero-balance synchronization.',
  });
});
