# ==============================================================================
# 04-Orchestration.ps1 - Lancement, enchainement, progression, UI
# ==============================================================================

$script:Runner = @{
    1 = { Invoke-Step1 }
    2 = { Invoke-Step2 }
    3 = { Invoke-Step3 }
    4 = { Invoke-Step4 }
    5 = { Invoke-Step5 }
    6 = { Invoke-Step6 }
}

# --- Lecture des réglages depuis la fenêtre Réglages (si ouverte) ----
function Save-Config {
    $c = $script:SetCtrls
    if (-not $c) { return }
    $script:Cfg.TerraRoot     = $c['terra'].Text.Trim()
    $script:Cfg.SetupExe      = $c['setup'].Text.Trim()
    $script:Cfg.PtcSource     = $c['ptc'].Text.Trim()
    $script:Cfg.PowerDraftExe = $c['pd'].Text.Trim()
    $script:Cfg.TscanDir      = $c['dest'].Text.Trim()
    $script:Cfg.Silent        = $c['silent'].Checked
    $script:Cfg.ComputerId    = $c['cid'].Text.Trim()
    if ($c['ver'].SelectedItem) { $script:Cfg.SetupVersion = [string]$c['ver'].SelectedItem }
}

# --- Exécution d'une étape ----------------------------------------------------
# Retourne 'ok' | 'err' | 'abort'
function Start-Step {
    param([int]$Index)

    $p = $script:Steps[$Index - 1]
    Set-Step $Index 'run' ''
    Set-Progress ((($Index - 1) / $script:StepCount) * 100) "Étape $Index/$($script:StepCount) : $($p.Title)…"
    Add-Log 'INFO' "Étape $Index – $($p.Title)"

    $ok = $false
    try {
        $ok = & $script:Runner[$Index]
    } catch {
        Add-Log 'ERR' "Exception étape ${Index} : $($_.Exception.Message)"
        $ok = $false
    }

    if ($script:Abort) {
        Set-Step $Index 'wait' ''
        return 'abort'
    }

    if ($ok) {
        Set-Step $Index 'ok' ''
        Add-Log 'OK' $p.Ok
        return 'ok'
    }

    Set-Step $Index 'err' $p.Er
    return 'err'
}

# --- Lancement de la procédure complète ---------------------------------------
function Invoke-AllSteps {
    if ($script:Running) { return }
    Save-Config

    if (-not $script:Cfg.TerraRoot -and $script:StepsState[2].s -ne 'ok') {
        if (-not (Show-TerraRootModal)) { return }
    }

    $script:Running = $true
    $script:Abort   = $false
    Update-UI

    if (-not (Test-Admin)) {
        Add-Log 'WARN' 'Droits administrateur absents : l''installation peut échouer.'
    }

    for ($i = 1; $i -le $script:StepCount; $i++) {
        if ($script:StepsState[$i].s -eq 'ok') { continue }
        $r = Start-Step $i
        Update-UI

        if ($r -eq 'abort') {
            Add-Log 'WARN' 'Arrêté par l''utilisateur.'
            break
        }
        if ($r -eq 'err') { break }
    }

    $script:Running = $false
    Update-UI

    $allOk = $true
    for ($i = 1; $i -le $script:StepCount; $i++) {
        if ($script:StepsState[$i].s -ne 'ok') { $allOk = $false; break }
    }
    if ($allOk) { Show-Toast 'Installation terminée' }
}

# --- Réinitialisation ----------------------------------------------------------
function Reset-Steps {
    for ($i = 1; $i -le $script:StepCount; $i++) {
        $script:StepsState[$i] = @{ s = 'wait'; m = '' }
    }
    $script:LogLines = @()
    $script:LogPainted = 0
    $script:LogLines += @{ t = Get-Now; l = 'INFO'; m = 'Prêt. Ouvrez Réglages pour ajuster les chemins ou lancez.' }
    if ($script:LogRtB) {
        $script:LogRtB.Clear()
        $script:LogPainted = 0
        Paint-Log
    }
    $script:Cfg.ComputerId = ''
    Update-UI
    Show-Toast 'Procédure réinitialisée'
}

# --- Mise a jour de toute l'interface (équivalent du render() de la maquette) -
function Update-UI {
    $count = 0
    $nx = -1
    $firstErr = -1
    $anyErr = $false
    for ($i = 1; $i -le $script:StepCount; $i++) {
        $s = $script:StepsState[$i]
        if ($s.s -eq 'ok') { $count++ } else { if ($nx -lt 0) { $nx = $i } }
        if ($s.s -eq 'err') { $anyErr = $true; if ($firstErr -lt 0) { $firstErr = $i } }

        # --- Carte ---
        $row = $script:StepRows[$i]
        if ($row) {
            $bg = Get-Col $script:Hex.($($s.s) + 'Bg')
            $fg = Get-Col $script:Hex.($($s.s) + 'Ink')
            $row.row.BackColor = $bg
            $row.row.Height    = if ($s.m) { 66 } else { 56 }
            $row.badge.ForeColor = $fg
            $row.badge.Text = $script:StepLabels[$s.s]
            $row.detail.Text = if ($s.m) { $s.m } else { '' }
            $row.detail.ForeColor = $fg
            $row.icon.Invalidate()
        }
    }

    # --- Boutons ---
    if ($script:BtnMain) {
        $b = $script:BtnMain
        if ($script:Running) {
            $b.Text = 'En cours…'
            $b.Enabled = $false
        } elseif ($nx -eq -1) {
            $b.Text = '✓ Terminé'
            $b.Enabled = $false
        } elseif ($count -eq 0 -and -not $anyErr) {
            $b.Text = '▶ Lancer l''installation'
            $b.Enabled = $true
        } elseif ($anyErr) {
            $b.Text = "▶ Réessayer l'étape $nx"
            $b.Enabled = $true
        } else {
            $b.Text = "▶ Reprendre à l'étape $nx"
            $b.Enabled = $true
        }
    }

    if ($script:BtnStop)   { $script:BtnStop.Visible = $script:Running }
    if ($script:BtnReset)  { $script:BtnReset.Enabled  = -not $script:Running }
    if ($script:BtnSet)    { $script:BtnSet.Enabled    = -not $script:Running }

    # --- Barre de progression ---
    if ($script:FillBar -and $script:FillMax) {
        $w = [int](($count / $script:StepCount) * $script:FillMax)
        $script:FillBar.Width = $w
    }

    # --- Texte de statut ---
    if (-not $script:Running -and $script:BandStatusText) {
        if ($nx -eq -1) {
            $script:BandStatusText.Text = 'Installation terminée'
        } elseif ($anyErr) {
            $script:BandStatusText.Text = "Arrêté à l'étape $firstErr"
        } elseif ($count -gt 0) {
            $script:BandStatusText.Text = "$count étape(s) sur $($script:StepCount) terminée(s)"
        } else {
            $script:BandStatusText.Text = 'Prêt à démarrer'
        }
    }

    # --- Info : Computer ID + Copier ---
    if ($script:BandInfo) {
        $cid = $script:Cfg.ComputerId
        $hasCid = -not [string]::IsNullOrWhiteSpace($cid)
        $script:BandInfo.Visible = $hasCid
        if ($hasCid) {
            $script:BandInfoCid.Text = "Computer ID : $cid"
            $script:BandInfo.Visible = $true
            $script:BandInfo.Height = 36
        }
    }
}

# ==============================================================================
# Point d'entree unique
# ==============================================================================
function Start-Application {
    Load-Settings

    # --- Construction de la fenêtre principale ---
    Build-MainForm

    # --- Garde d'activation ---
    if (-not (Show-ActivationModal)) { exit 1 }

    # --- Fenêtre principale ---
    $script:Form.ShowDialog()
}