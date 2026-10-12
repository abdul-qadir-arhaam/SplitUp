import { execSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';

const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';

export function renderSvgToPng(svgPath, outPngPath, size = 1024, transparent = true) {
  const absSvg = path.resolve(svgPath);
  const absOut = path.resolve(outPngPath);
  const tempHtml = path.resolve('docs/brand/temp_render.html');

  const bgStyle = transparent ? 'background: transparent;' : 'background: #0A1411;';

  const htmlContent = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body {
    width: ${size}px;
    height: ${size}px;
    overflow: hidden;
    ${bgStyle}
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

// Test rendering comparison page
const absComparison = path.resolve('docs/brand/comparison.html');
const absOutComp = path.resolve('docs/brand/comparison_preview.png');
const cmdComp = `"${chromePath}" --headless --disable-gpu --screenshot="${absOutComp}" --window-size=1280,1400 "file:///${absComparison.replace(/\\/g, '/')}"`;
execSync(cmdComp, { stdio: 'pipe' });

console.log('Rendered comparison_preview.png successfully.');
