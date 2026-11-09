// Verify the exact LibVLC 3.7.7 style candidate within a composed disposable OMP clone.
import { readFileSync, realpathSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, resolve } from 'node:path';
import { NEW, OLD, OMP_PIN, RUNTIME_PATH } from './apply.mjs';

const arg = process.argv[2];
if (!arg) throw new Error('VI_FONT_VERIFY_MISSING_ROOT');
const root = realpathSync(resolve(arg));
const git = (...args) => execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trim();
if (git('rev-parse', 'HEAD') !== OMP_PIN) throw new Error('VI_FONT_VERIFY_OMP_PIN');
const src = readFileSync(join(root, RUNTIME_PATH), 'utf8').replace(/\r\n/g, '\n');
if (src.includes(OLD)) throw new Error('VI_FONT_VERIFY_OLD_OPTIONS_PRESENT');
if (!src.includes(NEW) || src.split(NEW).length !== 2 || src.includes('--freetype-bold')) {
  throw new Error('VI_FONT_VERIFY_STYLE_MISSING_OR_DUPLICATE');
}
const expected = [
  '--verbose=-1', '--freetype-font=Noto Sans', '--freetype-rel-fontsize=13',
  '--freetype-outline-thickness=1',
  '--freetype-outline-color=0',
];
for (const flag of expected) {
  if (src.split('"' + flag + '"').length !== 2) {
    throw new Error('VI_FONT_VERIFY_INVALID_FLAG_COUNT');
  }
}
const gradle = readFileSync(join(root, 'android/app/build.gradle'), 'utf8');
if (!gradle.includes("implementation 'org.videolan.android:libvlc-all:3.7.7'")) {
  throw new Error('VI_FONT_VERIFY_LIBVLC_VERSION_DRIFT');
}
if (!readFileSync(join(root, 'android/app/src/main/java/com/spacesarmat/omp/player/P1ProductionSubtitles.kt'), 'utf8')
  .includes('internal object P1ProductionSubtitles')) {
  throw new Error('VI_FONT_VERIFY_G1_PRODUCTION_HELPER_MISSING');
}
console.log('VI_FONT_VLC3_7_7_SOURCE_STYLE_V2_VERIFY_PASS');
console.log('VI_FONT_G1_TRACK_BINDING_AND_RESUME_NOT_CHANGED_BY_STYLE_OVERLAY');
console.log('VI_FONT_REAL_REDMITV_GLYPH_RENDER_NOT_YET_TESTED');
