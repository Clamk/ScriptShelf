<#
.SYNOPSIS
    Sorts CX7 / HCS Studio image exports into one subfolder per well.

.DESCRIPTION
    Reads the well ID from each file name and moves the file into a folder
    named after that well, created next to the images:

        MFGTMP_261104130001_A04f00d1.tiff  ->  A04\MFGTMP_261104130001_A04f00d1.tiff

    Rules
      - Only files directly inside -Path are processed (subfolders are ignored).
      - Files without a recognisable well ID are left where they are and listed.
      - A file that already exists in the well folder is never overwritten (skipped).
      - Run with -WhatIf first to preview without moving anything.

    Compatible with Windows PowerShell 2.0 (Windows 7) and later.

.PARAMETER Path
    Folder containing the images. Default: current folder.

.PARAMETER Extensions
    File extensions to process. Default: .tif, .tiff

.EXAMPLE
    .\Group-ImagesByWell.ps1 -Path "D:\Exports\Plate1" -WhatIf
    Preview only: lists what would be moved.

.EXAMPLE
    .\Group-ImagesByWell.ps1 -Path "D:\Exports\Plate1"
    Does the move.

.NOTES
    If Windows blocks the script ("running scripts is disabled"), launch it with:
    powershell -ExecutionPolicy Bypass -File .\Group-ImagesByWell.ps1 -Path "D:\Exports\Plate1"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [string]$Path = (Get-Location).Path,

    [string[]]$Extensions = @('.tif', '.tiff')
)

# --- File name pattern -------------------------------------------------------
# <plate>_<well>f<field>d<channel>
#   plate   : everything before the last "_<well>f..d.." block (MFGTMP_261104130001)
#   well    : 1-2 letters + 2 digits (A04; also AF48 for 1536-well plates)
#   field   : f00, f01, ...
#   channel : d0, d1, ...
$pattern = '^(?<plate>.+)_(?<well>[A-Za-z]{1,2}\d{2})f\d+d\d+'

# --- Checks ------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Error "Folder not found: $Path"
    exit 1
}
$Path   = (Resolve-Path -LiteralPath $Path).ProviderPath
$extSet = $Extensions | ForEach-Object { $_.ToLower() }

$files = @(Get-ChildItem -LiteralPath $Path |
           Where-Object { -not $_.PSIsContainer -and ($extSet -contains $_.Extension.ToLower()) })

if ($files.Count -eq 0) {
    Write-Host "No $($Extensions -join '/') files found in $Path"
    exit 0
}

# --- Main loop ---------------------------------------------------------------
$moved     = 0
$skipped   = 0
$failed    = 0
$unmatched = @()
$perWell   = @{}   # well  -> number of files
$plates    = @{}   # plate -> $true (to detect mixed plates)
$i         = 0

foreach ($file in $files) {
    $i++
    if ($i % 50 -eq 0 -or $i -eq $files.Count) {
        Write-Progress -Activity "Sorting images by well" `
                       -Status "$i / $($files.Count)" `
                       -PercentComplete ([int](100 * $i / $files.Count))
    }

    if ($file.Name -notmatch $pattern) {
        $unmatched += $file.Name
        continue
    }
    $well = $Matches['well'].ToUpper()
    $plates[$Matches['plate']] = $true

    $destDir  = Join-Path $Path $well
    $destFile = Join-Path $destDir $file.Name

    if (Test-Path -LiteralPath $destFile) {
        Write-Warning "Already in $well\, skipped: $($file.Name)"
        $skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($file.Name, "Move to $well\")) {
        try {
            [void][System.IO.Directory]::CreateDirectory($destDir)   # no-op if it exists
            Move-Item -LiteralPath $file.FullName -Destination $destFile -ErrorAction Stop
            $moved++
        }
        catch {
            Write-Warning "Failed to move $($file.Name): $($_.Exception.Message)"
            $failed++
            continue
        }
    }
    $perWell[$well] = 1 + [int]$perWell[$well]
}
Write-Progress -Activity "Sorting images by well" -Completed

# --- Summary -----------------------------------------------------------------
$dryRun = [bool]$WhatIfPreference
Write-Host ""
Write-Host "Folder : $Path"
if ($dryRun) { Write-Host "Mode   : PREVIEW (-WhatIf) - nothing was moved" -ForegroundColor Yellow }
Write-Host ("Wells  : {0}" -f $perWell.Count)
if ($dryRun) {
    Write-Host ("Would move : {0} files" -f ($perWell.Values | Measure-Object -Sum).Sum)
} else {
    Write-Host ("Moved      : {0} files" -f $moved)
}
if ($skipped) { Write-Host ("Skipped    : {0} (already in well folder)" -f $skipped) -ForegroundColor Yellow }
if ($failed)  { Write-Host ("Failed     : {0}" -f $failed) -ForegroundColor Red }

if ($plates.Count -gt 1) {
    Write-Warning ("{0} different plates found in this folder; their images were grouped into the same well folders: {1}" -f `
                   $plates.Count, (($plates.Keys | Sort-Object) -join ', '))
}

if ($unmatched.Count) {
    Write-Host ("Not recognised, left in place: {0}" -f $unmatched.Count) -ForegroundColor Yellow
    $unmatched | Select-Object -First 10 | ForEach-Object { Write-Host "   $_" }
    if ($unmatched.Count -gt 10) { Write-Host "   ..." }
}

# Files per well, in plate order (A01, A02, ... B01 ...)
$perWell.GetEnumerator() | Sort-Object Name |
    Format-Table @{ Label = 'Well'; Expression = { $_.Name } },
                 @{ Label = 'Files'; Expression = { $_.Value } } -AutoSize
