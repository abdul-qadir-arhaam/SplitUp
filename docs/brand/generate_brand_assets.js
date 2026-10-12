import fs from 'node:fs';
import path from 'node:path';

export function makeSvg(emerald, brass) {
  const R = 205;
  const thetaDeg = 24;
  const gap = 16;
  const offset = 18;

  const theta = (thetaDeg * Math.PI) / 180;
  const sinT = Math.sin(theta);
  const cosT = Math.cos(theta);

  // Left half (emerald) - shifted up-right along cut (+offset), and left perpendicular to cut (-gap/2)
  const cxL = 256 + offset * sinT - (gap / 2) * cosT;
  const cyL = 256 - offset * cosT - (gap / 2) * sinT;
  const p1Lx = cxL + R * sinT;
  const p1Ly = cyL - R * cosT;
  const p2Lx = cxL - R * sinT;
  const p2Ly = cyL + R * cosT;

  // Right half (brass) - shifted down-left along cut (-offset), and right perpendicular to cut (+gap/2)
  const cxR = 256 - offset * sinT + (gap / 2) * cosT;
  const cyR = 256 + offset * cosT + (gap / 2) * sinT;
  const p1Rx = cxR + R * sinT;
  const p1Ry = cyR - R * cosT;
  const p2Rx = cxR - R * sinT;
  const p2Ry = cyR + R * cosT;

  const dLeft = `M ${p1Lx.toFixed(2)} ${p1Ly.toFixed(2)} A ${R} ${R} 0 0 0 ${p2Lx.toFixed(2)} ${p2Ly.toFixed(2)} Z`;
  const dRight = `M ${p1Rx.toFixed(2)} ${p1Ry.toFixed(2)} A ${R} ${R} 0 0 1 ${p2Rx.toFixed(2)} ${p2Ry.toFixed(2)} Z`;

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <path d="${dLeft}" fill="${emerald}" />
  <path d="${dRight}" fill="${brass}" />
</svg>
`;
}

// Generate the 4 master SVGs
fs.writeFileSync('docs/brand/svg/symbol_dark.svg', makeSvg('#1FA67A', '#C9A961'));
fs.writeFileSync('docs/brand/svg/symbol_light.svg', makeSvg('#0F7F5C', '#9A7B2F'));
fs.writeFileSync('docs/brand/svg/symbol_mono_white.svg', makeSvg('#FFFFFF', '#FFFFFF'));
fs.writeFileSync('docs/brand/svg/symbol_mono_dark.svg', makeSvg('#14201C', '#14201C'));

console.log('Master SVGs generated successfully in docs/brand/svg/');
