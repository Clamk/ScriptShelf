# Migration notes

Open items from the migration of 2026-11-07, and improvement ideas noticed while reading the scripts.
**None of the suggestions below has been applied**: the scripts are stored exactly as they were found.

## How each file was obtained

`manifest.json` gives a status per file:

- **verified**: byte copy of an original file (Composite Batch + README, Group-ImagesByWell).
- **extracted**: pulled by script from a saved chat transcript (27 Oct versions of the three examples).
- **reconstructed**: Move-ExportToNetwork.ps1, first version written from the transcript, then the three recorded
  edits of that chat replayed mechanically; each edit matched the text exactly once.
- **transcribed**: copied from displayed text, so it cannot be byte-verified here: the Overlay Viewer macros and the
  Panier VBA (from claude.ai artifacts), move_tiffs_to_images.ps1, the launchers, the first Move-Export version and the
  22 Oct examples. Checks done: bracket and block balance, ASCII where expected.
  Quick check against the artifacts: Overlay_Viewer_v2.ijm page shows **301 lines · 10.5 KB**; Code du Panier tabs show
  **489 / 118 / 14** lignes (modPanier / modEquiperPanier / ThisWorkbook).

Replacing a transcribed file by the original from your PC is the best fix: copy it over, the build then warns that it
changed since migration, and the diff shows any difference.

## Not migrated

- **Report_Image_Browser.py v2.9.1** (+ README, tests, archive): built over many versions with scripted edits (including
  a spaces-to-tabs conversion) and about 100,000 characters; a reconstruction from the chat could not be trusted.
  Needs the original file.
- **Move-ExportToNetwork.ps1, current working version** (progress display, archive folder next to the logs): contains
  internal network paths and a local user path. Held back until approved; the published file is the 5 Nov version with
  placeholder paths.

## Decisions pending

- Licence (none yet).
- Overlay Viewer: two variants kept (Overlay_Viewer_v2.ijm as main, Overlay_Viewer.ijm as the other); which one is
  current is not documented.
- Group-ImagesByWell: its comments contain a real-looking plate ID (`MFGTMP_261104130001`).
- VBA files are stored in UTF-8, as in the artifact. They are meant to be pasted into the VBA editor; an import with
  File > Import would need Windows-1252 encoding and an `Attribute VB_Name` header.

## Improvement ideas (not applied)

- **Group-ImagesByWell.ps1**: default extensions are `.tif, .tiff`; CX7 `.C01` exports need `-Extensions .C01`.
- **batch_convert_to_tiff.ijm**: the final "Done: N items processed" counts every entry of the folder, including the
  skipped subfolders.
- **folder_sizes.ps1**: needs PowerShell 3+ (`-Directory`, `-File`, `[PSCustomObject]`), so it fails on the
  Windows 7 PCs.
- **Move-ExportToNetwork.ps1**: a file with the same name at the destination is overwritten (documented in the manual).
- **Composite_Batch README**: mentions `Group-ImagesByWell.ps1` as sitting next to the macro; in this repository it is
  in `scripts/powershell/group-images-by-well/`.
