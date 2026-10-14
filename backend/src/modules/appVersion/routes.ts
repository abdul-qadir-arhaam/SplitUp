import { Router } from 'express';

export const appVersionRouter = Router();

appVersionRouter.get('/app/version', (req, res) => {
  res.json({
    latest_version: '1.0.3',
    currentVersion: '1.0.3',
    build_number: 4,
    buildNumber: 4,
    min_supported_build: 1,
    minSupportedVersion: '1.0.0',
    download_url: 'https://split-up-two.vercel.app/downloads/splitup-v1.0.2.apk',
    downloadUrl: '/downloads/splitup-v1.0.2.apk',
    file_size_mb: 20.74,
    release_notes: 'SplitUp v1.0.3: Fixed notification bug — removed all dummy notifications, added swipe-to-delete, and enabled smooth request handling.',
  });
});
