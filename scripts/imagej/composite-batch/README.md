# Composite Batch (Fiji macro)

Batch-exports flattened colour composites from single-channel high-content images
(e.g. Cellomics `.C01` exported by HCS Studio from the CX7).

## Files
| File | Role |
|---|---|
| `Composite_Batch.ijm` | Fiji macro: builds and exports the composites |
| `Group-ImagesByWell.ps1` | Optional PowerShell pre-step: sorts a flat HCS Studio export into one subfolder per well |

## Optional pre-step: sort images by well
`Group-ImagesByWell.ps1` reads the well ID from names like
`MFGTMP_261104130001_A04f00d1.C01` and moves each file into `A04\`, `A05\` …
It never overwrites anything, leaves unrecognised files in place, and works on Windows 7 (PowerShell 2.0).

```powershell
# 1. Preview (moves nothing)
.\Group-ImagesByWell.ps1 -Path "D:\Exports\Plate1" -Extensions .C01 -WhatIf
# 2. Do it
.\Group-ImagesByWell.ps1 -Path "D:\Exports\Plate1" -Extensions .C01
# If Windows blocks scripts:
powershell -ExecutionPolicy Bypass -File .\Group-ImagesByWell.ps1 -Path "D:\Exports\Plate1" -Extensions .C01
```
The script's default extensions are `.tif, .tiff`. For CX7 `.C01` files, pass `-Extensions .C01`.

You can then run the macro on the plate folder with **Include subfolders** ticked.
With HCS Studio names, the channel texts are `d0`, `d1` …
The "nearest the end of the name wins" rule keeps a well like `D10` from being taken for channel `d1`.
The pre-step is optional, because the macro also pairs files correctly in one flat folder.

## Install
- **Run once:** Fiji > Plugins > Macros > Run... > `Composite_Batch.ijm`
- **Menu entry:** copy `Composite_Batch.ijm` to `Fiji.app/plugins/`, restart Fiji;
  it appears under Plugins as *Composite Batch*.

Needs Fiji (ImageJ 1.53t+). Bio-Formats, used for `.C01`, ships with Fiji.

## Workflow
| Step | Dialog | What you set |
|---|---|---|
| 1 | Folders | Source (+ subfolders, e.g. `plate\A01`), destination, extensions (default `.C01`), number of channels |
| 2 | Channel rules | One text per channel (e.g. `DAPI`, `GFP`), then a grouping check with counts and an example set |
| 3 | Colours & ranges | LUT + fixed min/max per channel; **Auto** from N random sets, **Preview** to tune with B&C |
| 4 | Export | Format, suffix, folder structure, overwrite, single channels, scale bar, label |

## How files are paired
For each file, the channel text is removed from its name. Files in the same folder
whose remaining names are identical form one set:

```
A01\Plate1_A01f00_DAPI.C01  ┐
A01\Plate1_A01f00_GFP.C01   ┘ -> set "Plate1_A01f00" -> Plate1_A01f00_composite.png
```

This matches files **by name, not by sorted position**, so a missing image cannot
shift the pairing. If several texts match one name, the one nearest the end wins
(tie: the longer one, so `EGFP` beats `GFP`).

## Auto range
For each of N random sets (default 20, complete sets first) the macro runs an
auto-contrast (0.35 % saturated pixels) per channel and then takes the **median**
(default, robust to empty wells) or the **mean** of the min and max values.
The seed makes the draw reproducible. The sampled sets are listed in the log.

## Outputs (destination folder)
- `<name><suffix>.png|tif|jpg`: flattened RGB composite
- `<name>_<channel>.<ext>`: optional single-channel images in their colour
- `CompositeBatch_log_<date-time>.txt`: file list, grouping, all settings, every file written/skipped

Source files are never modified. Settings are remembered between runs.

## Limits
- Channels: 1 to 7. Images of a set must have the same size and bit depth.
- Stacks: only the first plane is used.
- JPEG quality follows Edit > Options > Input/Output.

## Changelog
- **2026-11-07**: added the companion script `Group-ImagesByWell.ps1` (sort images by well).
- **1.0** (2026-11-05): first version: name-based pairing, fixed ranges, random-sample auto range, preview, scale bar, label, run log.
