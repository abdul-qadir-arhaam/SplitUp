import { Router } from 'express';

export const appVersionRouter = Router();

appVersionRouter.get('/app/version', (req, res) => {
  res.json({
    latest_version: '1.0.10',
    currentVersion: '1.0.10',
    build_number: 2012,
    buildNumber: 2012,
    min_supported_build: 1,
    minSupportedVersion: '1.0.0',
    download_url: 'https://split-up-two.vercel.app/downloads/splitup-v1.0.10.apk',
    downloadUrl: '/downloads/splitup-v1.0.10.apk',
    file_size_mb: 20.8,
    release_notes: 'SplitUp v1.0.10: Clean empty amount input on expense creation, live database-backed settlement confirmation, actionable notifications, and trip expense editing.',
  });
});
