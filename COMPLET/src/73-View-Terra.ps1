# ==================================================================
# src\73-View-Terra.ps1  -  Vue "Installation Terra" (gabarit run)
#   Installation / configuration de Bentley PowerDraft avec les
#   modules TerraMatch, TerraModeler et TerraScan : 6 etapes via le
#   gabarit run (carte statut + liste + journal + barre d'actions).
#   Bouton vert "Reglages Terra" : modale de configuration (dossier
#   Terra, version, chemins, mode silencieux, Computer ID), persistee
#   dans %LOCALAPPDATA%\PowerDraftSetup\settings.json (fichier commun
#   avec PowerDraft-Setup.exe). Acces regi par la licence de l'assistant.
# Depend de : src\50-Widgets.ps1 (New-RunView), src\60-Shell.ps1,
#             src\24-Engine-Terra.ps1 (Invoke-TerraInstall).
# ==================================================================

# --- Chargement des reglages persistants avant construction de la vue ---
Load-TerraSettings
if ($TerraSourceDir) { $script:TerraCfg.TerraRoot = $TerraSourceDir }

# --- Gabarit run : les 6 etapes du moteur ---
$terraView = New-RunView -ReadyText "Ouvrez 'Reglages Terra' pour indiquer le dossier source, puis lancez." -Steps @(
    @('Securite & antivirus',      'Windows Defender + quarantaine'),
    @('Dossier Terra',             'Recherche eng + setup.exe'),
    @('Initialisation PowerDraft', 'Premier lancement, dossier 10.0.0'),
    @('Installation',              'setup.exe - ne jamais cliquer Abort'),
    @('Collecte systeme',          'Nom du poste + Computer ID'),
    @('Configuration finale',      'PTC_LAS.ptc -> C:\terra64\tscan')
) -GoText "Demarrer l'installation Terra" -ExtraText 'Reglages Terra' -ShowResume $false
Add-ViewPanel -Key 'Terra' -Panel $terraView.Panel

# Aliases utilises par 90-App (garde de fermeture, AutoTest, journaux).
$terraStatus     = $terraView.Status
$textBoxTerraLog = $terraView.Log
$btnTerraStart   = $terraView.BtnGo
$btnTerraCfg     = $terraView.BtnExtra
$btnTerraCancel  = $terraView.BtnCancel

# --- Pilotage des lignes d'etape selon la progression ---
function Set-TerraRows {
    param([int]$Active, [string]$ActiveText = 'EN COURS')
    for ($i = 0; $i -lt 6; $i++) {
        $st = if ($i -lt $Active) { 'OK' } elseif ($i -eq $Active) { $ActiveText } else { 'EN ATTENTE' }
        Set-RunRow $terraView $i $st
    }
}

# --- Journal et etat de la vue ---
function Write-TerraLog {
    param([string]$Message, [string]$Level = 'INFO')
    Write-UiLog -Box $textBoxTerraLog -Message $Message -Level $Level
    Set-Status $Message
}

function Set-TerraState {
    param([bool]$Running, [string]$Status, [string]$Detail = '', [int]$Percent = -1,
          [string]$PillText = 'EN ATTENTE', [System.Drawing.Color]$PillColor = $script:C_Muted,
          [string]$BarColor = 'Accent')
    Set-UiStatus -Ctl $terraStatus -Running $Running -Status $Status -Detail $Detail -Percent $Percent `
                 -PillText $PillText -PillColor $PillColor -BarColor $BarColor `
                 -EnableWhenIdle @($btnTerraStart; $btnTerraCfg) -EnableWhenBusy @($btnTerraCancel)
}

function Get-TerraRootInfo {
    $root = "$($script:TerraCfg.TerraRoot)".Trim()
    if ($root -and (Test-Path -LiteralPath $root)) { return $root }
    return ''
}

# ================= MODALE : REGLAGES TERRA =================
# Les gestionnaires d'evenements WinForms ne voient que la portee
# $script: : la fenetre et ses controles y sont donc publies.
function Show-TerraSettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Reglages Terra'
    $dlg.ClientSize = New-Object System.Drawing.Size(560, 430)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.BackColor = $script:C_Bg
    $dlg.Font = $script:FontUI
    $appIcon = Get-AppIcon
    if ($appIcon) { $dlg.Icon = $appIcon; $dlg.ShowIcon = $true }
    $script:TerraCfgDlg = $dlg

    $fields = [ordered]@{
        terra = @{ Label = 'Dossier principal Terra (contient eng\)'; Cfg = 'TerraRoot';     Y = 16 }
        ver   = @{ Label = 'Version a installer';                    Cfg = 'SetupVersion';  Y = 78 }
        dest  = @{ Label = 'Dossier cible TerraScan';                Cfg = 'TscanDir';      Y = 140 }
        pd    = @{ Label = 'PowerDraft.exe';                         Cfg = 'PowerDraftExe'; Y = 202 }
        cid   = @{ Label = 'Computer ID (Tools > About)';            Cfg = 'ComputerId';    Y = 264 }
    }
    $ctrls = @{}
    foreach ($k in @($fields.Keys)) {
        $f = $fields[$k]
        New-TextLabel -Text $f.Label -X 24 -Y $f.Y -W 500 -H 16 -Font $script:FontMini -Fore $script:C_Muted -Parent $dlg | Out-Null
        if ($k -eq 'ver') {
            $c = New-Object System.Windows.Forms.ComboBox
            $c.DropDownStyle = 'DropDownList'
            $c.Items.AddRange($script:TerraVersionChoices) | Out-Null
            if ($script:TerraVersionChoices -contains $script:TerraCfg.SetupVersion) { $c.SelectedItem = $script:TerraCfg.SetupVersion }
            else { $c.SelectedIndex = 0 }
        } else {
            $c = New-Object System.Windows.Forms.TextBox
            $c.Text = "$($script:TerraCfg.($f.Cfg))"
        }
        $c.Location = New-Object System.Drawing.Point(24, ($f.Y + 20))
        $c.Width = if ($k -eq 'terra') { 400 } else { 512 }
        $c.Height = 26
        $dlg.Controls.Add($c)
        $ctrls[$k] = $c
    }
    $script:TerraCfgCtrls = $ctrls

    # Bouton Parcourir pour le dossier Terra
    $btnBrowse = New-ModernButton -Text 'Parcourir...' -X 436 -Y 56 -W 100 -H 26 -Fill $script:C_Slate -Hover ([System.Drawing.Color]::FromArgb(120, 136, 160))
    $btnBrowse.Add_Click({
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog
        $fb.Description = 'Choisir le dossier principal Terra'
        $cur = "$($script:TerraCfg.TerraRoot)".Trim()
        if ($cur -and (Test-Path -LiteralPath $cur)) { $fb.SelectedPath = $cur }
        if ($fb.ShowDialog($script:TerraCfgDlg) -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:TerraCfgCtrls['terra'].Text = $fb.SelectedPath
        }
        $fb.Dispose()
    })
    $dlg.Controls.Add($btnBrowse)

    # Case mode silencieux
    $chkSilent = New-Object System.Windows.Forms.CheckBox
    $chkSilent.Text = 'Installation silencieuse (/quiet - la selection de version est ignoree)'
    $chkSilent.Location = New-Object System.Drawing.Point(24, 322)
    $chkSilent.AutoSize = $true
    $chkSilent.Checked = [bool]$script:TerraCfg.Silent
    $dlg.Controls.Add($chkSilent)
    $script:TerraCfgSilent = $chkSilent

    $btnOk = New-ModernButton -Text 'Enregistrer' -X 24 -Y 366 -W 250 -H 38
    $btnOk.Add_Click({ $script:TerraCfgDlg.DialogResult = [System.Windows.Forms.DialogResult]::OK; $script:TerraCfgDlg.Close() })
    $btnNo = New-GreyButton -Text 'Annuler' -X 292 -Y 366 -W 120 -H 38
    $btnNo.Add_Click({ $script:TerraCfgDlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $script:TerraCfgDlg.Close() })
    $dlg.Controls.Add($btnOk); $dlg.Controls.Add($btnNo)

    $res = $dlg.ShowDialog($form)
    if ($res -ne [System.Windows.Forms.DialogResult]::OK) {
        $dlg.Dispose(); $script:TerraCfgDlg = $null; $script:TerraCfgCtrls = $null
        return $false
    }

    $script:TerraCfg.TerraRoot     = $ctrls['terra'].Text.Trim()
    $script:TerraCfg.SetupVersion  = [string]$ctrls['ver'].SelectedItem
    $script:TerraCfg.TscanDir      = $ctrls['dest'].Text.Trim()
    $script:TerraCfg.PowerDraftExe = $ctrls['pd'].Text.Trim()
    $script:TerraCfg.ComputerId    = $ctrls['cid'].Text.Trim()
    $script:TerraCfg.Silent        = $chkSilent.Checked
    $ok = Save-TerraSettings
    $dlg.Dispose(); $script:TerraCfgDlg = $null; $script:TerraCfgCtrls = $null
    if (-not $ok) { Write-TerraLog 'Echec de sauvegarde des reglages (acces refuse).' 'ATTENTION' }
    return $true
}

$btnTerraCfg.Add_Click({
    $textBoxTerraLog.Clear()
    Write-TerraLog "Ouverture des reglages Terra..." 'INFO'
    if (Show-TerraSettingsDialog) {
        Write-TerraLog ("Reglages enregistres : {0}" -f $script:TerraSettingsFile) 'OK'
        $root = Get-TerraRootInfo
        if ($root) {
            Set-TerraState -Running $false -Status 'Pret' -Detail "Dossier Terra : $root" -Percent 0 -PillText 'PRET' -PillColor $script:C_Green
        } else {
            Set-TerraState -Running $false -Status 'Pret' -Detail "Dossier Terra non renseigne." -Percent 0 -PillText 'EN ATTENTE' -PillColor $script:C_Muted
        }
    }
})

# ================= ACTION : DEMARRAGE INSTALLATION TERRA =================
$btnTerraStart.Add_Click({
    $textBoxTerraLog.Clear()
    Reset-RunRows $terraView
    $script:TerraCancelRequested = $false

    # --- Dossier Terra requis (sinon on ouvre les reglages) ---
    $root = Get-TerraRootInfo
    if (-not $root) {
        Write-TerraLog "Dossier Terra non renseigne : ouverture des reglages." 'INFO'
        if ((Show-TerraSettingsDialog)) { $root = Get-TerraRootInfo }
    }
    if (-not $root) {
        Write-TerraLog 'Aucun dossier Terra valide : operation arretee.' 'ATTENTION'
        Set-TerraState -Running $false -Status 'Dossier manquant' -Detail "Renseignez le dossier principal Terra dans les reglages." -PillText 'ATTENTION' -PillColor $script:C_Amber -BarColor 'Amber'
        Show-Dialog "Aucun dossier Terra valide n'a ete fourni. Ouvrez 'Reglages Terra' et indiquez le dossier contenant eng\setup.exe." 'Source manquante' 'Warning'
        return
    }

    Set-TerraState -Running $true -Status 'En cours' -Detail "Initialisation..." -Percent 0 -PillText 'EN COURS' -PillColor $script:C_Accent
    Write-TerraLog '==============================================='
    Write-TerraLog "Demarrage de l'installation Terra (6 etapes) - version : $($script:TerraCfg.SetupVersion)"
    Write-TerraLog '==============================================='
    Set-TerraRows -Active 0

    # --- Callback de progression etape par etape ---
    $onProgress = {
        param($pct, $status, $idx)
        Set-TerraRows -Active ([int]$idx)
        Set-TerraState -Running $true -Status $status -Detail ("Progression : {0} %" -f $pct) -Percent $pct -PillText 'EN COURS' -PillColor $script:C_Accent
    }

    $logCb = { param($m, $l) Write-TerraLog $m $l }

    # Protections : desactivation automatique avant installation (best effort).
    Disable-PcInstallProtections -Simulate:($DryRun -or $AutoTest) -Log $logCb

    try {
        $result = Invoke-TerraInstall -Log $logCb -OnProgress $onProgress

        if ($result.Completed) {
            0..5 | ForEach-Object { Set-RunRow $terraView $_ 'OK' }
            Write-TerraLog '==============================================='
            Write-TerraLog ("Installation Terra terminee - Computer ID : {0}" -f $result.ComputerId) 'OK'
            Set-TerraState -Running $false -Status 'Terminee' -Detail "PowerDraft + modules Terra installes." -Percent 100 -PillText 'SUCCES' -PillColor $script:C_Green -BarColor 'Green'
            Show-Dialog "L'installation Terra (PowerDraft + modules) s'est deroulee correctement.`nComputer ID : $($result.ComputerId)" 'Installation Terra' 'Information'
        }
        elseif ($result.Aborted) {
            for ($i = 0; $i -lt 6; $i++) {
                if ($terraView.List.Items[$i].SubItems[2].Text -eq 'EN COURS') { Set-RunRow $terraView $i 'ARRET' }
            }
            Set-TerraState -Running $false -Status 'Interrompue' -Detail "Annulation demandee." -Percent -1 -PillText 'ARRET' -PillColor $script:C_Amber -BarColor 'Amber'
        }
        else {
            $idx = [int]$result.Failed - 1
            if ($idx -ge 0 -and $idx -lt 6) { Set-RunRow $terraView $idx 'ERREUR' }
            $msg = $script:TerraSteps[$idx].Er
            Write-TerraLog ("Echec a l'etape {0}/6." -f $result.Failed) 'ERREUR'
            Set-TerraState -Running $false -Status ("Echec - etape {0}/6" -f $result.Failed) -Detail $msg -PillText 'ERREUR' -PillColor $script:C_Red -BarColor 'Red'
            Show-Dialog $msg 'Installation Terra' 'Error'
        }
    }
    catch {
        for ($i = 0; $i -lt 6; $i++) {
            if ($terraView.List.Items[$i].SubItems[2].Text -eq 'EN COURS') { Set-RunRow $terraView $i 'ERREUR' }
        }
        Write-TerraLog "Erreur : $($_.Exception.Message)" 'ERREUR'
        Set-TerraState -Running $false -Status "Erreur durant l'installation" -Detail $_.Exception.Message -PillText 'ERREUR' -PillColor $script:C_Red -BarColor 'Red'
        Show-Dialog $_.Exception.Message 'Erreur Installation Terra' 'Error'
    }
})

$btnTerraCancel.Add_Click({
    $script:TerraCancelRequested = $true
    Write-TerraLog 'Annulation demandee...' 'ATTENTION'
    Set-TerraState -Running $true -Status 'Annulation en cours' -Detail "Interruption..." -Percent -1 -PillText 'ATTENTION' -PillColor $script:C_Amber -BarColor 'Amber'
})

# --- Initialisation ---
$rootInit = Get-TerraRootInfo
if ($rootInit) {
    Write-TerraLog "Vue Installation Terra prete. Dossier : $rootInit"
    Set-TerraState -Running $false -Status 'Pret' -Detail "Dossier Terra : $rootInit" -Percent 0 -PillText 'PRET' -PillColor $script:C_Green
} else {
    Write-TerraLog "Vue Installation Terra prete. Ouvrez 'Reglages Terra' pour indiquer le dossier source."
    Set-TerraState -Running $false -Status 'Pret' -Detail "Dossier Terra non renseigne." -Percent 0 -PillText 'EN ATTENTE' -PillColor $script:C_Muted
}
