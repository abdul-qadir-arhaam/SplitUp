import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = process.env.PORT || 3000;
const GITHUB_APK_URL = 'https://github.com/abdul-qadir-arhaam/SplitUp/releases/download/v1.0.0.apk/splitup-v1.0.0.apk';

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.apk': 'application/vnd.android.package-archive',
};

const server = http.createServer((req, res) => {
  let reqPath = req.url.split('?')[0];

  if (reqPath === '/app/version' || reqPath === '/version') {
    res.writeHead(200, {
      'Content-Type': 'application/json; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(JSON.stringify({
      currentVersion: '1.0.0',
      buildNumber: 1,
      minSupportedVersion: '1.0.0',
      downloadUrl: process.env.APK_DOWNLOAD_URL || GITHUB_APK_URL,
      releaseNotes: 'SplitUp v1.0.0: Two-party confirmed settlements, node-graph simplification, and offline-first storage.',
    }, null, 2));
    return;
  }

  // If directly requesting download or APK, redirect to GitHub Release if file not on disk
  if (reqPath.startsWith('/downloads/') || reqPath.endsWith('.apk')) {
    const filePath = path.join(__dirname, reqPath);
    if (!fs.existsSync(filePath)) {
      res.writeHead(302, {
        'Location': process.env.APK_DOWNLOAD_URL || GITHUB_APK_URL,
      });
      res.end();
      return;
    }
  }

  if (reqPath === '/' || reqPath === '') {
    reqPath = '/index.html';
  }

  const filePath = path.join(__dirname, reqPath);

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('404 Not Found');
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    const headers = {
      'Content-Type': contentType,
      'Content-Length': stats.size,
    };

    if (ext === '.apk') {
      headers['Content-Disposition'] = `attachment; filename="${path.basename(filePath)}"`;
    }

    res.writeHead(200, headers);
    fs.createReadStream(filePath).pipe(res);
  });
});

server.listen(PORT, () => {
  console.log(`SplitUp website running at http://localhost:${PORT}`);
});
