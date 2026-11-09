// P1 UX-SUB-FONT: opt-in, source-only LibVLC 3.7 Vietnamese caption candidate.
// Pinned OMP, G1 Production then P2 overlay; no font binary or Android-system changes.
// Apply only in a disposable p1-g1-prod-* checkout. No APK/TV action here.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, realpathSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const OMP_PIN = '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f';
export const RUNTIME_BLOB = '15bf0cb1d53ddf6c8936f362499a7575f2586f08';
export const RUNTIME_PATH = 'android/app/src/main/java/com/spacesarmat/omp/player/VlcRuntime.kt';
export const OLD = '        private val OPTIONS = arrayListOf("--verbose=-1")';
export const NEW = [
  '        private val OPTIONS = arrayListOf(',
  '            "--verbose=-1",',
  '            // Vietnamese caption candidate. VLC 3: smaller denominator means larger glyphs.',
  '            // V3 diagnostic A/B: keep v2 font, size, thin outline; toggle bold ON only.',
  '            "--freetype-font=Noto Sans",',
  '            "--freetype-rel-fontsize=13",',
  '            "--freetype-bold",',
  '            "--freetype-outline-thickness=1",',
  '            "--freetype-outline-color=0"',
  '        )',
].join('\n');

export function patchText(text) {
  const hits = text.split(OLD).length - 1;
  if (hits !== 1) throw new Error('VI_FONT_STOP_EXPECT_ONE_OPTIONS_ANCHOR');
  if (/freetype-(?:font|rel-fontsize|bold|outline-thickness)/.test(text)) {
    throw new Error('VI_FONT_STOP_EXISTING_FONT_OVERLAY');
  }
  return text.replace(OLD, NEW);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const arg = process.argv[2];
  if (!arg) throw new Error('VI_FONT_STOP_UPSTREAM_ROOT_REQUIRED');
  const root = realpathSync(resolve(arg));
  if (!basename(root).startsWith('p1-g1-prod-')) {
    throw new Error('VI_FONT_STOP_NOT_DISPOSABLE_OMP_ROOT');
  }
  const git = (...args) => execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trim();
  if (git('rev-parse', 'HEAD') !== OMP_PIN) throw new Error('VI_FONT_STOP_OMP_PIN_DRIFT');
  if (resolve(git('rev-parse', '--show-toplevel')).toLowerCase() !== root.toLowerCase()) {
    throw new Error('VI_FONT_STOP_WRONG_GIT_ROOT');
  }
  if (git('hash-object', '--', RUNTIME_PATH) !== RUNTIME_BLOB) {
    throw new Error('VI_FONT_STOP_VLC_RUNTIME_SOURCE_DRIFT');
  }
  const file = join(root, RUNTIME_PATH);
  const before = readFileSync(file, 'utf8');
  const patched = patchText(before);
  // Keep the exact upstream checkout EOL convention on Windows Git/autocrlf.
  const after = before.includes('\r\n') ? patched.replace(/(?<!\r)\n/g, '\r\n') : patched;
  writeFileSync(file, after, 'utf8');
  console.log('VI_FONT_VLC3_GUARDED_STYLE_V3_APPLIED size_denominator=13 font=Noto_Sans bold=true outline=1');
}
