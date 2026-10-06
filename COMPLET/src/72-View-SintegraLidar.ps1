# ==================================================================
# src\72-View-SintegraLidar.ps1  -  Vue "SintegraLidar" (gabarit run)
#   Integration en 7 etapes (source, securite, copie, registre, PATH,
#   separateur decimal, integration Bentley) via le gabarit run :
#   carte statut + liste d'etapes + journal plein + barre d'actions.
#   Protection anti-analyse, compteur d'essais trial, informations
#   applicatives remonte dans le journal et la carte statut.
# Depend de : src\50-Widgets.ps1 (New-RunView), src\60-Shell.ps1,
#             moteur 23 (Invoke-SintegraLidarInstall etc.), 55-Licence.
# ==================================================================

# --- Gabarit run : les 7 etapes du moteur ---
$sinView = New-RunView -ReadyText "Selectionnez le dossier source puis lancez l'integration." -Steps @(
    @('Selection source',      'Dossier source SintegraLidar'),
    @('Securite destination',  'Creation + permissions icacls'),
    @('Copie des fichiers',    'Source -> destination'),
    @('Import registre',       'Fichier .reg'),
    @('Ajout au PATH',         'Variable systeme PATH'),
    @('Separateur decimal',    'Decimal = point'),
    @('Integration Bentley',   'Fichier mvba PowerDraft')
) -GoText "Demarrer l'integration" -ShowResume $false
Add-ViewPanel -Key 'Sintegra' -Panel $sinView.Panel

# Aliases utilises par 90-App (garde de fermeture, AutoTest, journaux).
$sinStatus     = $sinView.Status
$textBoxSinLog = $sinView.Log
$btnSinStart   = $sinView.BtnGo
$btnSinCancel  = $sinView.BtnCancel

# --- Pilotage des lignes d'etape selon la progression ---
# Paliers du moteur : 5/15/35/50/60/75/90 % -> etapes 1..7.
function Set-SinRows {
    param([int]$Active, [string]$ActiveText = 'EN COURS')
    for ($i = 0; $i -lt 7; $i++) {
        $st = if ($i -lt $Active) { 'OK' } elseif ($i -eq $Active) { $ActiveText } else { 'EN ATTENTE' }
        Set-RunRow $sinView $i $st
    }
}

function Get-SinActiveStep {
    param([int]$Pct)
    $stepMap = @(5, 15, 35, 50, 60, 75, 90)
    $active = 0
    for ($i = 0; $i -lt $stepMap.Count; $i++) {
        if ($Pct -ge $stepMap[$i]) { $active = $i }
    }
    return $active
}

# --- Journal et etat de la vue ---
function Write-SinLog {
    param([string]$Message, [string]$Level = 'INFO')
    Write-UiLog -Box $textBoxSinLog -Message $Message -Level $Level
    Set-Status $Message
}

function Set-SinState {
    param([bool]$Running, [string]$Status, [string]$Detail = '', [int]$Percent = -1,
          [string]$PillText = 'EN ATTENTE', [System.Drawing.Color]$PillColor = $script:C_Muted,
          [string]$BarColor = 'Accent')
    Set-UiStatus -Ctl $sinStatus -Running $Running -Status $Status -Detail $Detail -Percent $Percent `
                 -PillText $PillText -PillColor $PillColor -BarColor $BarColor `
                 -EnableWhenIdle @($btnSinStart) -EnableWhenBusy @($btnSinCancel)
}

# --- Compteur d'essais trial ---
$script:SinTrialUsed = 0

# ================= ACTION : DEMARRAGE INTEGRATION SINTEGRA =================
$btnSinStart.Add_Click({
    $textBoxSinLog.Clear()
    Reset-RunRows $sinView
    $script:SintegraCancelRequested = $false
    $script:SinTrialUsed = 0

    # --- Protection anti-analyse ---
    if (Test-AnalysisEnvironment) {
        $msg = "Environnement d'analyse detecte (debogueur, nom d'ordinateur ou variable d'environnement suspecte). L'integration est refusee pour des raisons de securite."
        Write-SinLog $msg 'ERREUR'
        Set-SinState -Running $false -Status "Analyse detectee" -Detail $msg -PillText 'ERREUR' -PillColor $script:C_Red -BarColor 'Red'
        Show-Dialog $msg "Protection anti-analyse" 'Error'
        return
    }
    Write-SinLog "Verifications d'environnement : aucune menace detectee." 'OK'

    # --- Selection / validation du dossier source ---
    $source = $SintegraSourceDir
    if (-not $source -or -not (Test-Path -LiteralPath $source)) {
        Write-SinLog "Demande du dossier source SintegraLidar..." 'INFO'
        $source = Request-SintegraSourceDirectory -Initial $SintegraSourceDir
    }
    if (-not $source -or -not (Test-Path -LiteralPath $source)) {
        Show-Dialog "Aucun dossier source valide n'a ete fourni pour l'integration SintegraLidar." "Source manquante" 'Warning'
        Set-SinState -Running $false -Status "Source manquante" -Detail "Selectionnez un dossier source." -PillText 'ATTENTION' -PillColor $script:C_Amber -BarColor 'Amber'
        return
    }
    Write-SinLog "Source SintegraLidar : $source" 'OK'

    # --- Compteur d'essais ---
    $script:SinTrialUsed++
    Write-SinLog ("Lancement d'essai no " + $script:SinTrialUsed + " / " + $TrialMaxLaunches) 'INFO'
    if ($script:SinTrialUsed -gt $TrialMaxLaunches) {
        Write-SinLog ("Limite d'essais atteinte (" + $TrialMaxLaunches + "). Contactez votre administrateur.") 'ERREUR'
        Set-SinState -Running $false -Status "Limite d'essais atteinte" -Detail ("Tentative " + $script:SinTrialUsed + "/" + $TrialMaxLaunches) -PillText 'ERREUR' -PillColor $script:C_Red -BarColor 'Red'
        Show-Dialog ("Limite d'essais atteinte (" + $TrialMaxLaunches + "). Le compteur a ete consigne.") "Essai limite" 'Warning'
        return
    }

    Set-SinState -Running $true -Status "En cours" -Detail "Initialisation..." -Percent 0 -PillText 'EN COURS' -PillColor $script:C_Accent
    Write-SinLog "==============================================="
    Write-SinLog "Demarrage de l'integration SintegraLidar (7 etapes)..."
    Write-SinLog "==============================================="
    Set-SinRows -Active 0

    # --- Callback de progression etape par etape ---
    $onProgress = {
        param($pct, $status)
        Set-SinRows -Active (Get-SinActiveStep -Pct $pct)
        Set-SinState -Running $true -Status $status -Detail ("Progression : {0} %" -f $pct) -Percent $pct -PillText 'EN COURS' -PillColor $script:C_Accent
    }

    $logCb = { param($m, $l) Write-SinLog $m $l }

    # Protections : desactivation automatique avant installation (best effort).
    Disable-PcInstallProtections -Simulate:($DryRun -or $AutoTest) -Log $logCb

    try {
        $result = Invoke-SintegraLidarInstall -SourceDir $source -DestDir $SintegraDestDir -TrialLimit $TrialMaxLaunches -Log $logCb -OnProgress $onProgress

        0..6 | ForEach-Object { Set-RunRow $sinView $_ 'OK' }
        Write-SinLog ("Integration terminee : dest = {0}, essai = {1}/{2}" -f $result.DestDir, $result.TrialNumber, $TrialMaxLaunches) 'OK'
        Write-SinLog ("Application : {0} v{1} - {2} ({3})" -f $result.AppName, $result.AppVersion, $script:SintegraDevName, $script:SintegraContactEmail) 'INFO'
        Write-SinLog "==============================================="
        Set-SinState -Running $false -Status ("Terminee - {0} v{1}" -f $result.AppName, $result.AppVersion) -Detail ("Destination : {0} | Essai : {1}/{2}" -f $result.DestDir, $result.TrialNumber, $TrialMaxLaunches) -Percent 100 -PillText 'SUCCES' -PillColor $script:C_Green -BarColor 'Green'
    }
    catch {
        for ($i = 0; $i -lt 7; $i++) {
            if ($sinView.List.Items[$i].SubItems[2].Text -eq 'EN COURS') { Set-RunRow $sinView $i 'ERREUR' }
        }
        Write-SinLog "Erreur : $($_.Exception.Message)" 'ERREUR'
        Set-SinState -Running $false -Status "Erreur durant l'integration" -Detail $_.Exception.Message -PillText 'ERREUR' -PillColor $script:C_Red -BarColor 'Red'
        Show-Dialog $_.Exception.Message "Erreur SintegraLidar" 'Error'
    }
})

$btnSinCancel.Add_Click({
    $script:SintegraCancelRequested = $true
    Write-SinLog "Annulation demandee..." 'ATTENTION'
    Set-SinState -Running $true -Status "Annulation en cours" -Detail "Interruption..." -Percent -1 -PillText 'ATTENTION' -PillColor $script:C_Amber -BarColor 'Amber'
})

# --- Initialisation ---
Write-SinLog "Vue SintegraLidar prete. Cliquez sur 'Demarrer' pour lancer l'integration (7 etapes)."
Set-SinState -Running $false -Status "Pret" -Detail "Selectionnez le dossier source puis lancez l'integration." -Percent 0 -PillText 'EN ATTENTE' -PillColor $script:C_Muted
