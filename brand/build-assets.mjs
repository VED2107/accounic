/**
 * Brand asset build (brand/build-assets.mjs).
 *
 * Rasterises the SVG masters into every size the three clients need, so the
 * SVGs stay the single source of truth and no PNG is ever hand-edited.
 *
 *   node brand/build-assets.mjs
 *
 * Outputs:
 *   brand/png/…                          reference renders
 *   web/src/app/icon.svg | apple-icon.png favicon + iOS home-screen icon
 *   app/assets/brand/…                   in-app logo for Flutter
 *   app/android/app/src/main/res/…       Android launcher icons
 *   app/windows/runner/resources/app_icon.ico
 */

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..');

const svg = (name) => readFile(join(here, `${name}.svg`));

async function png(source, size, outPath, { background } = {}) {
  await mkdir(dirname(outPath), { recursive: true });
  let pipeline = sharp(source, { density: 400 }).resize(size, size, {
    fit: 'contain',
    background: background ?? { r: 0, g: 0, b: 0, alpha: 0 },
  });
  if (background) pipeline = pipeline.flatten({ background });
  await pipeline.png({ compressionLevel: 9 }).toFile(outPath);
  return outPath;
}

/**
 * Minimal ICO writer.
 *
 * Windows Vista and later accept a PNG payload inside an ICO container, so the
 * whole format reduces to a 6-byte header, one 16-byte directory entry, and the
 * PNG bytes. Pulling in an image library for this would be heavier than the
 * spec itself.
 */
async function ico(pngBuffer, size, outPath) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(1, 4); // one image

  const entry = Buffer.alloc(16);
  entry.writeUInt8(size >= 256 ? 0 : size, 0); // 0 means 256
  entry.writeUInt8(size >= 256 ? 0 : size, 1);
  entry.writeUInt8(0, 2); // palette
  entry.writeUInt8(0, 3); // reserved
  entry.writeUInt16LE(1, 4); // colour planes
  entry.writeUInt16LE(32, 6); // bits per pixel
  entry.writeUInt32LE(pngBuffer.length, 8);
  entry.writeUInt32LE(header.length + entry.length, 12);

  await mkdir(dirname(outPath), { recursive: true });
  await writeFile(outPath, Buffer.concat([header, entry, pngBuffer]));
  return outPath;
}

const icon = await svg('accounic-icon');
const appIcon = await svg('accounic-app-icon');
const favicon = await svg('accounic-favicon');
const horizontal = await svg('accounic-horizontal');
const white = await svg('accounic-white');

const written = [];
const out = (p) => written.push(p.replace(repoRoot, '').replace(/\\/g, '/'));

// --- reference renders -------------------------------------------------------
for (const size of [256, 512, 1024]) {
  out(await png(icon, size, join(here, 'png', `accounic-icon-${size}.png`)));
}
out(await png(appIcon, 1024, join(here, 'png', 'accounic-app-icon-1024.png')));

for (const [name, source, width] of [
  ['accounic-horizontal', horizontal, 1180],
  ['accounic-white', white, 1180],
]) {
  const path = join(here, 'png', `${name}.png`);
  await mkdir(dirname(path), { recursive: true });
  await sharp(source, { density: 400 })
    .resize({ width, fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png({ compressionLevel: 9 })
    .toFile(path);
  out(path);
}

// --- web ---------------------------------------------------------------------
// Next.js picks up src/app/icon.svg and apple-icon.png by convention.
await writeFile(join(repoRoot, 'web', 'src', 'app', 'icon.svg'), favicon);
out(join(repoRoot, 'web', 'src', 'app', 'icon.svg'));
out(await png(appIcon, 180, join(repoRoot, 'web', 'src', 'app', 'apple-icon.png')));

// --- Flutter in-app logo -----------------------------------------------------
for (const [name, source] of [
  ['accounic-icon', icon],
  ['accounic-horizontal', horizontal],
  ['accounic-white', white],
]) {
  const path = join(repoRoot, 'app', 'assets', 'brand', `${name}.svg`);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, source);
  out(path);
}
out(await png(icon, 512, join(repoRoot, 'app', 'assets', 'brand', 'accounic-icon-512.png')));

// --- Android launcher icons --------------------------------------------------
const mipmaps = {
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};
const androidRes = join(repoRoot, 'app', 'android', 'app', 'src', 'main', 'res');
for (const [folder, size] of Object.entries(mipmaps)) {
  out(await png(appIcon, size, join(androidRes, folder, 'ic_launcher.png')));
}

// --- Windows icon ------------------------------------------------------------
const windowsPng = await sharp(appIcon, { density: 400 })
  .resize(256, 256)
  .png({ compressionLevel: 9 })
  .toBuffer();
out(
  await ico(
    windowsPng,
    256,
    join(repoRoot, 'app', 'windows', 'runner', 'resources', 'app_icon.ico'),
  ),
);

console.log(`Wrote ${written.length} files:`);
for (const path of written) console.log(`  ${path}`);
