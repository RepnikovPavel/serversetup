#!/usr/bin/env python3
"""
Generate plugins.tsv: one line per OpenCode plugin listed in the
awesome-opencode registry (https://github.com/awesome-opencode/awesome-opencode).

Output columns (tab-separated):
    productId<TAB>displayName<TAB>repoUrl<TAB>spec

`spec` is what we hand to `opencode plugin <spec>`:
  * explicit npm package name when the YAML `installation` field declares one
    (covers scoped / monorepo packages such as @xberg-io/...),
  * otherwise `github:owner/repo`, which works for any repo that ships a valid
    opencode plugin module regardless of its published npm name.

Re-run any time to refresh the manifest against the latest upstream registry.
"""
import json
import os
import re
import subprocess
import sys

REPO = "https://github.com/awesome-opencode/awesome-opencode.git"
CLONE_DIR = sys.argv[1] if len(sys.argv) > 1 else "/tmp/opencode/awesome-opencode"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "plugins.tsv"
)


def clone(path):
    if os.path.isfile(os.path.join(path, "dist", "registry.json")):
        return path
    subprocess.run(
        ["git", "clone", "--depth", "1", REPO, path],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return path


def owner_repo(url):
    url = url.rstrip("/")
    tail = url.split("github.com/")[-1]
    return tail  # owner/repo


def plugin_meta(yaml_dir):
    """repoUrl -> {"names": [npm specs from `installation`], "yaml_name": name}."""
    try:
        import yaml
    except ImportError:
        subprocess.run(
            [sys.executable, "-m", "pip", "install", "-q", "pyyaml"],
            check=True,
        )
        import yaml

    meta = {}
    for fn in sorted(os.listdir(yaml_dir)):
        if not fn.endswith(".yaml"):
            continue
        with open(os.path.join(yaml_dir, fn)) as f:
            d = yaml.safe_load(f)
        repo = (d.get("repo") or "").strip()
        names = []
        for grp in re.findall(r'"plugin":\s*\[([^\]]*)\]', d.get("installation") or ""):
            names += re.findall(r'"([^"]+)"', grp)
        meta[repo] = {"names": names, "yaml_name": (d.get("name") or "").strip()}
    return meta


def is_npm_shaped(s):
    return bool(re.match(r"^@?[a-z0-9][a-z0-9._-]*(?:/[a-z0-9][a-z0-9._-]*)?$", s))


def candidates_for(repo, meta):
    """Ordered install specs to try. npm package first (it ships the built
    entrypoints opencode's loader requires), github source last (often lacks
    those entrypoints, so it is only a fallback)."""
    cands = []
    m = meta.get(repo, {})
    for n in m.get("names", []):
        if n not in cands:
            cands.append(n)
    yn = m.get("yaml_name", "")
    if yn and is_npm_shaped(yn) and yn not in cands:
        cands.append(yn)
    base = repo.rstrip("/").split("/")[-1].lower()
    if is_npm_shaped(base) and base not in cands:
        cands.append(base)
    gh = "github:" + owner_repo(repo)
    if gh not in cands:
        cands.append(gh)
    return cands


def main():
    path = clone(CLONE_DIR)
    with open(os.path.join(path, "dist", "registry.json")) as f:
        registry = json.load(f)
    meta = plugin_meta(os.path.join(path, "data", "plugins"))

    plugins = [e for e in registry if e.get("type") == "plugins"]
    rows = []
    for e in plugins:
        repo = e.get("repoUrl", "")
        cands = candidates_for(repo, meta)
        rows.append((e.get("productId", ""), e.get("displayName", ""), repo, " ".join(cands)))

    with open(OUT, "w") as f:
        f.write("# productId\tdisplayName\trepoUrl\tcandidates(space-separated, tried in order)\n")
        for r in rows:
            f.write("\t".join(r) + "\n")
    print(f"wrote {len(rows)} plugins -> {OUT}")
    for r in rows[:8]:
        print("  ", r[0], "|", r[3])


if __name__ == "__main__":
    main()
