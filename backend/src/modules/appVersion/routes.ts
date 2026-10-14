import { Router } from 'express';

export const appVersionRouter = Router();

appVersionRouter.get('/app/version', (req, res) => {
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
