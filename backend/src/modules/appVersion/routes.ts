import { Router } from 'express';

export const appVersionRouter = Router();

appVersionRouter.get('/app/version', (req, res) => {
  res.json({
    latest_version: '1.0.6',
    currentVersion: '1.0.6',
    build_number: 2008,
    buildNumber: 2008,
    min_supported_build: 1,
    minSupportedVersion: '1.0.0',
    download_url: 'https://split-up-two.vercel.app/downloads/splitup-v1.0.6.apk',
    downloadUrl: '/downloads/splitup-v1.0.6.apk',
    file_size_mb: 20.74,
    release_notes: 'SplitUp v1.0.6: Fixed real-time expense sync, dynamic payer identification, instant settlements, and fast save responsiveness.',
  });
});
