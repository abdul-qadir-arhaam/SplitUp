import { execSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';

const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';

export function renderSvgToPng(svgPath, outPngPath, size = 1024) {
  const absSvg = path.resolve(svgPath);
  const absOut = path.resolve(outPngPath);
  const tempHtml = path.resolve(`docs/brand/temp_${size}.html`);

  const htmlContent = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { margin: 0; padding: 0; }
  html, body {
    width: ${size}px;
    height: ${size}px;
    overflow: hidden;
    background: transparent;
  }
  img {
    width: ${size}px;
    height: ${size}px;
    display: block;
  }
</style>
</head>
<body>
  <img src="file:///${absSvg.replace(/\\/g, '/')}" />
</body>
</html>`;

  fs.writeFileSync(tempHtml, htmlContent);

  const cmd = `"${chromePath}" --headless --disable-gpu --default-background-color=00000000 --screenshot="${absOut}" --window-size=${size},${size} "file:///${tempHtml.replace(/\\/g, '/')}"`;
  execSync(cmd, { stdio: 'pipe' });

  if (fs.existsSync(tempHtml)) {
    fs.unlinkSync(tempHtml);
  }
}

const targets = [
  // symbol_dark at 1024, 512, 192, 96
  { src: 'docs/brand/svg/symbol_dark.svg', out: 'docs/brand/export/symbol_dark_1024.png', size: 1024 },
  { src: 'docs/brand/svg/symbol_dark.svg', out: 'docs/brand/export/symbol_dark_512.png', size: 512 },
  { src: 'docs/brand/svg/symbol_dark.svg', out: 'docs/brand/export/symbol_dark_192.png', size: 192 },
  { src: 'docs/brand/svg/symbol_dark.svg', out: 'docs/brand/export/symbol_dark_96.png', size: 96 },

  // symbol_light at 1024, 512, 192, 96
  { src: 'docs/brand/svg/symbol_light.svg', out: 'docs/brand/export/symbol_light_1024.png', size: 1024 },
  { src: 'docs/brand/svg/symbol_light.svg', out: 'docs/brand/export/symbol_light_512.png', size: 512 },
  { src: 'docs/brand/svg/symbol_light.svg', out: 'docs/brand/export/symbol_light_192.png', size: 192 },
  { src: 'docs/brand/svg/symbol_light.svg', out: 'docs/brand/export/symbol_light_96.png', size: 96 },

  // symbol_mono_white at 1024, 192
  { src: 'docs/brand/svg/symbol_mono_white.svg', out: 'docs/brand/export/symbol_mono_white_1024.png', size: 1024 },
  { src: 'docs/brand/svg/symbol_mono_white.svg', out: 'docs/brand/export/symbol_mono_white_192.png', size: 192 },

  // symbol_mono_dark at 1024, 192
  { src: 'docs/brand/svg/symbol_mono_dark.svg', out: 'docs/brand/export/symbol_mono_dark_1024.png', size: 1024 },
  { src: 'docs/brand/svg/symbol_mono_dark.svg', out: 'docs/brand/export/symbol_mono_dark_192.png', size: 192 },
];

console.log('Exporting PNGs...');
for (const t of targets) {
  renderSvgToPng(t.src, t.out, t.size);
  console.log(` - Rendered ${t.out} (${t.size}x${t.size})`);
}

console.log('All Step 2 PNGs exported successfully.');
