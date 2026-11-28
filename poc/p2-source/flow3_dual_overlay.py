"""Source-only dual-lane patcher for disposable Owner and composed OMP trees.

Never use this as an installer. No fetch, provider, TV, or task action.
"""
from __future__ import annotations
import argparse
import ast
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
OWNER_RECIPE=HERE/"flow3_dual_owner.json"
TV_RECIPE=HERE/"flow3_dual_tv.json"


def transform(text, pairs):
    for old,new in pairs:
        if not old or text.count(old)!=1:
            raise ValueError("FLOW3_DUAL_ANCHOR_DRIFT")
        text=text.replace(old,new,1)
    return text


def plan(root, mode, recipe=None):
    if mode not in ("owner","tv"):
        raise ValueError("FLOW3_DUAL_MODE")
    recipe=recipe or json.loads((OWNER_RECIPE if mode=="owner" else TV_RECIPE).read_text(encoding="utf-8"))
    expected="TTV-FLOW3-DUAL-OWNER-V1" if mode=="owner" else "TTV-FLOW3-DUAL-TV-V1"
    if recipe["schema"]!=expected:
        raise ValueError("FLOW3_DUAL_SCHEMA")
    pairs={recipe["path"]:recipe["rules"]} if mode=="owner" else recipe["rules"]
    output={}
    for relative,rules in pairs.items():
        path=root/relative
        if not path.is_file() or path.is_symlink():
            raise ValueError("FLOW3_DUAL_SOURCE_MISSING")
        text=transform(path.read_text(encoding="utf-8"),rules)
        if path.suffix==".py":
            ast.parse(text)
        output[path]=text
    return output


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-root",type=Path,required=True)
    p.add_argument("--mode",choices=["owner","tv"],required=True)
    p.add_argument("--apply",action="store_true")
    args=p.parse_args(argv)
    if not args.source_root.is_absolute():
        raise ValueError("FLOW3_EXPLICIT_DISPOSABLE_ROOT")
    output=plan(args.source_root,args.mode)
    if args.apply:
        for path,text in output.items():
            path.write_text(text,encoding="utf-8")
    print("FLOW3_DUAL_SOURCE_"+("APPLIED" if args.apply else "DRY_RUN"),len(output))
    return 0


if __name__=="__main__":
    raise SystemExit(main())
