"""Build the exact Flow 3 source-only overlay. Never install or run it."""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import zipfile

RECIPE = Path(__file__).with_name("flow3_owner_overlay.json")


def git_blob(data):
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def exact(data, expected):
    if git_blob(data) != expected:
        raise ValueError("FLOW3_SOURCE_BLOB_MISMATCH")
    return data


def replace_once(text, old, new):
    if not old or text.count(old) != 1:
        raise ValueError("FLOW3_PATCH_CONTEXT_MISMATCH")
    return text.replace(old, new, 1)


def apply_patch(raw, row):
    text = exact(raw, row["base_blob"]).decode("utf-8")
    if row["kind"] == "bridge":
        start, end = row["begin"], row["end"]
        if text.count(start) != 1 or text.count(end) != 1:
            raise ValueError("FLOW3_PATCH_CONTEXT_MISMATCH")
        i, j = text.index(start), text.index(end)
        if j <= i:
            raise ValueError("FLOW3_PATCH_CONTEXT_MISMATCH")
        text = text[:i] + row["replace_block"] + text[j:]
    elif row["kind"] != "literal":
        raise ValueError("FLOW3_PATCH_KIND")
    text = replace_once(text, row["old"], row["new"])
    return exact(text.encode("utf-8"), row["blob"])


def safe_path(name):
    p = PurePosixPath(name)
    if p.is_absolute() or ".." in p.parts or "\\" in name or str(p) != name:
        raise ValueError("FLOW3_PACKAGE_PATH")
    if not (name.startswith("app/poc/p2-sub-discovery/") or name.startswith("runner/")):
        raise ValueError("FLOW3_PACKAGE_SCOPE")
    return name


def assemble(recipe, read):
    """Read exact Git commit:path blobs via injected read-only transport."""
    if recipe["schema"] != "TTV-FLOW3-SOURCE-OVERLAY-V1":
        raise ValueError("FLOW3_RECIPE_SCHEMA")
    files = {}
    for row in recipe["patches"] + recipe["copies"]:
        name = safe_path(row["path"])
        if name in files:
            raise ValueError("FLOW3_PACKAGE_DUPLICATE")
        if "base_blob" in row:
            data = apply_patch(read(recipe["runtime_base"], row["source"]), row)
        else:
            data = exact(read(recipe["merged_g2_source"], row["source"]), row["blob"])
        if name.endswith(".py"):
            ast.parse(data, filename=name)
        files[name] = data
    # Verify the built payload against the independently pinned package tree.
    # Read-only git objects; no fetch, checkout, provider, device or host action.
    for name, data in files.items():
        if read(recipe["package_commit"], name) != data:
            raise ValueError("FLOW3_PACKAGE_SNAPSHOT_MISMATCH")
    metadata = read(recipe["package_commit"], "manifest.json")
    doc = json.loads(metadata)
    expected = [{"path": row["path"], "blob": row["blob"],
                 **({"base_blob": row["base_blob"]} if "base_blob" in row else {})}
                for row in recipe["patches"] + recipe["copies"]]
    if (doc.get("schema") != "TTV-FLOW3-SOURCE-PACKAGE-V1"
            or doc.get("runtime_base") != recipe["runtime_base"]
            or doc.get("merged_g2_source") != recipe["merged_g2_source"]
            or doc.get("files") != expected):
        raise ValueError("FLOW3_PACKAGE_MANIFEST_MISMATCH")
    files["manifest.json"] = metadata
    files["README.md"] = read(recipe["package_commit"], "README.md")
    return files


def write_zip(path, files):
    # Exclusive new file, fixed ordering and timestamp; no installed files touched.
    with path.open("xb") as stream:
        try:
            with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_STORED) as z:
                for name, data in sorted(files.items()):
                    info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                    info.create_system = 3
                    info.external_attr = 0o100644 << 16
                    z.writestr(info, data)
        except Exception:
            stream.close()
            path.unlink(missing_ok=True)
            raise


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args(argv)
    recipe = json.loads(RECIPE.read_text(encoding="utf-8"))
    def read(commit, path):
        return subprocess.check_output(["git", "-C", str(args.repo), "show", commit + ":" + path],
                                       stderr=subprocess.DEVNULL)
    files = assemble(recipe, read)
    write_zip(args.output, files)
    print("FLOW3_SOURCE_PACKAGE_PASS", len(files)-2, hashlib.sha256(args.output.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
