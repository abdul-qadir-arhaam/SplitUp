const GITHUB_APK_URL = 'https://github.com/abdul-qadir-arhaam/SplitUp/releases/download/v1.0.8/splitup-v1.0.8.apk';

export default function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.status(200).json({
    currentVersion: '1.0.8',
    buildNumber: 2010,
    minSupportedVersion: '1.0.0',
    downloadUrl: process.env.APK_DOWNLOAD_URL || '/downloads/splitup-v1.0.8.apk',
    releaseNotes: 'SplitUp v1.0.8: Instant group persistence across cold starts, fixed back-navigation group deletion, and enhanced net balance sync.',
  });
}
