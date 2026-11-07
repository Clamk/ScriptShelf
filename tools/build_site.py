#!/usr/bin/env python3
"""Validate the catalogue and assemble the static site in _site/.

Used by the GitHub Actions workflow and for local previews:

    python tools/build_site.py            # validate, then build _site/
    python tools/build_site.py --check    # validate only
    python -m http.server -d _site 8000   # preview at http://localhost:8000

Errors stop the build. Warnings are printed but do not stop it.
Standard library only, so it runs anywhere Python 3.8+ is installed.
"""
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGUE = ROOT / "catalogue" / "scripts.json"
WEBSITE = ROOT / "website"
SCRIPTS = ROOT / "scripts"
OUT = ROOT / "_site"

ESSENTIAL_SITE_FILES = ["index.html", "assets/css/app.css", "assets/js/app.js", "assets/js/highlight.js"]
REQUIRED_FIELDS = {
    "id": str, "name": str, "category": str, "language": str, "summary": str,
    "description": str, "tags": list, "path": str, "extension": str,
    "supporting_files": list, "requirements": list, "usage": list, "inputs": list,
    "outputs": list, "warnings": list, "example": bool, "added": str,
}
OPTIONAL_NULLABLE = {"tested_on": str, "created": str}
ID_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# Patterns that must never be published (errors) and ones worth a second look (warnings).
SECRET_ERRORS = [
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "private key"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b|\bgithub_pat_[A-Za-z0-9_]{50,}"), "GitHub token"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS access key"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{32,}"), "API secret key"),
]
SECRET_WARNINGS = [
    (re.compile(r"(?i)\b(password|passwd|pwd|secret|api[_-]?key|token)\b\s*[:=]\s*['\"][^'\"]{4,}['\"]"), "hard-coded credential?"),
    (re.compile(r"\\\\[A-Za-z0-9_.-]+\\[A-Za-z0-9_$.-]+"), "network (UNC) path"),
    (re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"), "e-mail address"),
]
TEXT_LIMIT = 5_000_000   # skip the secret scan on very large files

errors, warnings = [], []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def safe_rel_path(p, field, sid):
    """Repo-relative path inside scripts/, existing, no '..' or absolute paths."""
    if not isinstance(p, str) or not p:
        err(f"{sid}: {field} is empty")
        return None
    if p.startswith(("/", "\\")) or re.match(r"^[A-Za-z]:", p) or ".." in Path(p).parts or "\\" in p:
        err(f"{sid}: {field} must be a relative path with '/' separators: {p}")
        return None
    if not p.startswith("scripts/"):
        err(f"{sid}: {field} must be inside scripts/: {p}")
        return None
    full = ROOT / p
    if not full.is_file():
        err(f"{sid}: {field} not found: {p}")
        return None
    return full


def validate_catalogue():
    try:
        data = json.loads(CATALOGUE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        err(f"missing {CATALOGUE.relative_to(ROOT)}")
        return None
    except json.JSONDecodeError as e:
        err(f"catalogue is not valid JSON: {e}")
        return None

    for key in ("title", "repository", "categories", "scripts"):
        if key not in data:
            err(f"catalogue: missing top-level '{key}'")
    if errors:
        return None
    repo = data["repository"]
    for key in ("owner", "name", "branch"):
        if not isinstance(repo.get(key), str) or not repo.get(key):
            err(f"catalogue: repository.{key} missing")

    cat_ids = []
    for c in data["categories"]:
        if not isinstance(c, dict) or not ID_RE.match(str(c.get("id", ""))) or not c.get("label"):
            err(f"catalogue: bad category entry {c!r}")
            continue
        cat_ids.append(c["id"])
    if len(cat_ids) != len(set(cat_ids)):
        err("catalogue: duplicate category id")

    seen_ids, seen_paths, used = set(), set(), set()
    for i, s in enumerate(data["scripts"]):
        sid = s.get("id", f"#{i}") if isinstance(s, dict) else f"#{i}"
        if not isinstance(s, dict):
            err(f"script {sid}: not an object")
            continue
        for field, typ in REQUIRED_FIELDS.items():
            if field not in s:
                err(f"{sid}: missing field '{field}'")
            elif not isinstance(s[field], typ):
                err(f"{sid}: '{field}' should be {typ.__name__}")
        for field, typ in OPTIONAL_NULLABLE.items():
            if s.get(field) is not None and not isinstance(s[field], typ):
                err(f"{sid}: '{field}' should be {typ.__name__} or null")
        for field in ("tags", "requirements", "usage", "inputs", "outputs", "warnings"):
            if isinstance(s.get(field), list) and not all(isinstance(x, str) and x.strip() for x in s[field]):
                err(f"{sid}: '{field}' must contain non-empty strings only")
        if not ID_RE.match(str(s.get("id", ""))):
            err(f"{sid}: id must be lowercase-with-dashes")
        if sid in seen_ids:
            err(f"{sid}: duplicate id")
        seen_ids.add(sid)
        if s.get("category") not in cat_ids:
            err(f"{sid}: unknown category '{s.get('category')}'")
        for field in ("added", "created"):
            if s.get(field) is not None and not DATE_RE.match(str(s[field])):
                err(f"{sid}: '{field}' must be YYYY-MM-DD")

        full = safe_rel_path(s.get("path"), "path", sid)
        if full:
            if s["path"] in seen_paths:
                err(f"{sid}: path used by another entry: {s['path']}")
            seen_paths.add(s["path"])
            used.add(full)
            if s.get("extension") and not s["path"].lower().endswith(s["extension"].lower()):
                err(f"{sid}: extension '{s['extension']}' does not match {s['path']}")
        for field in ("supporting_files", "versions"):
            items = s.get(field, [])
            if not isinstance(items, list):
                err(f"{sid}: '{field}' should be a list")
                continue
            for j, sf in enumerate(items):
                if not isinstance(sf, dict) or not sf.get("label"):
                    err(f"{sid}: {field}[{j}] needs a path and a label")
                    continue
                if sf.get("date") is not None and not DATE_RE.match(str(sf["date"])):
                    err(f"{sid}: {field}[{j}].date must be YYYY-MM-DD")
                f = safe_rel_path(sf.get("path"), f"{field}[{j}]", sid)
                if f:
                    if f in used:
                        err(f"{sid}: {sf['path']} is listed twice")
                    used.add(f)
        if not s.get("requirements"):
            warn(f"{sid}: no requirements documented")
        if not s.get("tested_on"):
            warn(f"{sid}: 'tested_on' not documented")

    for f in SCRIPTS.rglob("*"):
        if f.is_file() and f not in used and f.name != ".gitkeep":
            warn(f"not in the catalogue: {f.relative_to(ROOT).as_posix()}")
    used_cats = {s.get("category") for s in data["scripts"] if isinstance(s, dict)}
    for c in cat_ids:
        if c not in used_cats:
            warn(f"category '{c}' has no scripts (hidden on the site)")
    return data


def scan_secrets():
    for f in sorted(SCRIPTS.rglob("*")):
        if not f.is_file() or f.stat().st_size > TEXT_LIMIT:
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rel = f.relative_to(ROOT).as_posix()
        for n, line in enumerate(text.splitlines(), 1):
            for rx, what in SECRET_ERRORS:
                if rx.search(line):
                    err(f"{rel}:{n}: looks like a {what}; remove it before publishing")
            for rx, what in SECRET_WARNINGS:
                if rx.search(line):
                    warn(f"{rel}:{n}: {what}, check before publishing")


def build():
    missing = [p for p in ESSENTIAL_SITE_FILES if not (WEBSITE / p).is_file()]
    for p in missing:
        err(f"missing website/{p}")
    if errors:
        return
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(WEBSITE, OUT)
    shutil.copytree(ROOT / "catalogue", OUT / "catalogue")
    shutil.copytree(SCRIPTS, OUT / "scripts")


def main():
    check_only = "--check" in sys.argv[1:]
    data = validate_catalogue()
    scan_secrets()
    if not check_only and not errors:
        build()

    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"ERROR:   {e}")
    if errors:
        print(f"\n{len(errors)} error(s): nothing built.")
        return 1
    n = len(data["scripts"]) if data else 0
    done = "catalogue valid" if check_only else f"site built in {OUT.relative_to(ROOT)}/"
    print(f"\nOK: {n} script(s), {len(warnings)} warning(s), {done}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
