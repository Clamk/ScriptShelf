# ---
# title: Folder sizes, largest first
# tags: disk space, files
# tested:
# notes: Lists each subfolder with its total size in GB, sorted largest first.
#   Handy before cleaning a data drive. Run it inside the folder to measure,
#   or pass one: .\folder_sizes.ps1 -Root <folder>
#   Needs PowerShell 3 or newer (Windows 7 ships with 2.0).
# ---
param([string]$Root = ".")

Get-ChildItem -Path $Root -Directory | ForEach-Object {
    $bytes = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{
        Folder = $_.Name
        SizeGB = [math]::Round($bytes / 1GB, 2)
    }
} | Sort-Object SizeGB -Descending | Format-Table -AutoSize
