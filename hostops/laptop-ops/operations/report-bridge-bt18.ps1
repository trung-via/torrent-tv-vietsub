# RB02 one-shot BT18 export. Never reruns AGY or touches playback.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$source='ad010d992cd69cec1dc28185d538392efe8e04fe'
$nonce='25e73e80cfce49728e4f6c1402e6cefb'
$folder='Torrent TV Vietsub - Brain Inbox'
$marker='RB02-binding-20261126-187'
$receipt=[ordered]@{schema='TTV-REPORT-BRIDGE-OWNER-V1';nonce=$rq.nonce;source_commit=$rq.source_commit;original_source=$source;original_nonce=$nonce;state='HOLD';reason='INBOX_NOT_VISIBLE';sha256='';file_count=0;bytes=0}
$dest=Join-Path $spool ('Receipts\report-bridge-'+$rq.nonce+'.json')
function Save-Receipt {
    $tmp=$dest+'.tmp'
    [IO.File]::WriteAllText($tmp,($receipt|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($tmp,$dest)
}
$paths=@()
foreach($drive in Get-PSDrive -PSProvider FileSystem){
    foreach($prefix in @('My Drive','Drive cua toi','Drive của tôi')){
        $paths+=Join-Path (Join-Path $drive.Root $prefix) $folder
    }
}
foreach($prefix in @('My Drive','Google Drive','Google Drive\My Drive','Google Drive\Drive của tôi','Drive của tôi')){
    $paths+=Join-Path (Join-Path $env:USERPROFILE $prefix) $folder
}
$matched=@($paths|Sort-Object -Unique|Where-Object { (Test-Path -LiteralPath $_ -PathType Container) -and (Test-Path -LiteralPath (Join-Path $_ $marker) -PathType Container) })
if($matched.Count -ne 1){
    if($matched.Count -gt 1){$receipt.reason='INBOX_AMBIGUOUS'}
    Save-Receipt
    return
}
$inbox=$matched[0]
$py=@'
"""Owner-local report bundle export and independent Brain verification (RB01-RB03).

No provider, TV, browser, GitHub upload or background service calls.
The Drive Desktop folder must be explicitly enrolled under the Owner account.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
import zipfile

SCHEMA = "TTV-REPORT-BRIDGE-V1"
OPERATION = "agy-native-browser-readout-1124"
REQUIRED = ("BRAIN_RESULT.json", "BRAIN_HANDOFF.json", "BRAIN_TEACHER_REPORT.json",
            "BRAIN_TEACHER_FULL_RESPONSE.md", "stream-timing.json", "BRAIN_FILTER_QA.json")
OPTIONAL = ("TEACHER_RECIPE_PRIVATE.json", "event-arrivals.jsonl", "verified-fixture.json")
CAP = 64 * 1024 * 1024
TOTAL = 128 * 1024 * 1024

def require(condition, message):
    if not condition:
        raise ValueError(message)

def digest(data):
    return hashlib.sha256(data).hexdigest()

def json_bytes(obj):
    return (json.dumps(obj, sort_keys=True, ensure_ascii=False, indent=2) + "\n").encode()

def valid_id(source, nonce):
    require(re.fullmatch("[0-9a-f]{40}", source) and re.fullmatch("[0-9a-f]{32}", nonce),
            "INVALID_IDENTITY")

def plain(path):
    s = path.lstat()
    require(not path.is_symlink() and not getattr(s, "st_file_attributes", 0) & 0x400,
            "LINK_OR_REPARSE_POINT")
    return s

def read(path, cap=CAP):
    s = plain(path)
    require(stat.S_ISREG(s.st_mode) and 0 < s.st_size <= cap, "FILE_SIZE_OR_TYPE")
    data = path.read_bytes()
    require(len(data) == s.st_size and len(data) <= cap, "FILE_CHANGED")
    return data

def read_json(path):
    return json.loads(read(path).decode("utf-8-sig"))

def identify(spool, source, nonce):
    valid_id(source, nonce)
    paths = [spool / "History" / ("receipt-" + nonce + ".json"),
             spool / "Receipts" / "receipt.json"]
    matches = []
    for p in paths:
        if p.exists():
            plain(p.parent)
            x = read_json(p)
            if x.get("nonce") == nonce and x.get("source_commit") == source:
                matches.append(x)
    require(matches and all(x == matches[0] for x in matches), "RECEIPT_MISSING_OR_CONFLICT")
    x = matches[0]
    require(x.get("schema") == "TTV-LAPTOP-HOSTOPS-RECEIPT-V1"
            and x.get("operation") == OPERATION
            and x.get("result") in ("SUCCESS", "FAILED_NO_RETRY"), "RECEIPT_NOT_TERMINAL")
    return x["result"]

def safe_name(name):
    require(isinstance(name, str) and name and name == Path(name).name
            and not any(c in name for c in '/\\:\x00') and name not in (".", ".."),
            "UNSAFE_ARTIFACT_NAME")
    return name

def make_bundle(root, spool, source, nonce):
    result = identify(spool, source, nonce)
    plain(root)
    run = root / ("bt18-hydrogen-opensubtitles-" + nonce)
    require(stat.S_ISDIR(plain(run).st_mode), "RUN_NOT_FOUND")
    handoff = read_json(run / "BRAIN_HANDOFF.json")
    report = read_json(run / "BRAIN_TEACHER_REPORT.json")
    brain = read_json(run / "BRAIN_RESULT.json")
    require(handoff.get("nonce") == nonce and handoff.get("source") == source
            and handoff.get("original_source") == source and handoff.get("mode") == "LIVE"
            and report.get("source_commit") == source and brain.get("handoff") == handoff,
            "REPORT_IDENTITY_MISMATCH")
    files = {n: read(run / n) for n in REQUIRED}
    for n in OPTIONAL:
        if (run / n).exists():
            files[n] = read(run / n)
    for a in report.get("artifacts", []):
        if a.get("copied_to_job") is not True:
            continue
        n = safe_name(a["filename"])
        require(Path(n).suffix.lower() in (".srt", ".zip"), "ARTIFACT_TYPE")
        directory = run / "browser-downloads"
        plain(directory)
        data = read(directory / n, 10_000_000)
        require(digest(data) == a.get("sha256") and len(data) == a.get("bytes"), "ARTIFACT_HASH")
        key = "browser-downloads/" + n
        require(key.casefold() not in {k.casefold() for k in files}, "DUPLICATE_ARTIFACT")
        files[key] = data
    require(sum(map(len, files.values())) <= TOTAL, "BUNDLE_SIZE")
    manifest = {"schema": SCHEMA, "source": source, "nonce": nonce,
                "receipt_result": result, "files": [
                    {"name": n, "bytes": len(b), "sha256": digest(b)}
                    for n, b in sorted(files.items())]}
    return manifest, files

def write_once(path, data):
    if path.exists():
        require(read(path, TOTAL + CAP) == data, "EXISTING_OUTPUT_CONFLICT")
        return
    fd, tmp = tempfile.mkstemp(prefix=".report-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        # The existing Owner operation is serialized. No overwrite on Windows.
        if path.exists():
            require(read(path, TOTAL + CAP) == data, "EXISTING_OUTPUT_CONFLICT")
        else:
            os.rename(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def export(root, spool, outbox, source, nonce):
    manifest, files = make_bundle(root, spool, source, nonce)
    require(stat.S_ISDIR(plain(outbox).st_mode), "INBOX_NOT_ENROLLED")
    name = "ttv-report-" + source + "-" + nonce
    import io
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as z:
        for n, b in sorted({**files, "manifest.json": json_bytes(manifest)}.items()):
            z.writestr(zipfile.ZipInfo(n, (1980, 1, 1, 0, 0, 0)), b)
    data = buffer.getvalue()
    ready = {"schema": SCHEMA, "source": source, "nonce": nonce,
             "zip": name + ".zip", "sha256": digest(data), "bytes": len(data),
             "file_count": len(files)}
    write_once(outbox / ready["zip"], data)
    write_once(outbox / (name + ".ready.json"), json_bytes(ready))
    return ready

def verify(bundle, ready, source, nonce):
    valid_id(source, nonce)
    r = read_json(ready)
    name = "ttv-report-" + source + "-" + nonce
    data = read(bundle, TOTAL + CAP)
    require(r.get("schema") == SCHEMA and r.get("source") == source and r.get("nonce") == nonce
            and r.get("zip") == name + ".zip" and bundle.name == r["zip"]
            and digest(data) == r.get("sha256") and len(data) == r.get("bytes"), "BUNDLE_ID_OR_HASH")
    import io
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        infos = z.infolist()
        names = [i.filename for i in infos]
        require(len(names) == len(set(n.casefold() for n in names)) and len(names) <= 100
                and sum(i.file_size for i in infos) <= TOTAL + CAP, "ZIP_LIMIT_OR_DUPLICATE")
        for i in infos:
            n = i.filename
            p = PurePosixPath(n)
            require(not p.is_absolute() and ".." not in p.parts and "\\" not in n and ":" not in n
                    and not i.is_dir() and not stat.S_ISLNK(i.external_attr >> 16), "ZIP_PATH")
        manifest = json.loads(z.read("manifest.json"))
        require(manifest.get("schema") == SCHEMA and manifest.get("source") == source
                and manifest.get("nonce") == nonce
                and manifest.get("receipt_result") in ("SUCCESS", "FAILED_NO_RETRY"), "MANIFEST_ID")
        records = manifest["files"]
        declared = [x["name"] for x in records]
        require(len(declared) == len(set(declared)) == r.get("file_count")
                and set(names) == set(declared) | {"manifest.json"}
                and "manifest.json" not in declared and set(REQUIRED) <= set(declared), "MANIFEST_COVERAGE")
        for x in records:
            n = x["name"]
            require(n in REQUIRED + OPTIONAL or (n.startswith("browser-downloads/")
                    and len(PurePosixPath(n).parts) == 2
                    and PurePosixPath(n).suffix.lower() in (".srt", ".zip")), "UNEXPECTED_FILE")
            b = z.read(n)
            require(len(b) == x["bytes"] and digest(b) == x["sha256"], "MEMBER_HASH")
        h = json.loads(z.read("BRAIN_HANDOFF.json").decode("utf-8-sig"))
        q = json.loads(z.read("BRAIN_TEACHER_REPORT.json").decode("utf-8-sig"))
        b = json.loads(z.read("BRAIN_RESULT.json").decode("utf-8-sig"))
        require(h.get("source") == source and h.get("nonce") == nonce
                and h.get("original_source") == source and h.get("mode") == "LIVE"
                and q.get("source_commit") == source and b.get("handoff") == h, "REPORT_IDENTITY")
        expected = {}
        for a in q.get("artifacts", []):
            if a.get("copied_to_job") is True:
                key = "browser-downloads/" + safe_name(a["filename"])
                require(key not in expected, "DUPLICATE_REPORT_ARTIFACT")
                expected[key] = (a["bytes"], a["sha256"])
        actual = {x["name"]: (x["bytes"], x["sha256"]) for x in records
                  if x["name"].startswith("browser-downloads/")}
        require(actual == expected, "ARTIFACT_COVERAGE")
    return {"state": "BRAIN_BUNDLE_VERIFIED", "source": source, "nonce": nonce,
            "file_count": r["file_count"], "sha256": r["sha256"],
            "receipt_result": manifest["receipt_result"]}

def main():
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=("export", "verify"))
    p.add_argument("--source", required=True)
    p.add_argument("--nonce", required=True)
    p.add_argument("--inbox", type=Path)
    p.add_argument("--zip", type=Path)
    p.add_argument("--ready", type=Path)
    a = p.parse_args()
    if a.mode == "export":
        require(os.name == "nt" and os.environ.get("GITHUB_ACTIONS") != "true",
                "OWNER_CONTEXT_REQUIRED")
        require(a.inbox is not None, "INBOX_NOT_ENROLLED")
        result = export(Path(os.environ["LOCALAPPDATA"]) / "TorrentTVVietsub" / "NativeBrowserTest",
                        Path(os.environ["ProgramData"]) / "TorrentTVVietsub" / "LaptopHostOps",
                        a.inbox, a.source, a.nonce)
    else:
        require(a.zip is not None and a.ready is not None, "BUNDLE_AND_READY_REQUIRED")
        result = verify(a.zip, a.ready, a.source, a.nonce)
    print(json.dumps(result, sort_keys=True))

if __name__ == "__main__":
    main()
'@
$script=Join-Path ([IO.Path]::GetTempPath()) ('ttv-report-bridge-'+$rq.nonce+'.py')
try {
    [IO.File]::WriteAllText($script,$py,[Text.UTF8Encoding]::new($false))
    $raw=& py -3 -I -B $script export --source $source --nonce $nonce --inbox $inbox 2>$null
    if($LASTEXITCODE -ne 0){$receipt.reason='EXPORT_FAILED';Save-Receipt;return}
    $ready=($raw|Out-String)|ConvertFrom-Json
    if($ready.schema -cne 'TTV-REPORT-BRIDGE-V1' -or $ready.source -cne $source -or $ready.nonce -cne $nonce -or $ready.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'EXPORT_RECEIPT_INVALID'}
    $receipt.state='LOCAL_EXPORT_PASS'
    $receipt.reason='NONE'
    $receipt.sha256=$ready.sha256
    $receipt.file_count=[int]$ready.file_count
    $receipt.bytes=[long]$ready.bytes
    Save-Receipt
} finally { if(Test-Path -LiteralPath $script){Remove-Item -LiteralPath $script -Force} }
