# =============================================================================
# Move-ExportToNetwork.ps1
# Deplace les exports locaux vers le lecteur reseau :
#   copie -> verification (taille + date) -> suppression de l'original
# Compatible PowerShell 2.0 (Windows 7 de base).
# =============================================================================

param(
    [switch]$DryRun    # Simulation : n'ecrit et ne supprime RIEN, affiche seulement ce qui serait fait
)

# ----------------------------- A MODIFIER -----------------------------------
$SourceDir     = "C:\Export"                    # Dossier d'export local
$DestDir       = "\\SERVEUR\Partage\Export"     # Destination reseau (prefere un chemin UNC a une lettre de lecteur)
$MinAgeMinutes = 2                              # Ne touche que les fichiers non modifies depuis N minutes
$LogDir        = "C:\Export_Logs"               # Dossier des journaux (hors du dossier d'export !)
# -----------------------------------------------------------------------------

$ErrorActionPreference = "Stop"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogFile  = Join-Path $LogDir ("transfer_{0}.log" -f (Get-Date -Format "yyyy-MM"))
$LockFile = Join-Path $LogDir "transfer.lock"

function Write-Log($msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

# --- Verrou : empeche deux executions simultanees (ex. tache planifiee + lancement manuel)
try {
    $lock = New-Object System.IO.FileStream($LockFile, 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
    Write-Log "Un transfert est deja en cours : arret."
    exit 0
}

try {
    if ($DryRun) { Write-Log "=== MODE SIMULATION (aucune modification) ===" }

    # --- Garde-fous : on ne supprime rien si source ou destination est inaccessible
    if (-not (Test-Path $SourceDir)) { Write-Log "ERREUR : source introuvable ($SourceDir)"; exit 1 }
    if (-not (Test-Path $DestDir))   { Write-Log "ERREUR : destination injoignable ($DestDir). Rien n'est supprime."; exit 1 }

    $SourceDir = $SourceDir.TrimEnd('\')
    $DestDir   = $DestDir.TrimEnd('\')
    $cutoff    = (Get-Date).AddMinutes(-$MinAgeMinutes)

    $files = @(Get-ChildItem -Path $SourceDir -Recurse -Force |
               Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoff })

    Write-Log ("{0} fichier(s) eligible(s) (anciennete > {1} min)" -f $files.Count, $MinAgeMinutes)

    $ok = 0; $fail = 0
    foreach ($f in $files) {
        $rel    = $f.FullName.Substring($SourceDir.Length).TrimStart('\')
        $target = Join-Path $DestDir $rel

        try {
            if ($DryRun) { Write-Log "[simulation] $rel"; continue }

            $targetFolder = Split-Path $target -Parent
            if (-not (Test-Path $targetFolder)) { New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null }

            # 1. Copie (Copy-Item conserve la date de modification)
            Copy-Item -LiteralPath $f.FullName -Destination $target -Force

            # 2. Verification : meme taille, meme date (tolerance 2 s pour les partages reseau)
            $t = Get-Item -LiteralPath $target
            $sameSize = ($t.Length -eq $f.Length)
            $sameDate = ([Math]::Abs(($t.LastWriteTime - $f.LastWriteTime).TotalSeconds) -le 2)
            if (-not ($sameSize -and $sameDate)) {
                throw "verification echouee (taille ou date differente)"
            }

            # 3. Suppression de l'original, seulement si tout est OK
            Remove-Item -LiteralPath $f.FullName -Force
            $ok++
        } catch {
            $fail++
            Write-Log "ECHEC : $rel -> $($_.Exception.Message) (original conserve)"
        }
    }

    # --- Nettoyage des sous-dossiers locaux devenus vides (jamais le dossier racine)
    if (-not $DryRun) {
        Get-ChildItem -Path $SourceDir -Recurse -Force |
            Where-Object { $_.PSIsContainer } |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object {
                if (@(Get-ChildItem -LiteralPath $_.FullName -Force).Count -eq 0) {
                    Remove-Item -LiteralPath $_.FullName -Force
                }
            }
    }

    Write-Log ("Termine : {0} transfere(s), {1} echec(s)" -f $ok, $fail)
    if ($fail -gt 0) { exit 2 }
}
finally {
    $lock.Close()
}
