import { execSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';

const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';

export function renderHtmlToPng(htmlContent, outPngPath, width, height) {
  const absOut = path.resolve(outPngPath);
  const outDir = path.dirname(absOut);
  if (!fs.existsSync(outDir)) {
    fs.mkdirSync(outDir, { recursive: true });
  }

  const tempHtml = path.resolve(`docs/brand/temp_${Date.now()}_${Math.random().toString(36).slice(2)}.html`);
  fs.writeFileSync(tempHtml, htmlContent);

  const cmd = `"${chromePath}" --headless --disable-gpu --default-background-color=00000000 --screenshot="${absOut}" --window-size=${width},${height} "file:///${tempHtml.replace(/\\/g, '/')}"`;
  execSync(cmd, { stdio: 'pipe' });

  if (fs.existsSync(tempHtml)) {
    fs.unlinkSync(tempHtml);
  }
}

// Read master SVGs
const svgDark = fs.readFileSync('docs/brand/svg/symbol_dark.svg', 'utf8');
const svgLight = fs.readFileSync('docs/brand/svg/symbol_light.svg', 'utf8');
const svgMonoWhite = fs.readFileSync('docs/brand/svg/symbol_mono_white.svg', 'utf8');
const svgMonoDark = fs.readFileSync('docs/brand/svg/symbol_mono_dark.svg', 'utf8');

// SVG as Base64 for clean inline embedding
const b64Dark = Buffer.from(svgDark).toString('base64');
const b64Light = Buffer.from(svgLight).toString('base64');
const b64MonoWhite = Buffer.from(svgMonoWhite).toString('base64');
const b64MonoDark = Buffer.from(svgMonoDark).toString('base64');

console.log('--- Step 2: Export PNGs ---');
const step2 = [
  { b64: b64Dark, out: 'docs/brand/export/symbol_dark_1024.png', size: 1024 },
  { b64: b64Dark, out: 'docs/brand/export/symbol_dark_512.png', size: 512 },
  { b64: b64Dark, out: 'docs/brand/export/symbol_dark_192.png', size: 192 },
  { b64: b64Dark, out: 'docs/brand/export/symbol_dark_96.png', size: 96 },

  { b64: b64Light, out: 'docs/brand/export/symbol_light_1024.png', size: 1024 },
  { b64: b64Light, out: 'docs/brand/export/symbol_light_512.png', size: 512 },
  { b64: b64Light, out: 'docs/brand/export/symbol_light_192.png', size: 192 },
  { b64: b64Light, out: 'docs/brand/export/symbol_light_96.png', size: 96 },

  { b64: b64MonoWhite, out: 'docs/brand/export/symbol_mono_white_1024.png', size: 1024 },
  { b64: b64MonoWhite, out: 'docs/brand/export/symbol_mono_white_192.png', size: 192 },

  { b64: b64MonoDark, out: 'docs/brand/export/symbol_mono_dark_1024.png', size: 1024 },
  { b64: b64MonoDark, out: 'docs/brand/export/symbol_mono_dark_192.png', size: 192 },
];

for (const s of step2) {
  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>* { margin:0; padding:0; } html,body { width:${s.size}px; height:${s.size}px; overflow:hidden; background:transparent; }</style></head><body><img src="data:image/svg+xml;base64,${s.b64}" width="${s.size}" height="${s.size}" /></body></html>`;
  renderHtmlToPng(html, s.out, s.size, s.size);
}
console.log('Step 2 completed.');

console.log('--- Step 3: Android Launcher Icons ---');
// Adaptive Foreground: 1024x1024 canvas with symbol centered within 600px diameter (inner 58%, safe within 66% zone)
function makeForegroundHtml(b64, badge = null) {
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html, body { width:1024px; height:1024px; overflow:hidden; background:transparent; }
  .center {
    position: absolute;
    left: 212px;
    top: 212px;
    width: 600px;
    height: 600px;
  }
  .badge {
    position: absolute;
    top: 220px;
    right: 220px;
    background: #C9A961;
    color: #0A1411;
    font-family: -apple-system, sans-serif;
    font-weight: 800;
    font-size: 42px;
    padding: 8px 24px;
    border-radius: 999px;
    letter-spacing: 2px;
    box-shadow: 0 4px 16px rgba(0,0,0,0.5);
  }
</style>
</head>
<body>
  <div class="center"><img src="data:image/svg+xml;base64,${b64}" width="600" height="600" /></div>
  ${badge ? `<div class="badge">${badge}</div>` : ''}
</body>
</html>`;
}

// Prod adaptive foreground & monochrome
renderHtmlToPng(makeForegroundHtml(b64Dark), 'app/android/app/src/main/res/drawable/ic_launcher_foreground.png', 1024, 1024);
renderHtmlToPng(makeForegroundHtml(b64MonoWhite), 'app/android/app/src/main/res/drawable/ic_launcher_monochrome.png', 1024, 1024);

// Dev adaptive foreground
renderHtmlToPng(makeForegroundHtml(b64Dark, 'DEV'), 'app/android/app/src/debug/res/drawable/ic_launcher_foreground.png', 1024, 1024);
renderHtmlToPng(makeForegroundHtml(b64MonoWhite, 'DEV'), 'app/android/app/src/debug/res/drawable/ic_launcher_monochrome.png', 1024, 1024);

// Legacy full-bleed square icons for older Android devices
function makeLegacyIconHtml(b64, size, badge = null) {
  const symbolSize = Math.round(size * 0.72);
  const offset = Math.round((size - symbolSize) / 2);
  const badgeFont = Math.round(size * 0.14);
  const badgePadX = Math.round(size * 0.08);
  const badgePadY = Math.round(size * 0.02);

  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html, body { width:${size}px; height:${size}px; overflow:hidden; background:#0A1411; }
  .center {
    position: absolute;
    left: ${offset}px;
    top: ${offset}px;
    width: ${symbolSize}px;
    height: ${symbolSize}px;
  }
  .badge {
    position: absolute;
    top: ${Math.round(size * 0.08)}px;
    right: ${Math.round(size * 0.08)}px;
    background: #C9A961;
    color: #0A1411;
    font-family: -apple-system, sans-serif;
    font-weight: 800;
    font-size: ${badgeFont}px;
    padding: ${badgePadY}px ${badgePadX}px;
    border-radius: 999px;
  }
</style>
</head>
<body>
  <div class="center"><img src="data:image/svg+xml;base64,${b64}" width="${symbolSize}" height="${symbolSize}" /></div>
  ${badge ? `<div class="badge">${badge}</div>` : ''}
</body>
</html>`;
}

const mipmaps = [
  { folder: 'mipmap-mdpi', size: 48 },
  { folder: 'mipmap-hdpi', size: 72 },
  { folder: 'mipmap-xhdpi', size: 96 },
  { folder: 'mipmap-xxhdpi', size: 144 },
  { folder: 'mipmap-xxxhdpi', size: 192 },
];

for (const m of mipmaps) {
  // Prod
  renderHtmlToPng(makeLegacyIconHtml(b64Dark, m.size), `app/android/app/src/main/res/${m.folder}/ic_launcher.png`, m.size, m.size);
  renderHtmlToPng(makeLegacyIconHtml(b64Dark, m.size), `app/android/app/src/main/res/${m.folder}/ic_launcher_round.png`, m.size, m.size);

  // Dev (debug)
  renderHtmlToPng(makeLegacyIconHtml(b64Dark, m.size, 'DEV'), `app/android/app/src/debug/res/${m.folder}/ic_launcher.png`, m.size, m.size);
  renderHtmlToPng(makeLegacyIconHtml(b64Dark, m.size, 'DEV'), `app/android/app/src/debug/res/${m.folder}/ic_launcher_round.png`, m.size, m.size);
}
console.log('Step 3 completed.');

console.log('--- Step 4: Splash Screen Assets ---');
// Android 12+ splash icon: 288x288 transparent with 192px centered symbol
function makeSplashIconHtml(b64, size = 288, iconSize = 192) {
  const offset = (size - iconSize) / 2;
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { margin:0; padding:0; }
  html, body { width:${size}px; height:${size}px; overflow:hidden; background:transparent; }
  .icon { position:absolute; left:${offset}px; top:${offset}px; width:${iconSize}px; height:${iconSize}px; }
</style>
</head>
<body>
  <div class="icon"><img src="data:image/svg+xml;base64,${b64}" width="${iconSize}" height="${iconSize}" /></div>
</body>
</html>`;
}

renderHtmlToPng(makeSplashIconHtml(b64Dark, 432, 288), 'app/android/app/src/main/res/drawable/splash_icon_dark.png', 432, 432);
renderHtmlToPng(makeSplashIconHtml(b64Light, 432, 288), 'app/android/app/src/main/res/drawable/splash_icon_light.png', 432, 432);
console.log('Step 4 completed.');

console.log('--- Step 6: Website Assets ---');
// Favicon SVG with prefers-color-scheme
const faviconSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <style>
    .left-half { fill: #1FA67A; }
    .right-half { fill: #C9A961; }
    @media (prefers-color-scheme: light) {
      .left-half { fill: #0F7F5C; }
      .right-half { fill: #9A7B2F; }
    }
  </style>
  <path class="left-half" d="M 339.39 49.03 A 205 205 0 0 0 172.63 423.58 Z" />
  <path class="right-half" d="M 339.37 88.42 A 205 205 0 0 1 172.61 462.97 Z" />
</svg>
`;

fs.writeFileSync('docs/brand/export/web/favicon.svg', faviconSvg);
fs.writeFileSync('website/favicon.svg', faviconSvg);

// apple-touch-icon: 180x180 symbol on #0A1411
const appleTouchHtml = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>* { margin:0; padding:0; } html,body { width:180px; height:180px; background:#0A1411; overflow:hidden; } .c { position:absolute; left:26px; top:26px; width:128px; height:128px; }</style></head><body><div class="c"><img src="data:image/svg+xml;base64,${b64Dark}" width="128" height="128" /></div></body></html>`;
renderHtmlToPng(appleTouchHtml, 'docs/brand/export/web/apple-touch-icon.png', 180, 180);
renderHtmlToPng(appleTouchHtml, 'website/apple-touch-icon.png', 180, 180);

// icon-192 & icon-512 (on #0A1411)
function makeWebIconHtml(size) {
  const iconSize = Math.round(size * 0.72);
  const offset = Math.round((size - iconSize) / 2);
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><style>* { margin:0; padding:0; } html,body { width:${size}px; height:${size}px; background:#0A1411; overflow:hidden; } .c { position:absolute; left:${offset}px; top:${offset}px; width:${iconSize}px; height:${iconSize}px; }</style></head><body><div class="c"><img src="data:image/svg+xml;base64,${b64Dark}" width="${iconSize}" height="${iconSize}" /></div></body></html>`;
}
renderHtmlToPng(makeWebIconHtml(192), 'docs/brand/export/web/icon-192.png', 192, 192);
renderHtmlToPng(makeWebIconHtml(192), 'website/icon-192.png', 192, 192);

renderHtmlToPng(makeWebIconHtml(512), 'docs/brand/export/web/icon-512.png', 512, 512);
renderHtmlToPng(makeWebIconHtml(512), 'website/icon-512.png', 512, 512);

// Favicon sizes: 48, 32, 16 px PNGs
renderHtmlToPng(`<!DOCTYPE html><html><head><meta charset="utf-8"><style>* { margin:0; padding:0; } html,body { width:48px; height:48px; background:transparent; overflow:hidden; }</style></head><body><img src="data:image/svg+xml;base64,${b64Dark}" width="48" height="48" /></body></html>`, 'docs/brand/export/web/favicon-48.png', 48, 48);
renderHtmlToPng(`<!DOCTYPE html><html><head><meta charset="utf-8"><style>* { margin:0; padding:0; } html,body { width:32px; height:32px; background:transparent; overflow:hidden; }</style></head><body><img src="data:image/svg+xml;base64,${b64Dark}" width="32" height="32" /></body></html>`, 'docs/brand/export/web/favicon-32.png', 32, 32);
renderHtmlToPng(`<!DOCTYPE html><html><head><meta charset="utf-8"><style>* { margin:0; padding:0; } html,body { width:16px; height:16px; background:transparent; overflow:hidden; }</style></head><body><img src="data:image/svg+xml;base64,${b64Dark}" width="16" height="16" /></body></html>`, 'docs/brand/export/web/favicon-16.png', 16, 16);

// Copy 32px to website/favicon.png
fs.copyFileSync('docs/brand/export/web/favicon-32.png', 'website/favicon.png');

// Open Graph Social Share Image: 1200 x 630 on #0A1411
const ogHtml = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html, body {
    width: 1200px;
    height: 630px;
    background: #0A1411;
    color: #F3F1EA;
    font-family: 'Manrope', -apple-system, sans-serif;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
  }
  .bg-blob-1 {
    position: absolute;
    width: 600px;
    height: 600px;
    left: -100px;
    top: -100px;
    background: radial-gradient(circle, rgba(31,166,122,0.3) 0%, transparent 70%);
  }
  .bg-blob-2 {
    position: absolute;
    width: 500px;
    height: 500px;
    right: -100px;
    bottom: -100px;
    background: radial-gradient(circle, rgba(201,169,97,0.2) 0%, transparent 70%);
  }
  .container {
    position: relative;
    z-index: 2;
    display: flex;
    align-items: center;
    gap: 48px;
  }
  .symbol {
    width: 220px;
    height: 220px;
  }
  .content {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .title {
    font-size: 88px;
    font-weight: 800;
    letter-spacing: -2px;
    color: #F3F1EA;
  }
  .tagline {
    font-size: 30px;
    color: #A9B4AF;
    font-weight: 500;
  }
</style>
</head>
<body>
  <div class="bg-blob-1"></div>
  <div class="bg-blob-2"></div>
  <div class="container">
    <div class="symbol"><img src="data:image/svg+xml;base64,${b64Dark}" width="220" height="220" /></div>
    <div class="content">
      <div class="title">SplitUp</div>
      <div class="tagline">Split up the bill, not the friendship.</div>
    </div>
  </div>
</body>
</html>`;

renderHtmlToPng(ogHtml, 'docs/brand/export/web/og_image.png', 1200, 630);
renderHtmlToPng(ogHtml, 'website/og_image.png', 1200, 630);

console.log('All branding assets generated successfully.');
