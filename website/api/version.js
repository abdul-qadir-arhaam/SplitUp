export default function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.status(200).json({
    currentVersion: '1.0.0',
    buildNumber: 1,
    minSupportedVersion: '1.0.0',
    downloadUrl: process.env.APK_DOWNLOAD_URL || '/downloads/splitup-v1.0.0.apk',
    releaseNotes: 'SplitUp v1.0.0: Two-party confirmed settlements, node-graph simplification, and offline-first storage.',
  });
}
