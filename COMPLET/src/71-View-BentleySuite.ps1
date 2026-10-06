# ==================================================================
# src\71-View-BentleySuite.ps1  -  Vue "Installation Suite" (gabarit run)
#   Liste des 21 modules (ListView colonnes : module / type / statut),
#   carte statut, journal plein, actions Demarrer / Reprendre apres
#   modules manuels / Annuler. Source fournie par -SuiteSourceDir ou
#   demandee au lancement. Modules 13/14/15 = manuels.
# Depend de : src\50-Widgets.ps1 (New-RunView), src\60-Shell.ps1,
#             moteur 22 (Invoke-BentleySuiteInstall, $script:BentleyModules),
#             moteur 23 (Request-SintegraSourceDirectory partage).
# ==================================================================

# --- Gabarit run alimente par la table des modules du moteur ---
$modSteps = @(
    foreach ($mod in $script:BentleyModules) {
        ,@(
            ('Module {0:00}  {1}' -f $mod.Num, $mod.Name),
            ("{0}  -  {1}" -f $mod.Mode, $(if ($mod.Manual) { 'manuel' } else { 'automatique' })),
            [bool]$mod.Manual
        )
    }
)
$suiteView = New-RunView -ReadyText "Selectionnez le dossier source et lancez l'installation." -Steps $modSteps -GoText "Demarrer l'installation de la Suite" -ShowResume $true
Add-ViewPanel -Key 'Suite' -Panel $suiteView.Panel

# Aliases utilises par 90-App (garde de fermeture, AutoTest, journaux).
$suiteStatus    = $suiteView.Status
$textBoxSuiteLog = $suiteView.Log
$btnSuiteStart  = $suiteView.BtnGo
$btnSuiteResume = $suiteView.BtnResume
$btnSuiteCancel = $suiteView.BtnCancel

# Index de ligne par numero de module (les numeros ne sont pas continus).
$script:SuiteRowIdx = @{}
$i = 0
foreach ($mod in $script:BentleyModules) { $script:SuiteRowIdx[$mod.Num] = $i; $i++ }

function Set-SuiteRowNum {
    param([int]$Num, [string]$Status)
    $idx = $script:SuiteRowIdx[$Num]
    if ($null -ne $idx) { Set-RunRow $suiteView ([int]$idx) $Status }
}

# --- Journal et etat de la vue ---
function Write-SuiteLog {
    param([string]$Message, [string]$Level = 'INFO')
    Write-UiLog -Box $textBoxSuiteLog -Message $Message -Level $Level
    Set-Status $Message
}

function Set-SuiteState {
    param([bool]$Running, [string]$Status, [string]$Detail = '', [int]$Percent = -1,
          [string]$PillText = 'EN ATTENTE', [System.Drawing.Color]$PillColor = $script:C_Muted,
          [string]$BarColor = 'Accent')
    Set-UiStatus -Ctl $suiteStatus -Running $Running -Status $Status -Detail $Detail -Percent $Percent `
                 -PillText $PillText -PillColor $PillColor -BarColor $BarColor `
                 -EnableWhenIdle @($btnSuiteStart) -EnableWhenBusy @($btnSuiteCancel)
}

# --- Etat interne ---
$script:SuiteManualResumeFrom = 0
$script:SuiteSourceResolved   = $null

# ================= ACTION : DEMARRAGE INSTALLATION SUITE =================
$btnSuiteStart.Add_Click({
    $textBoxSuiteLog.Clear()
    Reset-RunRows $suiteView
    $script:SuiteCancelRequested = $false
    $script:SuiteManualResumeFrom = 0

    # --- Selection / validation du dossier source ---
    $source = $SuiteSourceDir
    if (-not $source -or -not (Test-Path -LiteralPath $source)) {
        Write-SuiteLog "Demande du dossier source Bentley Suite..." 'INFO'
        $source = Request-SintegraSourceDirectory -Initial $SuiteSourceDir
    }
    if (-not $source -or -not (Test-Path -LiteralPath $source)) {
        Show-Dialog "Aucun dossier source valide n'a ete fourni pour l'installation Bentley Suite." "Source manquante" 'Warning'
        Set-SuiteState -Running $false -Status "Source manquante" -Detail "Selectionnez un dossier source pour demarrer." -PillText 'ATTENTION' -PillColor $script:C_Amber -BarColor 'Amber'
        $btnSuiteResume.Enabled = $false
        return
    }
    $script:SuiteSourceResolved = $source
    Write-SuiteLog "Source Bentley Suite : $source" 'OK'

    Set-SuiteState -Running $true -Status "En cours" -Detail "Connexion des modules..." -Percent 0 -PillText 'EN COURS' -PillColor $script:C_Accent
    Write-SuiteLog "==============================================="
    Write-SuiteLog "Demarrage de l'installation Bentley Suite ($($script:BentleyModules.Count) modules)..."
    Write-SuiteLog "==============================================="

    $onProgress = {
        param($pct, $status, $idx, $mod)
        if ($mod -and $mod.Num) { Set-SuiteRowNum -Num $mod.Num -Status 'EN COURS' }
        Set-SuiteState -Running $true -Status $status -Detail ("Module {0:00} - {1}" -f $mod.Num, $mod.Name) -Percent $pct -PillText 'EN COURS' -PillColor $script:C_Accent
    }

    $logCb = { param($m, $l) Write-SuiteLog $m $l }

    # Protections : desactivation automatique avant installation (best effort).
    Disable-PcInstallProtections -Simulate:($DryRun -or $AutoTest) -Log $logCb

    try {
        # On desactive la demande de source interne en passant explicitement le chemin.
        $result = Invoke-BentleySuiteInstall -SourceDir $script:SuiteSourceResolved -Log $logCb -OnProgress $onProgress

        # Statut final de chaque ligne selon le resultat du moteur.
        foreach ($mod in $script:BentleyModules) {
            if ($result.Failed -contains $mod.Name) {
                Set-SuiteRowNum -Num $mod.Num -Status 'ECHOUE'
            } elseif ($result.Skipped -contains $mod.Name) {
                Set-SuiteRowNum -Num $mod.Num -Status 'MANUEL'
            } else {
                Set-SuiteRowNum -Num $mod.Num -Status 'OK'
            }
        }

        if ($result.Success) {
            Write-SuiteLog ("Installation terminee : {0}/{1} modules installe(s), {2} echec(s), {3} manuel(s)." -f $result.Installed, $result.TotalModules, $result.Failed.Count, $result.Skipped.Count) 'OK'
            Write-SuiteLog "==============================================="
            Set-SuiteState -Running $false -Status ("Terminee - {0}/{1} modules" -f $result.Installed, $result.TotalModules) -Detail ("{0} echec(s), {1} module(s) manuel(s)" -f $result.Failed.Count, $result.Skipped.Count) -Percent 100 -PillText 'SUCCES' -PillColor $script:C_Green -BarColor 'Green'
        } else {
            Write-SuiteLog ("Installation terminee avec erreurs : {0} echec(s), {1} manuel(s)." -f $result.Failed.Count, $result.Skipped.Count) 'ERREUR'
            Write-SuiteLog "==============================================="
            Set-SuiteState -Running $false -Status ("Terminee - {0} echec(s)" -f $result.Failed.Count) -Detail ("Modules en erreur : " + ($result.Failed -join ', ')) -Percent 100 -PillText 'ATTENTION' -PillColor $script:C_Amber -BarColor 'Amber'
        }

        # Modules manuels restants -> la reprise redemarre au premier manuel.
        if ($result.Skipped.Count -gt 0) {
            $firstManual = 999
            foreach ($mod in $script:BentleyModules) {
                if (($result.Skipped -contains $mod.Name) -and ($mod.Num -lt $firstManual)) { $firstManual = $mod.Num }
            }
            $script:SuiteManualResumeFrom = $firstManual
            $btnSuiteResume.Enabled = $true
            Show-Dialog ("Les modules manuels suivants necessitent une action :`r`n{0}`r`n`r`nCliquez sur 'Reprendre' apres avoir effectue l'installation manuelle." -f ($result.Skipped -join ', ')) "Modules manuels" 'Warning'
        } else {
            $btnSuiteResume.Enabled = $false
        }
    }
    catch {
        Write-SuiteLog "Erreur : $($_.Exception.Message)" 'ERREUR'
        Set-SuiteState -Running $false -Status "Erreur durant l'installation" -Detail $_.Exception.Message -PillText 'ERREUR' -PillColor $script:C_Red -BarColor 'Red'
        Show-Dialog $_.Exception.Message "Erreur" 'Error'
    }
})

# ================= ACTION : REPRISE APRES MANUEL =================
$btnSuiteResume.Add_Click({
    if (-not $script:SuiteSourceResolved) {
        Show-Dialog "Aucune source enregistree. Relancez l'installation." "Reprise impossible" 'Warning'
        return
    }
    $script:SuiteCancelRequested = $false
    Write-SuiteLog ("Reprise de l'installation a partir du module {0:00}..." -f $script:SuiteManualResumeFrom) 'INFO'
    $onProgress = {
        param($pct, $status, $idx, $mod)
        if ($mod -and $mod.Num) { Set-SuiteRowNum -Num $mod.Num -Status 'EN COURS' }
        Set-SuiteState -Running $true -Status $status -Detail ("Module {0:00} - {1}" -f $mod.Num, $mod.Name) -Percent $pct -PillText 'REPRISE' -PillColor $script:C_Amber -BarColor 'Amber'
    }
    Disable-PcInstallProtections -Simulate:($DryRun -or $AutoTest) -Log { param($m, $l) Write-SuiteLog $m $l }
    try {
        $result = Invoke-BentleySuiteInstall -SourceDir $script:SuiteSourceResolved -ResumeFrom $script:SuiteManualResumeFrom -Log { param($m, $l) Write-SuiteLog $m $l } -OnProgress $onProgress
        foreach ($mod in $script:BentleyModules) {
            if ($result.Failed -contains $mod.Name) { Set-SuiteRowNum -Num $mod.Num -Status 'ECHOUE' }
            elseif ($result.Skipped -contains $mod.Name) { Set-SuiteRowNum -Num $mod.Num -Status 'MANUEL' }
            elseif ($mod.Num -ge $script:SuiteManualResumeFrom) { Set-SuiteRowNum -Num $mod.Num -Status 'OK' }
        }
        Write-SuiteLog ("Reprise terminee : {0}/{1} modules, {2} echec(s)." -f $result.Installed, $result.TotalModules, $result.Failed.Count) 'OK'
        Set-SuiteState -Running $false -Status ("Reprise terminee - {0}/{1}" -f $result.Installed, $result.TotalModules) -Percent 100 -PillText 'SUCCES' -PillColor $script:C_Green -BarColor 'Green'
        $btnSuiteResume.Enabled = $false
    }
    catch {
        Write-SuiteLog "Erreur pendant la reprise : $($_.Exception.Message)" 'ERREUR'
        Set-SuiteState -Running $false -Status "Erreur" -Detail $_.Exception.Message -PillText 'ERREUR' -PillColor $script:C_Red -BarColor 'Red'
    }
})

$btnSuiteCancel.Add_Click({
    $script:SuiteCancelRequested = $true
    Write-SuiteLog "Annulation demandee..." 'ATTENTION'
    Set-SuiteState -Running $true -Status "Annulation en cours" -Detail "Interruption..." -Percent -1 -PillText 'ATTENTION' -PillColor $script:C_Amber -BarColor 'Amber'
})

# --- Initialisation ---
Write-SuiteLog "Vue Bentley Suite prete. Cliquez sur 'Demarrer' pour lancer l'installation ($($script:BentleyModules.Count) modules)."
Set-SuiteState -Running $false -Status "Pret" -Detail "Selectionnez le dossier source et lancez l'installation." -Percent 0 -PillText 'EN ATTENTE' -PillColor $script:C_Muted
$btnSuiteResume.Enabled = $false
