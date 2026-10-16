import { Router } from 'express';

export const appVersionRouter = Router();

appVersionRouter.get('/app/version', (req, res) => {
  res.json({
    latest_version: '1.0.7',
    currentVersion: '1.0.7',
    build_number: 2009,
    buildNumber: 2009,
    min_supported_build: 1,
    minSupportedVersion: '1.0.0',
    download_url: 'https://split-up-two.vercel.app/downloads/splitup-v1.0.7.apk',
    downloadUrl: '/downloads/splitup-v1.0.7.apk',
    file_size_mb: 20.74,
    release_notes: 'SplitUp v1.0.7: Fixed settlement confirmation sync, instant net balance updates, and notifications persistence.',
  });
});
