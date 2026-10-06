# ==============================================================================
# 03-Steps.ps1 - Implementation des 6 etapes
#   Chaque fonction LOG son travail puis retourne $true / $false.
#   L'etat de la carte (wait/run/ok/err) est gere par Start-Step (04).
# ==============================================================================

function Start-StepLog {
    param([int]$Index)
    foreach ($ln in $script:Steps[$Index].Lines) { Add-Log 'INFO' $ln }
}

# --- Etape 1 : Securite & antivirus -------------------------------------------
function Invoke-Step1 {
    Start-StepLog 1
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $rt = if ($mp.RealTimeProtectionEnabled) { 'activée' } else { 'désactivée' }
        Add-Log 'INFO' "Protection temps réel : $rt"

        if ($mp.RealTimeProtectionEnabled) {
            Add-Log 'WARN' 'Protection active : ajoutez une exclusion dans Windows Security'
            Add-Log 'WARN' 'plutôt que de désactiver la protection.'
        }

        $q = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Quarantine'
        if (Test-Path $q) {
            $items = @(Get-ChildItem $q -Force -ErrorAction SilentlyContinue)
            Add-Log 'INFO' "Éléments en quarantaine : $($items.Count)"
            if ($items.Count -gt 0) { Add-Log 'WARN' 'Restaurer via Windows Security > historique.' }
        }

        if ($script:BtnSecurity -and -not $script:BtnSecurity.IsDisposed) {
            Add-Log 'INFO' 'Ouvrez Windows Security depuis les réglages pour ajouter une exclusion.'
        }
        return $true
    } catch {
        Add-Log 'WARN' "État Defender indisponible : $_"
        return $true
    }
}

# --- Etape 2 : localisation du dossier Terra ----------------------------------
function Invoke-Step2 {
    $root = "$($script:Cfg.TerraRoot)".Trim()

    if (-not $root -or -not (Test-Path $root)) {
        Add-Log 'ERR' "Dossier Terra introuvable : '$root'"
        return $false
    }
    Add-Log 'INFO' "Dossier principal : $root"

    Start-StepLog 2

    $eng = Join-Path $root 'eng'
    if (-not (Test-Path $eng)) {
        Add-Log 'INFO' 'Sous-dossier eng absent à la racine - recherche récursive...'
        $found = Get-ChildItem -Path $root -Directory -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -ieq 'eng' } | Select-Object -First 1
        if ($found) { $eng = $found.FullName }
    }

    if (-not (Test-Path $eng)) {
        Add-Log 'ERR' 'Aucun dossier eng trouvé.'
        return $false
    }

    $script:Cfg.EngPath  = $eng
    $script:Cfg.SetupExe = Join-Path $eng 'setup.exe'
    Add-Log 'INFO' "Dossier eng : $eng"

    $setup = $script:Cfg.SetupExe
    if (-not (Test-Path $setup)) {
        $hit = Get-ChildItem -Path $eng -Recurse -Depth 3 -Filter 'setup.exe' -File -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { $setup = $hit.FullName; $script:Cfg.SetupExe = $setup }
    }

    if (-not (Test-Path $setup)) {
        Add-Log 'ERR' 'setup.exe introuvable dans eng.'
        return $false
    }
    Add-Log 'OK' "setup.exe : $setup"

    $ptc = Join-Path $eng 'PTC_LAS.ptc'
    if (Test-Path $ptc) {
        $script:Cfg.PtcSource = $ptc
        Add-Log 'OK' "PTC_LAS.ptc : $ptc"
    } else {
        Add-Log 'WARN' 'PTC_LAS.ptc absent du dossier eng.'
    }

    Save-Settings | Out-Null
    return $true
}

# --- Etape 3 : initialisation de PowerDraft -----------------------------------
function Invoke-Step3 {
    $exe = $script:Cfg.PowerDraftExe

    if (-not (Test-Path $exe)) {
        Add-Log 'ERR' "PowerDraft.exe introuvable : $exe"
        return $false
    }

    Start-StepLog 3

    try {
        $p = Start-Process -FilePath $exe -PassThru
        Add-Log 'INFO' "Processus lancé (PID $($p.Id))"
        Start-Sleep -Seconds 8

        if (-not $p.HasExited) {
            $p.CloseMainWindow() | Out-Null
            Start-Sleep -Seconds 2
            if (-not $p.HasExited) { $p.Kill() }
        }
        Add-Log 'INFO' 'Fermeture de PowerDraft.'

        $target = Join-Path $env:LocalAppData 'Bentley\PowerDraft\10.0.0'
        for ($i = 0; $i -lt 12; $i++) {
            if ($script:Abort) { return $false }
            if (Test-Path $target) {
                Add-Log 'OK' "Arborescence générée : $target"
                return $true
            }
            Start-Sleep -Seconds 5
        }

        Add-Log 'ERR' 'Dossier 10.0.0 non détecté après initialisation.'
        return $false
    } catch {
        Add-Log 'ERR' "Échec du lancement : $_"
        return $false
    }
}

# --- Etape 4 : installation via setup.exe -------------------------------------
function Invoke-Step4 {
    $setup = $script:Cfg.SetupExe

    if (-not (Test-Path $setup)) {
        Add-Log 'ERR' "setup.exe introuvable : $setup"
        return $false
    }

    Add-Log 'WARN' "RÈGLE CRITIQUE : ne jamais cliquer sur Abort."
    Add-Log 'WARN' "Attendre le bouton Terminer ($($script:Cfg.SetupVersion))."

    Start-StepLog 4

    try {
        $argsList = @()
        if ($script:Cfg.Silent) { $argsList = '/quiet'; Add-Log 'WARN' 'Mode silencieux.' }

        $p = Start-Process -FilePath $setup -ArgumentList $argsList -PassThru
        Add-Log 'INFO' "Installeur démarré (PID $($p.Id))"

        if ($script:Cfg.Silent) {
            $p.WaitForExit()
            $p.Refresh()
        } else {
            $deadline = (Get-Date).AddMinutes(60)
            while (-not $p.HasExited) {
                if ($script:Abort) {
                    Add-Log 'WARN' 'Abandon demandé par l''utilisateur.'
                    return $false
                }
                if ((Get-Date) -gt $deadline) {
                    Add-Log 'ERR' 'Délai de 60 min dépassé - installeur toujours ouvert.'
                    return $false
                }
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 250
            }
        }

        $p.Refresh()
        Add-Log 'INFO' "Code de retour : $($p.ExitCode)"

        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
            if ($p.ExitCode -eq 3010) { Add-Log 'WARN' 'Redémarrage requis.' }
            return $true
        }

        if ($p.ExitCode -eq 1602) { Add-Log 'ERR' 'Code 1602 : annulation (Abort).' }
        return $false
    } catch {
        Add-Log 'ERR' "Échec de l'installation : $_"
        return $false
    }
}

# --- Etape 5 : collecte systeme -----------------------------------------------
function Invoke-Step5 {
    $cname = $env:COMPUTERNAME
    Add-Log 'INFO' "Nom de l'ordinateur : $cname"

    Start-StepLog 5

    $cid = "$($script:Cfg.ComputerId)".Trim()
    if (-not $cid) {
        Add-Log 'ERR' 'Computer ID non renseigné.'
        return $false
    }

    Add-Log 'OK' "Computer ID : $cid"

    if (Test-Path $script:Cfg.PowerDraftExe) {
        try {
            Start-Process -FilePath $script:Cfg.PowerDraftExe | Out-Null
            Add-Log 'INFO' 'PowerDraft relancé pour vérification.'
        } catch {
            Add-Log 'WARN' "Relance impossible : $_"
        }
    }

    Save-Settings | Out-Null
    return $true
}

# --- Etape 6 : configuration finale ------------------------------------------
function Invoke-Step6 {
    $src = $script:Cfg.PtcSource
    $dst = Join-Path $script:Cfg.TscanDir 'PTC_LAS.ptc'

    Start-StepLog 6

    if (-not (Test-Path $src)) {
        Add-Log 'ERR' "PTC_LAS.ptc introuvable : $src"
        return $false
    }

    try {
        if (-not (Test-Path $script:Cfg.TscanDir)) {
            New-Item -ItemType Directory -Path $script:Cfg.TscanDir -Force | Out-Null
            Add-Log 'INFO' "Dossier créé : $($script:Cfg.TscanDir)"
        }
        Copy-Item -Path $src -Destination $dst -Force
        Add-Log 'OK' "Fichier copié : $dst"

        if (Test-Path $dst) {
            $sz = (Get-Item $dst).Length
            Add-Log 'INFO' ("Taille : {0:N0} octets" -f $sz)
        }

        if (Test-Path $script:Cfg.PowerDraftExe) {
            Add-Log 'INFO' 'Lancement de PowerDraft pour le premier chargement du PTC.'
            Start-Process -FilePath $script:Cfg.PowerDraftExe | Out-Null
        }

        Save-Settings | Out-Null
        return $true
    } catch {
        Add-Log 'ERR' "Échec de la configuration : $_"
        return $false
    }
}