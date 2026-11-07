# Size of each subfolder (GB), largest first
$root = "D:\Data"
Get-ChildItem -Path $root -Directory | ForEach-Object {
    $bytes = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{
        Folder = $_.Name
        SizeGB = [math]::Round($bytes / 1GB, 2)
    }
} | Sort-Object SizeGB -Descending | Format-Table -AutoSize