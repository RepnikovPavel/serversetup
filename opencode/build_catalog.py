#!/usr/bin/env python3
"""
build_catalog.py — merge the awesome-opencode registry (plugin descriptions)
with plugins.tsv (ordered install specs) into a single plugins_catalog.json.

Output: one entry per plugin with
    productId, displayName, repoUrl, tagline, description, tags, scope, candidates

`candidates` is the ordered list of specs to try with `opencode plugin <spec> -g`
(first one that installs wins). It comes straight from plugins.tsv.

Usage:
    ./build_catalog.py [registry.json] [plugins.tsv] [plugins_catalog.json]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REGISTRY = sys.argv[1] if len(sys.argv) > 1 else "/tmp/opencode/awesome-opencode/dist/registry.json"
TSV = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "plugins.tsv")
OUT = sys.argv[3] if len(sys.argv) > 3 else os.path.join(HERE, "plugins_catalog.json")


def read_tsv_candidates(path):
    """productId -> ordered list of candidate specs."""
    cands = {}
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 4:
                continue
            pid, _name, _repo, spec_field = parts[0], parts[1], parts[2], parts[3]
            specs = [s for s in spec_field.split(" ") if s]
            cands[pid] = specs
    return cands


def main():
    with open(REGISTRY) as f:
        registry = json.load(f)
    plugins = [e for e in registry if e.get("type") == "plugins"]
    cands = read_tsv_candidates(TSV)

    catalog = []
    missing_cands = []
    for e in plugins:
        pid = e.get("productId", "")
        cand_list = cands.get(pid)
        if not cand_list:
            missing_cands.append(pid)
            # fall back: derive a github spec from the repoUrl
            repo = (e.get("repoUrl") or "").strip().rstrip("/")
            tail = repo.split("github.com/")[-1] if "github.com/" in repo else ""
            cand_list = ["github:" + tail] if tail else []
        catalog.append({
            "productId": pid,
            "displayName": e.get("displayName") or pid,
            "repoUrl": e.get("repoUrl") or "",
            "tagline": (e.get("tagline") or "").strip(),
            "description": (e.get("description") or "").strip(),
            "tags": e.get("tags") or [],
            "scope": e.get("scope") or ["global"],
            "candidates": cand_list,
        })

    with open(OUT, "w") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)

    print(f"wrote {len(catalog)} plugins -> {OUT}")
    if missing_cands:
        print(f"note: {len(missing_cands)} plugins had no plugins.tsv entry, "
              f"derived github spec from repoUrl:")
        for pid in missing_cands:
            print(f"  - {pid}")


if __name__ == "__main__":
    main()
