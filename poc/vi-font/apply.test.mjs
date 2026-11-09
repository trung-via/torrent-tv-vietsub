import test from 'node:test';
import assert from 'node:assert/strict';
import { OLD, NEW, patchText } from './apply.mjs';

const base = [
  'class VlcLibrary {',
  '  companion object {',
  OLD,
  '  }',
  '}',
].join('\n');

test('controlled VLC3 style injection keeps one verbose option and exact 5 style options', () => {
  const result = patchText(base);
  assert.ok(result.includes(NEW));
  assert.equal((result.match(/--verbose=-1/g) || []).length, 1);
  assert.equal((result.match(/--freetype-/g) || []).length, 5);
  assert.ok(result.includes('--freetype-font=Noto Sans'));
  assert.ok(result.includes('--freetype-rel-fontsize=13'));
  assert.ok(result.includes('--freetype-bold'));
  assert.ok(result.includes('--freetype-outline-thickness=2'));
  assert.ok(result.includes('--freetype-outline-color=0'));
  assert.equal(result.replace(NEW, OLD), base);
});

test('fail-closed when upstream anchor missing or duplicated', () => {
  assert.throws(() => patchText('unexpected source'), /EXPECT_ONE_OPTIONS_ANCHOR/);
  assert.throws(() => patchText(base + '\n' + OLD), /EXPECT_ONE_OPTIONS_ANCHOR/);
});

test('fail-closed on existing font customization or second application', () => {
  assert.throws(() => patchText(base + '\n"freetype-bold"'), /EXISTING_FONT_OVERLAY/);
  assert.throws(() => patchText(patchText(base)), /EXPECT_ONE_OPTIONS_ANCHOR/);
});

test('original Vietnamese glyph specimen stays precomposed and legible as source', () => {
  const tokens = 'ở chảy cậu cả bận hỏng được mất mời dọa phải tất lưu bộ ả ậ ỏ ọ ộ ỡ'.split(' ');
  for (const token of tokens) {
    assert.equal(token.normalize('NFC'), token);
    assert.ok(!/\p{M}/u.test(token), 'not precomposed: ' + token);
  }
});
