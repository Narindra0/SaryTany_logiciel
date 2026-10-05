# ==================================================================
# src\20-Engine-Deployment.ps1  -  Moteur de deploiement Bentley
#   Copie du profil PowerDraft vers C:\IT_Config, le profil par defaut
#   et chaque profil utilisateur, puis deploiement automatique a chaque
#   ouverture de session (entree RunOnce machine auto-reparatrice).
#   Moteur testable : aucune dependance a l'interface graphique.
# Depend de : $SourceConfig, $ItStSource, $DefaultPath, $UsersRoot (parametres)
# ==================================================================
# Etat partage avec l'interface : mis a true par le bouton "Annuler".
$script:CancelRequested = $false

function Copy-Tree {
    param([string]$From, [string]$To)
    if (-not (Test-Path -LiteralPath $From)) { throw "Source introuvable : $From" }
    if (-not (Test-Path -LiteralPath $To)) { New-Item -ItemType Directory -Force -Path $To | Out-Null }
    $roboArgs = @($From, $To, '/E', '/IS', '/IT', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/XJ')
    $out = & robocopy.exe @roboArgs 2>&1
    $code = $LASTEXITCODE
    if ($code -ge 8) { throw "Robocopy a echoue (code $code) pour $From -> $To :: $($out -join ' | ')" }
    return $code
}

function Get-DeployTargets {
    param([string]$Root = 'C:\Users')
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    $exclude = @('Public', 'Default', 'All Users', 'Default User', 'Desktop.ini')
    @(Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { ($exclude -notcontains $_.Name) -and (-not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)) } |
        ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Path = Join-Path $_.FullName 'AppData\Local\Bentley\PowerDraft'
            }
        })
}

function Invoke-BentleyDeployment {
    param([scriptblock]$OnProgress, [scriptblock]$Log)

    $say = {
        param($m, $l = 'INFO')
        if ($Log) { & $Log $m $l } else { Write-Out ("[{0}] {1}" -f $l, $m) $l }
    }.GetNewClosure()
    $upd = {
        param($p, $s)
        if ($OnProgress) { & $OnProgress $p $s }
    }.GetNewClosure()

    # --- Etape 1 : source de reference ---
    & $upd 5 "Preparation de la source de reference..."
    if (Test-Path -LiteralPath $ItStSource) {
        & $say "Profil 'it_st' detecte : $ItStSource" 'OK'
        Copy-Tree -From $ItStSource -To $SourceConfig | Out-Null
        & $say "Reference synchronisee dans : $SourceConfig" 'OK'
    }
    elseif (Test-Path -LiteralPath $SourceConfig) {
        & $say "Reference existante utilisee : $SourceConfig" 'INFO'
    }
    else {
        & $say "Aucun profil PowerDraft de reference trouve (ni it_st ni IT_Config)." 'ERREUR'
        throw "Source de reference introuvable."
    }
    $fileCount = @(Get-ChildItem -LiteralPath $SourceConfig -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    & $say "Source de reference validee ($fileCount fichiers)." 'OK'

    # --- Etape 2 : profil par defaut ---
    if ($script:CancelRequested) { throw "Operation annulee par l'utilisateur." }
    & $upd 35 "Mise a jour du profil par defaut..."
    Copy-Tree -From $SourceConfig -To $DefaultPath | Out-Null
    & $say "Profil par defaut (Default) mis a jour : $DefaultPath" 'OK'

    # --- Etape 3 : profils utilisateurs existants ---
    & $upd 50 "Propagation aux profils utilisateurs existants..."
    $targets = @(Get-DeployTargets -Root $UsersRoot)
    if ($targets.Count -eq 0) { & $say "Aucun profil utilisateur detecte dans $UsersRoot (etape 3 sans objet)." 'ATTENTION' }
    $done = 0
    $failed = @()
    $i = 0
    foreach ($t in $targets) {
        if ($script:CancelRequested) { throw "Operation annulee par l'utilisateur." }
        $i++
        & $upd (50 + [int](40 * ($i / [Math]::Max(1, $targets.Count)))) ("Profil : {0}" -f $t.Name)
        try {
            Copy-Tree -From $SourceConfig -To $t.Path | Out-Null
            $done++
            $n = @(Get-ChildItem -LiteralPath $t.Path -Recurse -File -Force -ErrorAction SilentlyContinue).Count
            & $say ("Profil mis a jour : {0} ({1} fichiers)" -f $t.Name, $n) 'OK'
        }
        catch {
            $failed += $t.Name
            & $say ("ECHEC sur le profil {0} : {1}" -f $t.Name, $_.Exception.Message) 'ERREUR'
        }
    }

    & $upd 100 "Termine"
    return [pscustomobject]@{
        Success = ($failed.Count -eq 0)
        Updated = $done
        Failed  = $failed
        Targets = $targets.Count
        Files   = $fileCount
    }
}

# ============ DEPLOIEMENT AUTOMATIQUE A L'OUVERTURE DE SESSION ============
# NOTE : l'onglet "Scripts PowerShell" de gpedit.msc ecrit un fichier cache
# (C:\Windows\System32\grouppolicy\user\scripts\psscripts.ini) non documente et non
# scriptable de facon fiable. Mecanisme equivalent, supported et verifiable utilise ici :
# une entree RunOnce machine (HKLM) qui s'execute DANS le contexte de l'utilisateur qui
# ouvre sa session et qui se-re-enregistre a chaque execution (chaine auto-reparatrice).
$script:LogonScriptTemplate = @'
# Deploiement automatique du profil Bentley PowerDraft - genere par l'assistant Sarytany.
# Execute a chaque ouverture de session, dans le contexte de l'utilisateur connecte.
$Source      = '__SOURCE__'
$Destination = Join-Path $env:LOCALAPPDATA 'Bentley\PowerDraft'
if (Test-Path -LiteralPath $Source) {
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        & robocopy.exe $Source $Destination /E /IS /IT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XJ | Out-Null
        if ($LASTEXITCODE -lt 8) { Write-Out "Configuration PowerDraft deployee pour $env:USERNAME." }
    } else {
        Write-Out "Configuration Bentley deja presente pour $env:USERNAME."
    }
}
'@

$script:LogonCmdTemplate = @'
@echo off
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v __VALUENAME__ /t REG_SZ /d "__CMD__" /f >nul 2>&1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "__PS1__"
exit /b 0
'@

function Get-RegValue {
    param([string]$Path, [string]$Name)
    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
    $prop = $item.PSObject.Properties[$Name]
    if ($null -eq $prop) { throw "La valeur '$Name' est absente de $Path" }
    return $prop.Value
}

function Install-AutoDeploy {
    param(
        [string]$LogonDir   = 'C:\IT_Config',
        [string]$RunOnceKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        [string]$ValueName  = 'BentleyPowerDraftConfig',
        [string]$SourcePath = $SourceConfig,
        [scriptblock]$Log
    )
    $say = {
        param($m, $l = 'INFO')
        if ($Log) { & $Log $m $l } else { Write-Out ("[{0}] {1}" -f $l, $m) $l }
    }.GetNewClosure()

    if (-not (Test-Path -LiteralPath $LogonDir)) { New-Item -ItemType Directory -Force -Path $LogonDir | Out-Null }
    $ps1Path = Join-Path $LogonDir 'Deploy-Bentley.ps1'

    ($script:LogonScriptTemplate -replace '__SOURCE__', $SourcePath) | Set-Content -LiteralPath $ps1Path -Encoding UTF8
    if (-not (Test-Path -LiteralPath $ps1Path)) { throw "Ecriture impossible : $ps1Path" }
    & $say "Script de logon ecrit : $ps1Path" 'OK'

    $cmdPath = Join-Path $LogonDir 'Deploy-Bentley.cmd'
    $cmdBody = ($script:LogonCmdTemplate -replace '__VALUENAME__', $ValueName) `
                   -replace '__CMD__', $cmdPath -replace '__PS1__', $ps1Path
    Set-Content -LiteralPath $cmdPath -Value $cmdBody -Encoding ASCII
    if (-not (Test-Path -LiteralPath $cmdPath)) { throw "Ecriture impossible : $cmdPath" }
    & $say "Wrapper ecrit : $cmdPath" 'OK'

    if (-not (Test-Path -LiteralPath $RunOnceKey)) { New-Item -Path $RunOnceKey -Force | Out-Null }
    New-ItemProperty -Path $RunOnceKey -Name $ValueName -Value ('"' + $cmdPath + '"') -PropertyType String -Force | Out-Null
    & $say "Entree RunOnce ecrite : $RunOnceKey\$ValueName" 'OK'

    $readBack = Get-RegValue -Path $RunOnceKey -Name $ValueName
    if ("$readBack" -notlike "*$cmdPath*") { throw "RunOnce ne pointe pas vers le bon wrapper : $readBack" }
    if (-not (Test-Path -LiteralPath $cmdPath)) { throw "Wrapper enregistre introuvable : $cmdPath" }
    & $say "Verification OK - RunOnce pointe vers : $readBack" 'OK'

    return [pscustomobject]@{
        Success    = $true
        ScriptPath = $ps1Path
        CmdPath    = $cmdPath
        RunOnceKey = "$RunOnceKey\$ValueName"
    }
}
