import { Router } from 'express';

export const appVersionRouter = Router();

appVersionRouter.get('/app/version', (req, res) => {
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
