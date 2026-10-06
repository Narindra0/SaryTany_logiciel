# ==================================================================
# src\24-Engine-Terra.ps1  -  Moteur "Installation Terra"
#   Portage du projet "Installation Terra" (PowerDraft + modules
#   TerraMatch / TerraModeler / TerraScan) dans l'assistant :
#   6 etapes enchainees, arret a la premiere echec, annulation
#   possible, persistance des reglages dans le MEME fichier que
#   PowerDraft-Setup.exe (%LOCALAPPDATA%\PowerDraftSetup\settings.json)
#   pour garder la continuite des valeurs saisies.
# Contrats : Invoke-TerraInstall -Log {msg, level} -OnProgress {pct, status, idx}
#           $script:TerraCancelRequested  (drapeau d'arret demande par la vue)
#           Load-TerraSettings / Save-TerraSettings / $script:TerraCfg
# Niveaux de log : INFO | OK | ATTENTION | ERREUR
# ==================================================================

# --- Etat d'annulation (la vue 73 le remet a false a chaque lancement) ---
$script:TerraCancelRequested = $false

# --- Reglages persistants (interop PowerDraft-Setup.exe) ---
$script:TerraAppDataDir   = Join-Path $env:LOCALAPPDATA 'PowerDraftSetup'
$script:TerraSettingsFile = Join-Path $script:TerraAppDataDir 'settings.json'

$script:TerraCfg = [ordered]@{
    TerraRoot     = ''                                # Dossier principal Terra (contient eng\)
    SetupExe      = ''                                # eng\setup.exe (determine par l'etape 2)
    SetupVersion  = 'PowerDraft CE'                   # Version a installer
    PtcSource     = ''                                # eng\PTC_LAS.ptc
    TscanDir      = 'C:\terra64\tscan'                # Dossier cible TerraScan
    PowerDraftExe = 'C:\Program Files\Bentley\PowerDraft\PowerDraft.exe'
    Silent        = $false
    ComputerId    = ''
}
$script:TerraVersionChoices = @('PowerDraft CE', 'MicroStation CE')

# --- Libelles des 6 etapes (statut + journal) ---
$script:TerraSteps = @(
    @{ Title = 'Securite & antivirus'
       Ok   = 'Protection verifiee'
       Er   = 'Windows Security indisponible.' },
    @{ Title = 'Dossier Terra'
       Ok   = 'setup.exe localise'
       Er   = 'setup.exe introuvable. Verifiez le dossier dans les reglages.' },
    @{ Title = 'Initialisation PowerDraft'
       Ok   = 'Dossier 10.0.0 cree'
       Er   = 'PowerDraft ne demarre pas. Verifiez son chemin dans les reglages.' },
    @{ Title = 'Installation'
       Ok   = 'Installation terminee'
       Er   = 'L''installeur s''est arrete trop tot. Fermez-le puis relancez (ne jamais cliquer Abort).' },
    @{ Title = 'Collecte systeme'
       Ok   = 'Informations recuperees'
       Er   = 'Computer ID illegible ou vide. Ouvrez Terra (Tools > About) puis renseignez-le.' },
    @{ Title = 'Configuration finale'
       Ok   = 'Configuration validee'
       Er   = 'Dossier cible protege en ecriture. Relancez en administrateur.' }
)

# ==================== PERSISTANCE ====================
function Save-TerraSettings {
    try {
        if (-not (Test-Path $script:TerraAppDataDir)) {
            New-Item -ItemType Directory -Path $script:TerraAppDataDir -Force | Out-Null
        }
        $script:TerraCfg | ConvertTo-Json | Set-Content -Path $script:TerraSettingsFile -Encoding UTF8
        return $true
    } catch { return $false }
}

function Load-TerraSettings {
    if (-not (Test-Path $script:TerraSettingsFile)) { return }
    try {
        $json = Get-Content -Path $script:TerraSettingsFile -Raw -Encoding UTF8
        if (-not $json) { return }
        $data = $json | ConvertFrom-Json
        foreach ($k in @($data.PSObject.Properties.Name)) {
            if ($script:TerraCfg.Contains($k)) { $script:TerraCfg[$k] = $data.$k }
        }
    } catch {
        Write-Verbose "Reglages Terra illisibles : $script:TerraSettingsFile"
    }
}

# ==================== ETAPES ====================
# Chaque fonction journalise via $say (msg, niveau) et retourne $true / $false.

function Invoke-TerraStep1 {
    param([scriptblock]$say)
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $rt = if ($mp.RealTimeProtectionEnabled) { 'activee' } else { 'desactivee' }
        & $say "Protection temps reel : $rt" 'INFO'
        if ($mp.RealTimeProtectionEnabled) {
            & $say 'Protection active : ajoutez une exclusion sous Windows Security plutot que de la desactiver.' 'ATTENTION'
        }
        $q = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Quarantine'
        if (Test-Path $q) {
            $items = @(Get-ChildItem $q -Force -ErrorAction SilentlyContinue)
            & $say ("Elements en quarantaine : {0}" -f $items.Count) 'INFO'
            if ($items.Count -gt 0) { & $say 'Restaurer les fichiers via Windows Security > historique.' 'ATTENTION' }
        }
        return $true
    } catch {
        & $say "Etat Defender indisponible : $($_.Exception.Message)" 'ATTENTION'
        return $true
    }
}

function Invoke-TerraStep2 {
    param([scriptblock]$say)
    $root = "$($script:TerraCfg.TerraRoot)".Trim()
    if (-not $root -or -not (Test-Path -LiteralPath $root)) {
        & $say "Dossier Terra introuvable : '$root'" 'ERREUR'
        return $false
    }
    & $say "Dossier principal : $root" 'INFO'

    $eng = Join-Path $root 'eng'
    if (-not (Test-Path -LiteralPath $eng)) {
        & $say 'Sous-dossier eng absent a la racine - recherche recursive...' 'INFO'
        $found = Get-ChildItem -LiteralPath $root -Directory -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -ieq 'eng' } | Select-Object -First 1
        if ($found) { $eng = $found.FullName }
    }
    if (-not (Test-Path -LiteralPath $eng)) {
        & $say 'Aucun dossier eng trouve.' 'ERREUR'
        return $false
    }

    $setup = Join-Path $eng 'setup.exe'
    if (-not (Test-Path -LiteralPath $setup)) {
        $hit = Get-ChildItem -LiteralPath $eng -Recurse -Depth 3 -Filter 'setup.exe' -File -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { $setup = $hit.FullName }
    }
    if (-not (Test-Path -LiteralPath $setup)) {
        & $say "setup.exe introuvable dans eng ($eng)." 'ERREUR'
        return $false
    }
    & $say "Dossier eng : $eng" 'INFO'
    & $say "setup.exe : $setup" 'OK'

    $ptc = Join-Path $eng 'PTC_LAS.ptc'
    if (Test-Path -LiteralPath $ptc) {
        & $say "PTC_LAS.ptc : $ptc" 'OK'
    } else {
        & $say 'PTC_LAS.ptc absent du dossier eng (l''etape 6 echouera).' 'ATTENTION'
    }

    $script:TerraCfg.SetupExe  = $setup
    $script:TerraCfg.PtcSource = $ptc
    Save-TerraSettings | Out-Null
    return $true
}

function Invoke-TerraStep3 {
    param([scriptblock]$say)
    $exe = "$($script:TerraCfg.PowerDraftExe)".Trim()
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
        & $say "PowerDraft.exe introuvable : $exe" 'ERREUR'
        return $false
    }
    try {
        & $say 'Lancement de PowerDraft pour initialiser les dossiers...' 'INFO'
        $p = Start-Process -FilePath $exe -PassThru
        & $say "Processus lance (PID $($p.Id))" 'INFO'
        Start-Sleep -Seconds 8
        [System.Windows.Forms.Application]::DoEvents()
        if (-not $p.HasExited) {
            $p.CloseMainWindow() | Out-Null
            Start-Sleep -Seconds 2
            if (-not $p.HasExited) { $p.Kill() }
        }
        & $say 'Fermeture de PowerDraft.' 'INFO'

        $target = Join-Path $env:LocalAppData 'Bentley\PowerDraft\10.0.0'
        for ($i = 0; $i -lt 12; $i++) {
            if ($script:TerraCancelRequested) { return $false }
            if (Test-Path -LiteralPath $target) {
                & $say "Arborescence generee : $target" 'OK'
                return $true
            }
            Start-Sleep -Seconds 5
            [System.Windows.Forms.Application]::DoEvents()
        }
        & $say 'Dossier 10.0.0 non detecte apres initialisation.' 'ERREUR'
        return $false
    } catch {
        & $say "Echec du lancement : $($_.Exception.Message)" 'ERREUR'
        return $false
    }
}

function Invoke-TerraStep4 {
    param([scriptblock]$say)
    $setup = "$($script:TerraCfg.SetupExe)".Trim()
    if (-not $setup -or -not (Test-Path -LiteralPath $setup)) {
        & $say "setup.exe introuvable : '$setup' (lancez d'abord l'etape 2 via le dossier Terra)." 'ERREUR'
        return $false
    }
    & $say "REGLE CRITIQUE : ne jamais cliquer sur Abort." 'ATTENTION'
    & $say "Attendre le bouton Terminer ($($script:TerraCfg.SetupVersion))." 'ATTENTION'
    try {
        $argsList = @()
        if ($script:TerraCfg.Silent) { $argsList = '/quiet'; & $say 'Mode silencieux : la selection de version est ignoree.' 'ATTENTION' }

        & $say "Ouverture de l'installeur : $setup" 'INFO'
        $p = Start-Process -FilePath $setup -ArgumentList $argsList -PassThru
        & $say "Installeur demarre (PID $($p.Id))" 'INFO'

        if ($script:TerraCfg.Silent) {
            $p.WaitForExit()
        } else {
            $deadline = (Get-Date).AddMinutes(60)
            while (-not $p.HasExited) {
                if ($script:TerraCancelRequested) {
                    & $say 'Abandon demande par l''utilisateur (installeur laisse ouvert).' 'ATTENTION'
                    return $false
                }
                if ((Get-Date) -gt $deadline) {
                    & $say 'Delai de 60 min depasse - installeur toujours ouvert.' 'ERREUR'
                    return $false
                }
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 250
            }
        }
        $p.Refresh()
        & $say "Code de retour : $($p.ExitCode)" 'INFO'
        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
            if ($p.ExitCode -eq 3010) { & $say 'Redemarrage requis.' 'ATTENTION' }
            return $true
        }
        if ($p.ExitCode -eq 1602) { & $say 'Code 1602 : annulation (Abort) detectee.' 'ERREUR' }
        return $false
    } catch {
        & $say "Echec de l'installation : $($_.Exception.Message)" 'ERREUR'
        return $false
    }
}

function Invoke-TerraStep5 {
    param([scriptblock]$say)
    $cname = $env:COMPUTERNAME
    & $say "Nom de l'ordinateur : $cname" 'INFO'
    $cid = "$($script:TerraCfg.ComputerId)".Trim()
    if (-not $cid) {
        & $say 'Computer ID non renseigne (Tools > About > Copy for email, puis Reglages Terra).' 'ERREUR'
        return $false
    }
    & $say "Computer ID : $cid" 'OK'
    $exe = "$($script:TerraCfg.PowerDraftExe)".Trim()
    if ($exe -and (Test-Path -LiteralPath $exe)) {
        try {
            Start-Process -FilePath $exe | Out-Null
            & $say 'PowerDraft relance pour verification.' 'INFO'
        } catch {
            & $say "Relance impossible : $($_.Exception.Message)" 'ATTENTION'
        }
    }
    Save-TerraSettings | Out-Null
    return $true
}

function Invoke-TerraStep6 {
    param([scriptblock]$say)
    $src = "$($script:TerraCfg.PtcSource)".Trim()
    $dst = Join-Path "$($script:TerraCfg.TscanDir)".Trim() 'PTC_LAS.ptc'
    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
        & $say "PTC_LAS.ptc introuvable : '$src'" 'ERREUR'
        return $false
    }
    try {
        if (-not (Test-Path -LiteralPath $script:TerraCfg.TscanDir)) {
            New-Item -ItemType Directory -Path $script:TerraCfg.TscanDir -Force | Out-Null
            & $say "Dossier cree : $($script:TerraCfg.TscanDir)" 'INFO'
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        & $say "Fichier copie : $dst" 'OK'
        if (Test-Path -LiteralPath $dst) {
            $sz = (Get-Item -LiteralPath $dst).Length
            & $say ("Taille : {0:N0} octets" -f $sz) 'INFO'
        }
        $exe = "$($script:TerraCfg.PowerDraftExe)".Trim()
        if ($exe -and (Test-Path -LiteralPath $exe)) {
            & $say 'Lancement de PowerDraft pour le premier chargement du PTC.' 'INFO'
            Start-Process -FilePath $exe | Out-Null
        }
        Save-TerraSettings | Out-Null
        return $true
    } catch {
        & $say "Echec de la configuration : $($_.Exception.Message)" 'ERREUR'
        return $false
    }
}

# ==================== ORCHESTRATION ====================
function Invoke-TerraInstall {
    <#
        Enchaine les 6 etapes Terra. S'arrete au premier echec ou a
        l'annulation. Retourne @{ Completed; Failed; Aborted; ComputerId }.
        -OnProgress est appele avec (pct, status, idx) ; idx = ligne 0-based.
    #>
    param(
        [scriptblock]$OnProgress,
        [scriptblock]$Log
    )

    $say = {
        param($m, $l = 'INFO')
        if ($Log) { & $Log $m $l }
    }.GetNewClosure()
    $upd = {
        param($p, $s, $i)
        if ($OnProgress) { & $OnProgress $p $s $i }
    }.GetNewClosure()

    $runners = @(
        { param($s) Invoke-TerraStep1 $s },
        { param($s) Invoke-TerraStep2 $s },
        { param($s) Invoke-TerraStep3 $s },
        { param($s) Invoke-TerraStep4 $s },
        { param($s) Invoke-TerraStep5 $s },
        { param($s) Invoke-TerraStep6 $s }
    )

    $result = @{ Completed = $false; Failed = 0; Aborted = $false; ComputerId = '' }

    for ($i = 0; $i -lt 6; $i++) {
        if ($script:TerraCancelRequested) {
            $result.Aborted = $true
            & $say 'Operation annulee avant l''etape.' 'ATTENTION'
            return $result
        }
        $step = $script:TerraSteps[$i]
        & $upd ([int](($i / 6) * 100)) ("Etape {0}/6 : {1}" -f ($i + 1), $step.Title) $i

        $ok = $false
        try {
            $ok = & $runners[$i] $say
        } catch {
            & $say "Exception etape $($i + 1) : $($_.Exception.Message)" 'ERREUR'
            $ok = $false
        }

        if ($script:TerraCancelRequested) {
            $result.Aborted = $true
            & $say 'Operation interrompue par l''utilisateur.' 'ATTENTION'
            return $result
        }
        if (-not $ok) {
            $result.Failed = $i + 1
            & $say $step.Er 'ERREUR'
            return $result
        }

        & $say ("[{0}/6] {1}" -f ($i + 1), $step.Ok) 'OK'
        & $upd ([int]( (($i + 1) / 6) * 100 )) ("Etape {0}/6 terminee" -f ($i + 1)) $i
    }

    $result.Completed  = $true
    $result.ComputerId = "$($script:TerraCfg.ComputerId)".Trim()
    return $result
}
