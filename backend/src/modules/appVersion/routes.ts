import { Router } from 'express';

export const appVersionRouter = Router();

appVersionRouter.get('/app/version', (req, res) => {
  res.json({
    latest_version: '1.0.5',
    currentVersion: '1.0.5',
    build_number: 2007,
    buildNumber: 2007,
    min_supported_build: 1,
    minSupportedVersion: '1.0.0',
    download_url: 'https://split-up-two.vercel.app/downloads/splitup-v1.0.5.apk',
    downloadUrl: '/downloads/splitup-v1.0.5.apk',
    file_size_mb: 20.74,
    release_notes: 'SplitUp v1.0.5: Android 14 in-app installer, server-first expense sync, and authoritative balances.',
  });
});
