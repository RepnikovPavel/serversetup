#!/usr/bin/env python3
"""
installer.py — TUI for browsing, installing and removing OpenCode plugins.

Layout (chosen: list on top, details below):
    ┌─ header: title + search + install counter ──────┐
    ├─ list pane: scrollable plugins (● installed / ○)│
    ├─ detail pane: tagline, full description, repo…  │
    └─ footer: hotkeys                                │

Install state is read from ~/.config/opencode/opencode.jsonc (jsonc-aware).
Installing shells out to `opencode plugin <spec> -g` (30s timeout, no retry);
removal edits the `plugin:` array in the config directly.

Keys: ↑↓/jk move · Enter install/remove · / search · n/N next/prev match
      r refresh status from config · d toggle full details (README + commits)
      q quit
"""
from __future__ import annotations

import curses
import datetime
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOG = os.path.join(HERE, "plugins_catalog.json")
CONFIG = os.path.expanduser("~/.config/opencode/opencode.jsonc")

INSTALL_TIMEOUT = 30  # seconds; hanging installs get killed
GH_TIMEOUT = 15        # seconds for each GitHub API call
README_MAX_LINES = 200  # cap rendered README so scrolling stays bounded


# ----------------------------------------------------------- github queries ---

def owner_repo(repo_url: str) -> str | None:
    """Extract 'owner/repo' from a GitHub URL.

    Returns None for non-GitHub hosts (gitee, codeberg, gist, ...) and
    unparseable input, so callers can skip GitHub-specific lookups.
    """
    if not repo_url:
        return None
    u = repo_url.strip().rstrip("/").rstrip("/")
    u = re.sub(r"\.git$", "", u)
    if "github.com" in u:
        if "gist.github.com" in u:
            return None
        tail = u.split("github.com/")[-1]
        parts = tail.split("/")
        if len(parts) >= 2 and parts[0] and parts[1]:
            return "/".join(parts[:2])
        return None
    if u.startswith("github:") and "http" not in u:
        parts = u[len("github:"):].split("/")
        if len(parts) >= 2 and parts[0] and parts[1]:
            return "/".join(parts[:2])
    return None


def _gh_api(endpoint: str, jq: str | None = None,
            paginate: bool = False, timeout: int = GH_TIMEOUT) -> str | None:
    """Run `gh api`, return stripped stdout or None on any failure."""
    args = ["gh", "api"]
    if paginate:
        args.append("--paginate")
    if jq:
        args += ["--jq", jq]
    args.append(endpoint)
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    if r.returncode != 0:
        return None
    return r.stdout.strip() or None


def count_commits_30d(owner_repo: str | None) -> int | None:
    """Number of commits in the last 30 days. None if unknown / not GitHub."""
    if not owner_repo:
        return None
    since = (datetime.datetime.utcnow() - datetime.timedelta(days=30)
             ).strftime("%Y-%m-%dT%H:%M:%SZ")
    out = _gh_api(f"repos/{owner_repo}/commits?since={since}&per_page=100",
                  jq="length", paginate=True)
    if out is None:
        return None
    total = 0
    for chunk in out.split():
        try:
            total += int(chunk)
        except ValueError:
            return None
    return total


def fetch_readme(owner_repo: str | None) -> str | None:
    """Raw README markdown from the default branch. None if unavailable."""
    if not owner_repo:
        return None
    url = _gh_api(f"repos/{owner_repo}/readme", jq=".download_url")
    if not url:
        return None
    try:
        r = subprocess.run(["curl", "-sL", url],
                           capture_output=True, text=True, timeout=GH_TIMEOUT)
    except subprocess.TimeoutExpired:
        return None
    if r.returncode != 0 or not r.stdout:
        return None
    return r.stdout


def render_markdown(md_text: str, width: int) -> list[str]:
    """Render markdown to plain-text lines (no ANSI) via rich.

    Code blocks keep their box framing, lists get bullets, headers are
    emphasised. Output is rstripped per line so curses won't draw trailing
    spaces over the right edge.
    """
    if not md_text:
        return []
    try:
        import io
        from rich.console import Console
        from rich.markdown import Markdown
    except ImportError:
        # fallback: just split raw markdown lines
        return [ln.rstrip() for ln in md_text.splitlines()][:README_MAX_LINES]
    width = max(40, width)
    # record=True + file=dev-null-buffer so rich never writes to the real
    # stdout/stderr (which would corrupt the curses screen).
    sink = io.StringIO()
    con = Console(file=sink, width=width, force_terminal=False,
                  color_system=None, highlight=False, record=True)
    con.print(Markdown(md_text))
    lines = [ln.rstrip() for ln in con.export_text().splitlines()]
    if len(lines) > README_MAX_LINES:
        lines = lines[:README_MAX_LINES] + ["… (README truncated)"]
    return lines


def fetch_plugin_extras(repo_url: str, detail_width: int) -> dict:
    """Collect commits-30d + rendered README for a plugin.

    Returns dict with keys: owner_repo, commits, readme_lines, error.
    Never raises — network/parse errors become an `error` message.
    """
    or_ = owner_repo(repo_url)
    result = {"owner_repo": or_, "commits": None,
              "readme_lines": [], "error": ""}
    if or_ is None:
        result["error"] = "not a GitHub repository (skipped)"
        return result
    commits = count_commits_30d(or_)
    result["commits"] = commits
    raw = fetch_readme(or_)
    if raw:
        result["readme_lines"] = render_markdown(raw, detail_width)
    else:
        result["error"] = "README unavailable"
    return result


# ---------------------------------------------------------------- config io ---

def _strip_jsonc(raw: str) -> str:
    """Strip /* block */ and // line comments from jsonc so json.loads works."""
    raw = re.sub(r"/\*.*?\*/", "", raw, flags=re.S)
    raw = re.sub(r"(^|[^:])//.*", r"\1", raw)
    return raw


def read_installed() -> set[str]:
    """Return the set of plugin specs currently in the config's plugin array."""
    try:
        raw = open(CONFIG).read()
    except FileNotFoundError:
        return set()
    try:
        cfg = json.loads(_strip_jsonc(raw))
    except Exception:
        return set()
    specs = set()
    for x in cfg.get("plugin") or []:
        if isinstance(x, list) and x:
            specs.add(x[0])
        elif isinstance(x, str):
            specs.add(x)
    return specs


def write_config(plugins: list[str]) -> None:
    """Rewrite the config with the given plugin spec list (plain json)."""
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    cfg = {
        "$schema": "https://opencode.ai/config.json",
        "plugin": plugins,
    }
    with open(CONFIG, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")


def remove_spec(spec: str) -> None:
    """Remove a single spec from the config's plugin array."""
    raw = open(CONFIG).read()
    try:
        cfg = json.loads(_strip_jsonc(raw))
    except Exception:
        cfg = {}
    plugins = []
    for x in cfg.get("plugin") or []:
        s = x[0] if isinstance(x, list) and x else x
        if isinstance(s, str) and s != spec:
            plugins.append(s)
    cfg["plugin"] = plugins
    cfg.setdefault("$schema", "https://opencode.ai/config.json")
    with open(CONFIG, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")


# --------------------------------------------------------------- install ------

def try_install(candidates: list[str]) -> tuple[bool, str, str]:
    """Try each candidate spec in order. Return (ok, chosen_spec, message)."""
    last_msg = ""
    for spec in candidates:
        try:
            proc = subprocess.run(
                ["opencode", "plugin", spec, "-g"],
                capture_output=True,
                text=True,
                timeout=INSTALL_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            last_msg = f"{spec}: timeout ({INSTALL_TIMEOUT}s)"
            continue
        out = (proc.stdout + proc.stderr).strip()
        if proc.returncode == 0:
            return True, spec, f"{spec}: installed"
        # keep a short tail of the failure message
        tail = out.splitlines()[-1] if out else f"exit {proc.returncode}"
        last_msg = f"{spec}: {tail[:120]}"
    return False, candidates[-1] if candidates else "?", last_msg


# ----------------------------------------------------------------- model -----

def load_catalog() -> list[dict]:
    with open(CATALOG) as f:
        return json.load(f)


def matches(p: dict, query: str) -> bool:
    if not query:
        return True
    q = query.lower()
    hay = " ".join([
        p.get("productId", ""),
        p.get("displayName", ""),
        p.get("tagline", ""),
        p.get("description", ""),
    ]).lower()
    return q in hay


# ------------------------------------------------------------------ ui -------

class UI:
    def __init__(self, stdscr: curses.window, catalog: list[dict]):
        self.stdscr = stdscr
        self.catalog = catalog
        self.query = ""
        self.searching = False
        self.cursor = 0            # index into filtered list
        self.top = 0               # first visible row in list pane
        self.detail_top = 0        # scroll offset of detail pane
        self.detail_mode = "brief"  # "brief" or "full"
        self._extras: dict[str, dict] = {}   # productId -> fetch_plugin_extras() result
        self.status = ""           # transient bottom-of-list message
        self.installed: set[str] = set()
        self.refresh_installed()

    # -- state --
    def refresh_installed(self):
        self.installed = read_installed()

    def filtered(self) -> list[dict]:
        return [p for p in self.catalog if matches(p, self.query)]

    def is_installed(self, p: dict) -> bool:
        return any(c in self.installed for c in p.get("candidates", []))

    def installed_count(self) -> int:
        return sum(1 for p in self.catalog if self.is_installed(p))

    # -- geometry --
    def _layout(self):
        h, w = self.stdscr.getmaxyx()
        header_h = 2
        footer_h = 1
        # split remaining space: list 45%, detail the rest (min 6 each)
        remain = h - header_h - footer_h - 2  # -2 for the two separator lines
        list_h = max(6, remain * 45 // 100)
        detail_h = remain - list_h
        return {
            "h": h, "w": w,
            "header_y": 0,
            "list_y": header_h + 1,            # after sep
            "list_h": list_h,
            "detail_y": header_h + 1 + list_h + 1,
            "detail_h": detail_h,
            "footer_y": h - 1,
        }

    # -- main loop --
    def run(self):
        curses.curs_set(0)
        self.stdscr.clear()
        while True:
            self.draw()
            ch = self.stdscr.getch()
            if self.searching:
                self._handle_search_key(ch)
            else:
                if self._handle_key(ch):
                    break

    # -- input --
    def _handle_search_key(self, ch):
        if ch in (27,):                      # Esc
            self.searching = False
            self.query = ""
            self.cursor = 0
            self.top = 0
        elif ch in (10, curses.KEY_ENTER):   # Enter: commit, stay filtered
            self.searching = False
        elif ch in (curses.KEY_BACKSPACE, 127, 8):
            self.query = self.query[:-1]
            self.cursor = 0
            self.top = 0
        elif 32 <= ch <= 126:
            self.query += chr(ch)
            self.cursor = 0
            self.top = 0

    def _handle_key(self, ch) -> bool:
        # returns True to quit
        layout = self._layout()
        if ch in (ord("q"), ord("Q")):
            return True
        # In full-details mode, j/k and arrows scroll the detail pane so the
        # README can be read without the list stealing focus. J/K (or PgUp/Dn)
        # still move the list so you can walk plugins without leaving full mode.
        if self.detail_mode == "full":
            if ch in (ord("j"), curses.KEY_DOWN):
                self.detail_top += 1; return False
            elif ch in (ord("k"), curses.KEY_UP):
                self.detail_top = max(0, self.detail_top - 1); return False
            elif ch in (ord("g"), curses.KEY_HOME):
                self.detail_top = 0; return False
        if ch in (ord("j"), curses.KEY_DOWN):
            self._move(1)
        elif ch in (ord("k"), curses.KEY_UP):
            self._move(-1)
        elif ch in (ord("J"), curses.KEY_NPAGE):
            self._move(layout["list_h"])
        elif ch in (ord("K"), curses.KEY_PPAGE):
            self._move(-layout["list_h"])
        elif ch == ord("g"):
            self.cursor = 0; self.top = 0
        elif ch == ord("G"):
            f = self.filtered(); self.cursor = max(0, len(f) - 1)
        elif ch == ord("/"):
            self.searching = True
            self.query = ""
            self.cursor = 0; self.top = 0
        elif ch in (ord("n"),):
            self._search_jump(+1)
        elif ch in (ord("N"),):
            self._search_jump(-1)
        elif ch in (10, curses.KEY_ENTER):
            self._toggle_current()
        elif ch in (ord("d"), ord("D")):
            self._toggle_full_details(force_refresh=(ch == ord("D")))
        elif ch == ord("r"):
            self.refresh_installed()
            self.status = "install status refreshed from config"
        elif ch == ord("R"):
            self.refresh_installed()
            self._extras.clear()
            self.status = "cleared detail cache (re-fetch on next d)"
        # detail scroll (fallback bindings, also available in brief mode)
        elif ch == ord("}"):
            self.detail_top += 1
        elif ch == ord("{"):
            self.detail_top = max(0, self.detail_top - 1)
        return False

    # -- full details (README + commits) --
    def _toggle_full_details(self, force_refresh: bool):
        f = self.filtered()
        if not f or self.cursor >= len(f):
            return
        p = f[self.cursor]
        if self.detail_mode == "full" and not force_refresh:
            # back to brief
            self.detail_mode = "brief"
            self.detail_top = 0
            self.status = ""
            return
        self.detail_mode = "full"
        self.detail_top = 0
        # fetch on demand; cache so scrolling/redraw doesn't re-hit GitHub
        if force_refresh:
            self._extras.pop(p["productId"], None)
        if p["productId"] not in self._extras:
            self.status = "loading README & commit activity from GitHub…"
            self.draw()
            self.stdscr.refresh()
            width = self._layout()["w"] - 2
            self._extras[p["productId"]] = fetch_plugin_extras(
                p.get("repoUrl", ""), width)
        ext = self._extras[p["productId"]]
        c = ext.get("commits")
        cstr = "unknown" if c is None else str(c)
        self.status = (f"commits(30d): {cstr}"
                       + (f"  ·  {ext['error']}" if ext.get("error") else ""))

    def _move(self, delta):
        f = self.filtered()
        if not f:
            return
        prev = self.cursor
        self.cursor = max(0, min(len(f) - 1, self.cursor + delta))
        if self.cursor != prev:
            self.detail_top = 0          # reset scroll on plugin change
            # Stay in the current detail mode: if full, the new plugin's
            # README will load on next redraw via _draw_detail/_toggle.
            if self.detail_mode == "full":
                # trigger fetch for the newly selected plugin (uses cache)
                self._ensure_full_extras(f[self.cursor])
        layout = self._layout()
        if self.cursor < self.top:
            self.top = self.cursor
        elif self.cursor >= self.top + layout["list_h"]:
            self.top = self.cursor - layout["list_h"] + 1

    def _ensure_full_extras(self, p):
        """If full mode is on but extras aren't cached for this plugin, fetch."""
        if not p or p["productId"] in self._extras:
            return
        width = self._layout()["w"] - 2
        self._extras[p["productId"]] = fetch_plugin_extras(
            p.get("repoUrl", ""), width)

    def _search_jump(self, direction):
        if not self.query:
            return
        f = self.filtered()
        n = len(f)
        if n == 0:
            return
        start = (self.cursor + direction) % n
        # filtered() already constrains to matches, so any row is a match;
        # jump just moves to next/prev visible.
        self.cursor = start
        layout = self._layout()
        if self.cursor < self.top:
            self.top = self.cursor
        elif self.cursor >= self.top + layout["list_h"]:
            self.top = self.cursor - layout["list_h"] + 1

    def _toggle_current(self):
        f = self.filtered()
        if not f or self.cursor >= len(f):
            return
        p = f[self.cursor]
        if self.is_installed(p):
            # remove: find which candidate is in the config and drop it
            to_remove = next(
                (c for c in p.get("candidates", []) if c in self.installed),
                None,
            )
            if to_remove:
                remove_spec(to_remove)
                self.refresh_installed()
                self.status = f"removed: {to_remove}"
            else:
                self.status = "marked installed but spec not found in config"
        else:
            self.status = "installing…"
            self.draw()                          # show "installing…"
            self.stdscr.refresh()
            ok, chosen, msg = try_install(p.get("candidates", []))
            self.refresh_installed()
            if ok:
                self.status = f"OK  {msg}"
            else:
                self.status = f"FAIL  {msg}"

    # -- drawing --
    def draw(self):
        self.stdscr.erase()
        layout = self._layout()
        self._draw_header(layout)
        self._draw_list(layout)
        self._draw_detail(layout)
        self._draw_footer(layout)
        self.stdscr.refresh()

    def _draw_header(self, L):
        w = L["w"]
        total = len(self.catalog)
        inst = self.installed_count()
        title = " OpenCode Plugin Installer "
        right = f"installed: {inst}/{total} "
        if self.searching:
            mid = f"search: {self.query}_"
        elif self.query:
            mid = f"filter: \"{self.query}\"  (n/N next/prev, Esc clear)"
        else:
            mid = "press / to search"
        # build a single header line, truncate middle if needed
        avail = w - len(title) - len(right)
        mid = mid[:max(0, avail)]
        line = title + mid.ljust(avail)[:avail] + right
        try:
            self.stdscr.addnstr(0, 0, line.ljust(w)[:w], w, curses.A_REVERSE)
        except curses.error:
            pass
        # separator
        self._hline(1, 0, w)

    def _draw_list(self, L):
        y = L["list_y"]; h = L["list_h"]; w = L["w"]
        f = self.filtered()
        if not f:
            try:
                self.stdscr.addstr(y, 0, "  (no plugins match)")
            except curses.error:
                pass
            return
        # clamp scroll
        if self.cursor < self.top:
            self.top = self.cursor
        elif self.cursor >= self.top + h:
            self.top = self.cursor - h + 1
        self.top = max(0, min(self.top, max(0, len(f) - h)))
        for i in range(h):
            idx = self.top + i
            if idx >= len(f):
                break
            p = f[idx]
            inst = self.is_installed(p)
            mark = "●" if inst else "○"
            name = p.get("displayName", p["productId"])
            tag = p.get("tagline", "")
            name_w = max(10, min(34, w // 3))
            left = f"  {mark} {name}"
            if len(left) > name_w + 2:
                left = left[: name_w + 1] + "…"
            tag_avail = w - len(left) - 2
            tag_disp = tag[:tag_avail] + ("…" if len(tag) > tag_avail else "")
            row = left.ljust(name_w + 2) + tag_disp
            attr = curses.A_REVERSE if idx == self.cursor else (curses.A_BOLD if inst else 0)
            try:
                self.stdscr.addnstr(y + i, 0, row.ljust(w)[:w], w, attr)
            except curses.error:
                pass
        # separator under the list
        self._hline(y + h, 0, w)

    def _draw_detail(self, L):
        y = L["detail_y"]; h = L["detail_h"]; w = L["w"]
        f = self.filtered()
        if not f or self.cursor >= len(f):
            return
        p = f[self.cursor]
        inst = self.is_installed(p)
        status_lbl = "[installed]" if inst else "[not installed]"
        inst_spec = next(
            (c for c in p.get("candidates", []) if c in self.installed), ""
        )

        # --- brief header (shown in both modes) ---
        lines = []  # list of (text, attr)
        lines.append((p.get("displayName", p["productId"]), curses.A_BOLD))
        lines.append((f"{status_lbl}  {p.get('tagline','')}", curses.A_NORMAL))
        lines.append(("", curses.A_NORMAL))
        for d in (p.get("description") or "").splitlines():
            lines.append((d, curses.A_NORMAL))
        lines.append(("", curses.A_NORMAL))

        if self.detail_mode == "full":
            ext = self._extras.get(p["productId"], {})
            # commit activity (live from GitHub, last 30 days)
            c = ext.get("commits")
            or_ = ext.get("owner_repo")
            if or_:
                cstr = "unknown" if c is None else str(c)
                lines.append((f"commits (last 30d): {cstr}   [{or_}]",
                              curses.A_BOLD))
            else:
                lines.append((f"commits (last 30d): n/a   ({ext.get('error','not GitHub')})",
                              curses.A_NORMAL))
            if ext.get("error") and or_:
                lines.append((f"  note: {ext['error']}", curses.A_NORMAL))
            lines.append(("", curses.A_NORMAL))
            # README rendered as markdown
            rm = ext.get("readme_lines") or []
            if rm:
                lines.append(("──── README (from repo) ────", curses.A_BOLD))
                lines.append(("", curses.A_NORMAL))
                for ln in rm:
                    lines.append((ln, curses.A_NORMAL))
            elif not or_:
                lines.append(("(no GitHub repo — README not fetched)",
                              curses.A_NORMAL))
            else:
                lines.append(("(README unavailable)", curses.A_NORMAL))
            lines.append(("", curses.A_NORMAL))

        # brief footer: tags / repo / specs (hidden in full to save space)
        if self.detail_mode == "brief":
            tags = ", ".join(p.get("tags") or []) or "(none)"
            lines.append((f"tags: {tags}", curses.A_NORMAL))
            repo = p.get("repoUrl", "")
            if repo:
                lines.append((f"repo: {repo}", curses.A_NORMAL))
            specs = " | ".join(p.get("candidates") or [])
            lines.append((f"specs: {specs}", curses.A_NORMAL))
            if inst_spec:
                lines.append((f"active spec: {inst_spec}", curses.A_NORMAL))
            hint = "press 'd' for full details (README + recent commits)"
            lines.append(("", curses.A_NORMAL))
            lines.append((hint, curses.A_DIM))

        # flatten with wrapping
        flat = []  # list of (text, attr)
        for text, attr in lines:
            if not text:
                flat.append(("", curses.A_NORMAL))
                continue
            for seg in self._wrap(text, w - 2):
                flat.append((seg, attr))

        # scroll
        max_top = max(0, len(flat) - h)
        self.detail_top = max(0, min(self.detail_top, max_top))
        for i in range(h):
            idx = self.detail_top + i
            if idx >= len(flat):
                break
            text, attr = flat[idx]
            try:
                self.stdscr.addnstr(y + i, 0, ("  " + text).ljust(w)[:w], w, attr)
            except curses.error:
                pass

    def _draw_footer(self, L):
        y = L["footer_y"]; w = L["w"]
        if self.detail_mode == "full":
            hot = (" ↑↓/jk scroll README · J/K switch plugin · "
                   "d back to brief · Enter install/remove · q quit ")
        else:
            hot = (" ↑↓/jk move · Enter install/remove · / search · n/N next · "
                   "d details · R refresh · q quit ")
        # status overrides hotkeys if present
        text = self.status if self.status else hot
        try:
            self.stdscr.addnstr(y, 0, text.ljust(w)[:w], w, curses.A_REVERSE)
        except curses.error:
            pass

    # -- helpers --
    def _hline(self, y, x, w):
        try:
            self.stdscr.addch(y, x, curses.ACS_HLINE)
            self.stdscr.hline(y, x + 1, curses.ACS_HLINE, w - 2)
            self.stdscr.addch(y, x + w - 1, curses.ACS_HLINE)
        except curses.error:
            try:
                self.stdscr.addstr(y, x, "-" * w)
            except curses.error:
                pass

    @staticmethod
    def _wrap(text, width):
        if width <= 0:
            return [text]
        out = []
        cur = ""
        for word in text.split(" "):
            if not cur:
                cur = word
            elif len(cur) + 1 + len(word) <= width:
                cur += " " + word
            else:
                out.append(cur)
                cur = word
        out.append(cur)
        return out


def _init_colors():
    try:
        curses.use_default_colors()
        curses.init_pair(1, -1, -1)
    except Exception:
        pass


def main(stdscr: curses.window):
    if not os.path.exists(CATALOG):
        print(f"catalog not found: {CATALOG}", file=sys.stderr)
        print("run ./build_catalog.py first", file=sys.stderr)
        sys.exit(2)
    catalog = load_catalog()
    _init_colors()
    UI(stdscr, catalog).run()


if __name__ == "__main__":
    curses.wrapper(main)
