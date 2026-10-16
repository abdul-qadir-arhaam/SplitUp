const GITHUB_APK_URL = 'https://github.com/abdul-qadir-arhaam/SplitUp/releases/download/v1.0.6/splitup-v1.0.6.apk';

export default function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.status(200).json({
    currentVersion: '1.0.6',
    buildNumber: 8,
    minSupportedVersion: '1.0.0',
    downloadUrl: process.env.APK_DOWNLOAD_URL || '/downloads/splitup-v1.0.6.apk',
    releaseNotes: 'SplitUp v1.0.6: Fixed real-time expense sync, dynamic payer identification, instant settlements, and save responsiveness.',
  });
}
