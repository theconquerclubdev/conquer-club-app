/**
 * One-time cleanup script:
 * Finds every file in a Supabase Storage bucket bigger than 80 KB,
 * shrinks it (webp, quality-reduction loop, same logic as the app),
 * backs up the ORIGINAL locally first, then re-uploads the smaller version.
 *
 * SAFE BY DEFAULT: runs in DRY-RUN mode unless you pass --apply
 *
 * Usage:
 *   npm install
 *   node index.js                # dry run - only reports, changes nothing
 *   node index.js --apply        # actually backs up + shrinks + re-uploads
 */

const { createClient } = require('@supabase/supabase-js');
const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

// ---------- CONFIG ----------
const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BUCKET = process.env.SUPABASE_BUCKET || 'progress-photos';

const MAX_BYTES = 80 * 1024; // 80 KB cap - must match app's cap
const MIN_QUALITY = 20;      // quality floor, same as app
const START_QUALITY = 65;    // starting quality, same as app
const RESIZE_MAX_WIDTH = 1080;
const RESIZE_MAX_HEIGHT = 1350;

const BACKUP_DIR = path.join(__dirname, 'backup-originals');
const DELAY_MS = 200; // small pause between files, gentle on free tier

const APPLY = process.argv.includes('--apply');
// ---------------------------

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY env vars.');
  console.error('Copy .env.example to .env and fill it in, then run with: node -r dotenv/config index.js');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Recursively list every actual file (not folder) in the bucket
async function listAllFiles(prefix = '') {
  const files = [];
  let offset = 0;
  const limit = 1000;

  while (true) {
    const { data, error } = await supabase.storage
      .from(BUCKET)
      .list(prefix, { limit, offset, sortBy: { column: 'name', order: 'asc' } });

    if (error) {
      throw new Error(`List failed for prefix "${prefix}": ${error.message}`);
    }
    if (!data || data.length === 0) break;

    for (const entry of data) {
      const fullPath = prefix ? `${prefix}/${entry.name}` : entry.name;
      const isFolder = entry.id === null; // Supabase convention: folders have no id/metadata
      if (isFolder) {
        const nested = await listAllFiles(fullPath);
        files.push(...nested);
      } else {
        files.push({
          path: fullPath,
          size: entry.metadata?.size ?? 0,
        });
      }
    }

    if (data.length < limit) break;
    offset += limit;
  }

  return files;
}

// Compress buffer to webp under MAX_BYTES, same quality-reduction loop as the app
async function compressUnderCap(inputBuffer) {
  let quality = START_QUALITY;
  let result = null;

  do {
    result = await sharp(inputBuffer)
      .resize({
        width: RESIZE_MAX_WIDTH,
        height: RESIZE_MAX_HEIGHT,
        fit: 'inside',
        withoutEnlargement: true,
      })
      .webp({ quality })
      .toBuffer();

    quality -= 10;
  } while (result.length > MAX_BYTES && quality >= MIN_QUALITY);

  return result;
}

async function main() {
  console.log(`Mode: ${APPLY ? 'APPLY (will modify storage)' : 'DRY RUN (read-only, changes nothing)'}`);
  console.log(`Bucket: ${BUCKET} | Cap: ${MAX_BYTES} bytes\n`);

  console.log('Scanning bucket...');
  const allFiles = await listAllFiles('');
  const oversized = allFiles.filter((f) => f.size > MAX_BYTES);

  console.log(`Total files found: ${allFiles.length}`);
  console.log(`Files over 80 KB: ${oversized.length}\n`);

  if (oversized.length === 0) {
    console.log('Nothing to do. All files already under 80 KB.');
    return;
  }

  if (!APPLY) {
    console.log('--- DRY RUN REPORT (nothing changed) ---');
    for (const f of oversized) {
      console.log(`  ${f.path}  ->  ${(f.size / 1024).toFixed(1)} KB`);
    }
    console.log('\nRe-run with "--apply" to actually shrink and re-upload these files.');
    console.log('Originals will be backed up first, to:', BACKUP_DIR);
    return;
  }

  fs.mkdirSync(BACKUP_DIR, { recursive: true });

  const results = { shrunk: 0, skippedNoImprovement: 0, failed: 0 };

  for (const f of oversized) {
    try {
      console.log(`\nProcessing: ${f.path} (${(f.size / 1024).toFixed(1)} KB)`);

      // 1. Download original
      const { data: downloadData, error: downloadErr } = await supabase.storage
        .from(BUCKET)
        .download(f.path);
      if (downloadErr) throw new Error(`Download failed: ${downloadErr.message}`);

      const originalBuffer = Buffer.from(await downloadData.arrayBuffer());

      // 2. Backup original to local disk BEFORE touching cloud copy
      const backupPath = path.join(BACKUP_DIR, f.path.replace(/\//g, '__'));
      fs.writeFileSync(backupPath, originalBuffer);

      // 3. Compress
      const compressed = await compressUnderCap(originalBuffer);

      // 4. Only overwrite if actually smaller than the original
      if (compressed.length >= originalBuffer.length) {
        console.log('  Skipped: compression did not reduce size, leaving original untouched.');
        results.skippedNoImprovement++;
        continue;
      }

      // 5. Re-upload, replacing the old file
      const { error: uploadErr } = await supabase.storage
        .from(BUCKET)
        .upload(f.path, compressed, {
          upsert: true,
          contentType: 'image/webp',
        });
      if (uploadErr) throw new Error(`Upload failed: ${uploadErr.message}`);

      const flag = compressed.length > MAX_BYTES ? '  (still above 80 KB, floor reached)' : '';
      console.log(`  Done: ${(originalBuffer.length / 1024).toFixed(1)} KB -> ${(compressed.length / 1024).toFixed(1)} KB${flag}`);
      results.shrunk++;
    } catch (err) {
      console.error(`  FAILED: ${err.message}`);
      results.failed++;
    }

    await sleep(DELAY_MS);
  }

  console.log('\n--- SUMMARY ---');
  console.log(`Shrunk & re-uploaded: ${results.shrunk}`);
  console.log(`Skipped (no improvement): ${results.skippedNoImprovement}`);
  console.log(`Failed: ${results.failed}`);
  console.log(`Originals backed up in: ${BACKUP_DIR}`);
}

main().catch((err) => {
  console.error('Script error:', err);
  process.exit(1);
});
