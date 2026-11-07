# Migration notes

Open items from the migration of 2026-11-07, and improvement ideas noticed while reading the scripts.
**None of the suggestions below has been applied**: the scripts are stored exactly as they were.

## Not migrated yet

See `not_migrated_yet` in `manifest.json`: the two Overlay Viewer macros, the Excel "Panier" VBA modules,
Report_Image_Browser, Move-ExportToNetwork (+ launcher), move_tiffs_to_images, and the later file versions of the
three examples. They will be added from their original files.

## Decisions pending

- Licence (none yet).
- Move-ExportToNetwork: the working copy holds internal network paths; publish the placeholder version only?
- Group-ImagesByWell: its comments contain a real-looking plate ID (`MFGTMP_261104130001`).
- VBA files: encoding (VBA's editor imports `.bas` files as Windows-1252, the code contains French accents).

## Status of the migrated files

- `composite-batch`: written 2026-11-05 without access to Fiji; never run.
- `group-images-by-well`: not known to have been run.
- The three examples (`batch-convert-to-tiff`, `folder-sizes`, `merge-csv-files`) are the demo snippets seeded into the
  Script Shelf artifact; never tested. They were copied from the artifact's database text, so their "before" hash is
  of that copy; a byte check against Script Shelf > Export is still possible.

## Improvement ideas (not applied)

- **Group-ImagesByWell.ps1**: default extensions are `.tif, .tiff`; CX7 `.C01` exports need `-Extensions .C01`.
  Adding `.C01` to the defaults would save typing.
- **batch_convert_to_tiff.ijm**: the final "Done: N items processed" counts every entry of the folder, including the
  skipped subfolders.
- **folder_sizes.ps1**: needs PowerShell 3+ (`-Directory`, `-File`, `[PSCustomObject]`), so it fails on the
  Windows 7 PCs; the folder is hard-coded in `$root` (the later repo variant takes `-Root`).
- **merge_csv_files.py**: the folder is hard-coded; an empty folder makes `pd.concat` raise an error.
- **Composite_Batch README**: mentions `Group-ImagesByWell.ps1` as sitting next to the macro; in this repository it is
  in `scripts/powershell/group-images-by-well/`.
