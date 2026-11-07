// Guarded application of P2 search UI overlay onto a disposable, pinned OMP
// checkout. Compatible with a checkout already patched by verified G1 script.
// No subprocess to download media, no Android/ADB or Windows host actions.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, copyFileSync, mkdirSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const PIN = '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f';
const ADD_BLOB = 'be8ab4529e0fdb9fe6dde3cc68c7fe58284aa323';
const root = resolve(process.argv[2] || '');
const from = dirname(fileURLToPath(import.meta.url));
// Keep the two leading porcelain status columns. .trim() corrupts
// ' M src/api/torrserver.ts' into 'M src/api/torrserver.ts', then slice(3)
// loses the first two path characters. This was caught composing G1 + P2.
const git = (...args) => execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trimEnd();
function fail(message) { throw new Error('STOP_P2_UI_OVERLAY: ' + message); }
function once(text, oldValue, newValue, label) {
  const first = text.indexOf(oldValue);
  if (first < 0 || text.indexOf(oldValue, first + oldValue.length) !== -1) fail('MISSING_OR_DUPLICATE_ANCHOR_' + label);
  return text.slice(0, first) + newValue + text.slice(first + oldValue.length);
}
if (!process.argv[2]) fail('UPSTREAM_ROOT_REQUIRED');
if (git('rev-parse', 'HEAD') !== PIN) fail('OMP_PIN_CHANGED');
const add = 'src/screens/Add.tsx';
if (git('hash-object', '--', add) !== ADD_BLOB) fail('ADD_TSX_SOURCE_BLOB_CHANGED');
const gitRoot = resolve(git('rev-parse', '--show-toplevel'));
if (gitRoot.toLowerCase() !== root.toLowerCase()) fail('WRONG_GIT_ROOT');
const allowedG1 = [
  'src/api/torrserver.ts', 'src/player/nativePlayer.ts',
  'android/app/src/main/java/com/spacesarmat/omp/player/NativePlayer.kt',
  'android/app/src/main/java/com/spacesarmat/omp/player/PlayerActivity.kt',
  'android/app/src/main/java/com/spacesarmat/omp/player/EngineSwitcher.kt',
  'android/app/src/main/java/com/spacesarmat/omp/player/PlayerSession.kt',
  'android/app/src/main/java/com/spacesarmat/omp/player/P1ProductionSubtitles.kt',
  'android/app/src/test/java/com/spacesarmat/omp/player/P1ProductionSubtitlesTest.kt',
];
const dirty = git('status', '--porcelain', '--untracked-files=all').split(/\r?\n/).filter(Boolean);
for (const line of dirty) {
  const name = line.slice(3).trim().replace(/\\/g, '/');
  if (allowedG1.indexOf(name) < 0) fail('UNEXPECTED_DIRTY_FILE:' + name);
}
const helper = join(root, 'src/sources/tvCandidateCheck.ts');
const tests = join(root, 'tests/sources/tvCandidateCheck.test.ts');
if (existsSync(helper) || existsSync(tests)) fail('DESTINATION_EXISTS');
let text = readFileSync(join(root, add), 'utf8');
text = once(text,
  "import { sortTvResults, stableTvOrder, type TvSortKey } from '../sources/tvSort';",
  "import { sortTvResults, stableTvOrder, type TvSortKey } from '../sources/tvSort';\nimport { inspectP2Reported, rankP2Reported } from '../sources/tvCandidateCheck';",
  'IMPORT');
text = once(text,
  "  const [sortKey, setSortKey] = useState<TvSortKey>('quality');",
  "  const [sortKey, setSortKey] = useState<TvSortKey>('quality');\n  // P2 is opt-in; ranking never authorizes download or verifies a media track.\n  const [p2ReportedView, setP2ReportedView] = useState(false);",
  'STATE');
text = once(text,
  "  const sorted = pool ? (streaming ? stableTvOrder(order.current, pool, sortKey) : sortTvResults(pool, sortKey)) : [];",
  "  const baseSorted = pool ? (streaming ? stableTvOrder(order.current, pool, sortKey) : sortTvResults(pool, sortKey)) : [];\n  // Preserve cursor order during a streaming search; rank only after all sources settle.\n  const sorted = p2ReportedView && !streaming ? rankP2Reported(baseSorted) : baseSorted;",
  'SORT');
text = once(text,
  "      {note === 'phoneDown' && <div class=\"search-note search-note-warn\">{t('search.phoneDown')}</div>}",
  "      {p2ReportedView && <div class=\"search-note\" data-hint=\"p2-reported\">P2: chỉ ưu tiên kích thước + seed được nguồn báo cáo; chưa xác minh 2K, audio Việt hay quyền nội dung.</div>}\n      {note === 'phoneDown' && <div class=\"search-note search-note-warn\">{t('search.phoneDown')}</div>}",
  'DISCLAIMER');
text = once(text,
  "          {prog && <Button focusKey=\"search-sort\" className=\"search-sort\" label={t('search.sortLabel', { v: sortName() })} onPress={pickSort} />}",
  "          {prog && <Button focusKey=\"search-sort\" className=\"search-sort\" label={t('search.sortLabel', { v: sortName() })} onPress={pickSort} />}\n          {prog && <Button focusKey=\"search-p2\" className=\"search-sort\" label={p2ReportedView ? 'P2: 8–12 GB, ≥300 seed báo cáo (bật)' : 'P2: ưu tiên metadata (tắt)'} onPress={() => { order.current = []; setP2ReportedView((v) => !v); }} />}",
  'BUTTON');
text = once(text,
  "            const kind = resultKindLabel(r);",
  "            const kind = resultKindLabel(r);\n            const p2Status = p2ReportedView ? inspectP2Reported(r) : null;",
  'ROW_STATE');
text = once(text,
  "                    {kind && <span class=\"search-chip search-kind\">{tvGlyphs(kind)}</span>}",
  "                    {kind && <span class=\"search-chip search-kind\">{tvGlyphs(kind)}</span>}\n                    {p2Status && <span class=\"search-chip\">{p2Status === 'reported-match' ? 'P2: khớp (báo cáo)' : p2Status === 'reported-mismatch' ? 'P2: ngoài giới hạn (báo cáo)' : 'P2: chưa đủ dữ liệu'}</span>}",
  'ROW_BADGE');
writeFileSync(join(root, add), text, 'utf8');
copyFileSync(join(from, 'tvCandidateCheck.ts'), helper);
mkdirSync(dirname(tests), { recursive: true });
copyFileSync(join(from, 'tvCandidateCheck.test.ts'), tests);
console.log('P2_OMP_REPORTED_SEARCH_UI_APPLIED pinned=' + PIN + ' no_tv_effect=true');
