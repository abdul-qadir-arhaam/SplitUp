import { Router } from 'express';

export const appVersionRouter = Router();

appVersionRouter.get('/app/version', (req, res) => {
  res.json({
    latest_version_code: 1,
    latest_version_name: '1.0.0',
    min_supported_version_code: 1,
    download_page_url: 'https://splitup.app/download',
  });
});
