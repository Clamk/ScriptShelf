# ---
# title: Move all TIFF files into an "images" subfolder
# tags: files, tiff, organise
# tested:
# notes: Put the script in the folder that holds the TIFFs and run it (right-click > Run with PowerShell).
#   It creates an "images" subfolder there and moves every .tif / .tiff file of that folder into it.
#   Subfolders are not searched. A file that already exists in images is skipped, never overwritten.
#
#   - Preview without moving anything: .\move_tiffs_to_images.ps1 -WhatIf
#   - Another folder or subfolder name: .\move_tiffs_to_images.ps1 -Folder <folder> -Subfolder raw
#   - Works with PowerShell 2.0 (Windows 7) and newer.
# ---
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Folder,               # default: the folder this script is in
    [string]$Subfolder = "images"  # name of the subfolder to create
)

if (-not $Folder) {
    if ($MyInvocation.MyCommand.Path) { $Folder = Split-Path -Parent $MyInvocation.MyCommand.Path }
    else { $Folder = (Get-Location).Path }   # code pasted into a console: use the current folder
}
$target = Join-Path $Folder $Subfolder

# Files only (not folders), extension .tif or .tiff in any letter case.
$tiffs = @(Get-ChildItem -LiteralPath $Folder | Where-Object {
    -not $_.PSIsContainer -and $_.Extension -match '^\.tiff?$'
})

if ($tiffs.Count -eq 0) {
    Write-Host "No TIFF files found in $Folder"
}
else {
    if (-not (Test-Path -LiteralPath $target)) {
        New-Item -ItemType Directory -Path $target | Out-Null
    }

    $moved = 0; $skipped = 0; $failed = 0
    foreach ($f in $tiffs) {
        $dest = Join-Path $target $f.Name
        if (Test-Path -LiteralPath $dest) {
            Write-Warning "Skipped, already in ${Subfolder}: $($f.Name)"
            $skipped++
            continue
        }
        try {
            Move-Item -LiteralPath $f.FullName -Destination $dest -ErrorAction Stop
            $moved++
        }
        catch {
            # Usually the file is open in another program (Fiji, HCS Studio...).
            Write-Warning "Could not move $($f.Name): $($_.Exception.Message)"
            $failed++
        }
    }

    if ($WhatIfPreference) {
        Write-Host "Preview only: $($tiffs.Count) TIFF file(s) would be moved to $target"
    }
    else {
        Write-Host "Moved $moved file(s) to $target"
        if ($skipped) { Write-Host "Skipped $skipped (same name already in $Subfolder)" }
        if ($failed)  { Write-Host "Failed $failed (see warnings above)" }
    }
}

# Keeps the window open when started with right-click > Run with PowerShell. Delete this line if you don't need it.
if ($Host.Name -eq "ConsoleHost") { Read-Host "Press Enter to close" | Out-Null }
