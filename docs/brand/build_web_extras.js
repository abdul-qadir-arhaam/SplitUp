import fs from 'node:fs';
import path from 'node:path';

// 1. Pack favicon.ico (multi-size: 16, 32, 48 px PNGs)
function createIco(pngItems) {
  const count = pngItems.length;
  const headerSize = 6;
  const dirEntrySize = 16;
  let offset = headerSize + count * dirEntrySize;

  const header = Buffer.alloc(headerSize);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // 1 = ICO
  header.writeUInt16LE(count, 4);

  const dirEntries = [];
  for (const item of pngItems) {
    const entry = Buffer.alloc(dirEntrySize);
    entry.writeUInt8(item.width >= 256 ? 0 : item.width, 0);
    entry.writeUInt8(item.height >= 256 ? 0 : item.height, 1);
    entry.writeUInt8(0, 2); // color count
    entry.writeUInt8(0, 3); // reserved
    entry.writeUInt16LE(1, 4); // planes
    entry.writeUInt16LE(32, 6); // bpp
    entry.writeUInt32LE(item.buffer.length, 8); // size
    entry.writeUInt32LE(offset, 12); // offset
    dirEntries.push(entry);
    offset += item.buffer.length;
  }

  return Buffer.concat([header, ...dirEntries, ...pngItems.map(p => p.buffer)]);
}

const p16 = fs.readFileSync('docs/brand/export/web/favicon-16.png');
const p32 = fs.readFileSync('docs/brand/export/web/favicon-32.png');
const p48 = fs.readFileSync('docs/brand/export/web/favicon-48.png');

const icoBuffer = createIco([
  { width: 16, height: 16, buffer: p16 },
  { width: 32, height: 32, buffer: p32 },
  { width: 48, height: 48, buffer: p48 },
]);

fs.writeFileSync('docs/brand/export/web/favicon.ico', icoBuffer);
fs.writeFileSync('website/favicon.ico', icoBuffer);
console.log('favicon.ico successfully generated (16x16, 32x32, 48x48 multi-size).');

// 2. Horizontal Logos (Dark and Light)
const horizontalDarkSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 460 120" width="100%" height="100%">
  <!-- SplitUp Symbol Dark -->
  <g transform="translate(10, 10) scale(0.1953125)">
    <path fill="#1FA67A" d="M 339.39 49.03 A 205 205 0 0 0 172.63 423.58 Z" />
    <path fill="#C9A961" d="M 339.37 88.42 A 205 205 0 0 1 172.61 462.97 Z" />
  </g>
  <text x="130" y="76" font-family="'Manrope', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-weight="800" font-size="64" letter-spacing="-1.5">
    <tspan fill="#F3F1EA">Split</tspan><tspan fill="#1FA67A">Up</tspan>
  </text>
</svg>
`;

const horizontalLightSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 460 120" width="100%" height="100%">
  <!-- SplitUp Symbol Light -->
  <g transform="translate(10, 10) scale(0.1953125)">
    <path fill="#0F7F5C" d="M 339.39 49.03 A 205 205 0 0 0 172.63 423.58 Z" />
    <path fill="#9A7B2F" d="M 339.37 88.42 A 205 205 0 0 1 172.61 462.97 Z" />
  </g>
  <text x="130" y="76" font-family="'Manrope', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-weight="800" font-size="64" letter-spacing="-1.5">
    <tspan fill="#14201C">Split</tspan><tspan fill="#0F7F5C">Up</tspan>
  </text>
</svg>
`;

fs.writeFileSync('docs/brand/svg/logo_horizontal_dark.svg', horizontalDarkSvg);
fs.writeFileSync('docs/brand/svg/logo_horizontal_light.svg', horizontalLightSvg);
fs.writeFileSync('website/logo_horizontal_dark.svg', horizontalDarkSvg);
fs.writeFileSync('website/logo_horizontal_light.svg', horizontalLightSvg);

console.log('Horizontal SVGs generated successfully.');
