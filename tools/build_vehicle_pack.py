#!/usr/bin/env python3
"""Build dist/otbt_overland.zip, the OTBT Overland vehicle pack (vehicles/otbt_overland).

    python3 tools/build_vehicle_pack.py [--out DIR] [--allow-missing]

The zip holds vehicles/otbt_overland/mod/ as the game's own layout, plus info_<config>.json for every build in
vehicles/otbt_overland/builds.json (its name, the brand, a description). A build without its saved config
(mod/vehicles/<model>/<config>.pc) stops the build, unless --allow-missing (then it is left out with a warning).
"""

import argparse
import io
import json
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK = os.path.join(ROOT, "vehicles", "otbt_overland")
NAME = "otbt_overland.zip"


def load_builds():
    with open(os.path.join(PACK, "builds.json"), encoding="utf-8") as f:
        return json.load(f)


def info_json(spec, brand):
    """The config's info file, as the game's vehicle selector reads it."""
    return {
        "Configuration": spec["name"],
        "Description": f"{spec['role']}. An {brand['name']} overland build ({brand['url']}).",
        "Source": "Mod"
    }


def pack_bytes(allow_missing=False):
    """The pack's zip, in memory, and the configs left out."""
    data = load_builds()
    mod = os.path.join(PACK, "mod")
    missing = []
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for dirpath, dirnames, filenames in os.walk(mod):
            dirnames.sort()
            for name in sorted(filenames):
                if name in (".keep", ".DS_Store"):
                    continue
                src = os.path.join(dirpath, name)
                z.write(src, os.path.relpath(src, mod).replace(os.sep, "/"))
        for spec in data["builds"]:
            pc = os.path.join(mod, "vehicles", spec["model"], spec["config"] + ".pc")
            if not os.path.isfile(pc):
                missing.append(f"{spec['model']}/{spec['config']}.pc")
                continue
            z.writestr(f"vehicles/{spec['model']}/info_{spec['config']}.json",
                       json.dumps(info_json(spec, data["brand"]), indent=2))
    if missing and not allow_missing:
        sys.exit("missing saved configs (see vehicles/otbt_overland/MODDER_BRIEF.md): " + ", ".join(missing))
    for m in missing:
        print(f"warning: {m} not saved yet, left out", file=sys.stderr)
    return buf.getvalue(), missing


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=os.path.join(ROOT, "dist"), help="output folder (default: dist/)")
    ap.add_argument("--allow-missing", action="store_true", help="leave out builds not saved yet")
    args = ap.parse_args()
    raw, _ = pack_bytes(args.allow_missing)
    os.makedirs(args.out, exist_ok=True)
    path = os.path.join(args.out, NAME)
    with open(path, "wb") as f:
        f.write(raw)
    print(f"{path}: {len(raw) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
