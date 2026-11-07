# Script Shelf

A catalogue of my scripts for high-content imaging and everyday lab data chores: Fiji macros, PowerShell, Python.

- **Website:** https://clamk.github.io/ScriptShelf/ (search, filters, code preview, copy, download)
- **Source of truth:** this repository. The scripts are plain files in `scripts/` and work without the website.

## Repository layout

```
scripts/<category>/<script-id>/   the scripts, stored exactly as written (one folder per script,
                                  so supporting files such as a README or a launcher stay together)
catalogue/scripts.json            metadata for every script; the website reads it
website/                          the static site (HTML, CSS, vanilla JavaScript, no dependencies)
tools/build_site.py               validates the catalogue and assembles the site in _site/
migration/manifest.json           where each migrated file came from, with SHA-256 hashes
migration/NOTES.md                open items and suggested script improvements (not applied)
.github/workflows/deploy.yml      validate, build and deploy to GitHub Pages on every push to main
```

Script metadata lives in the catalogue, not in the script files, so adding a script to the shelf never changes the script itself.

## Add a script

1. Create `scripts/<category>/<script-id>/` and put the file in it unchanged, plus any supporting files.
   `script-id` is lowercase with dashes, e.g. `group-images-by-well`.
2. Add an entry to `catalogue/scripts.json` (copy an existing one). Fill in only what is known; leave lists empty and
   `tested_on` / `created` as `null` when not documented: the site shows them as "not documented".
3. Optional: preview locally (below).
4. Commit and push to `main`. The workflow validates and deploys; the site updates within a minute or two.

| Field | Meaning |
|---|---|
| `id`, `name`, `category`, `language` | identifier, display name, category id, language label |
| `summary`, `description` | one line for the card; full text for the script page |
| `tags` | lowercase keywords used for filters and search |
| `path`, `extension`, `supporting_files` | main file, its extension, extra files (`{path, label}`) |
| `requirements`, `usage`, `inputs`, `outputs`, `warnings` | lists of short sentences |
| `tested_on` | where it was actually run, e.g. `Fiji 2.14, Windows 10`, or `null` |
| `example` | `true` for demo snippets |
| `created` | when the script was originally written, if known |
| `added` | when it was added to this repository (drives "Recently added") |

**New category:** add `{ "id": "...", "label": "..." }` to `categories` and the folder `scripts/<id>/`.
A colour can be added in `website/assets/css/app.css` as `--cat-<id>`. Categories without scripts are hidden.

## Preview locally

```
python tools/build_site.py
python -m http.server -d _site 8000
```

Then open http://localhost:8000. `python tools/build_site.py --check` only validates.
The build stops on errors (invalid catalogue, missing file, something that looks like a key or token) and prints
warnings for things worth a look (undocumented fields, network paths, e-mail addresses, files changed since migration).

## Deployment

GitHub Actions (`.github/workflows/deploy.yml`) runs on every push to `main` and can be started by hand from the
Actions tab. One-time setup: **Settings > Pages > Build and deployment > Source: GitHub Actions**.

## Integrity

`.gitattributes` stores `scripts/` byte for byte (no line-ending conversion), so the hashes in
`migration/manifest.json` stay valid on every machine. The build warns when a file no longer matches its migration hash,
which is expected after an intentional edit.

## Licence

No licence has been chosen yet. Until one is added, the code is visible but all rights are reserved.
