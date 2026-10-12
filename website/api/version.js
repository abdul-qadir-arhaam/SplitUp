const GITHUB_APK_URL = 'https://github.com/abdul-qadir-arhaam/SplitUp/releases/download/v1.0.2/splitup-v1.0.2.apk';

export default function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.status(200).json({
    currentVersion: '1.0.2',
    buildNumber: 3,
    minSupportedVersion: '1.0.0',
    downloadUrl: process.env.APK_DOWNLOAD_URL || GITHUB_APK_URL,
    releaseNotes: 'SplitUp v1.0.2: Brand logo system, adaptive launcher icon, splash screens, and connected database authentication.',
  });
}
