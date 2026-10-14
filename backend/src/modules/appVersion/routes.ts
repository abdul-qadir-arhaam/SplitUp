import { Router } from 'express';

export const appVersionRouter = Router();

appVersionRouter.get('/app/version', (req, res) => {
  res.json({
    latest_version: '1.0.4',
    currentVersion: '1.0.4',
    build_number: 5,
    buildNumber: 5,
    min_supported_build: 1,
    minSupportedVersion: '1.0.0',
    download_url: 'https://split-up-two.vercel.app/downloads/splitup-v1.0.4.apk',
    downloadUrl: '/downloads/splitup-v1.0.4.apk',
    file_size_mb: 20.80,
    release_notes: 'SplitUp v1.0.4: 100% Cloud-synced! All friends, groups, trips, expenses, settlements, and notifications are now permanently synced to the cloud and restored across uninstalls.',
  });
});
