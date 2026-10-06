# ==================================================================
# src\70-View-Deployment.ps1  -  Vue "Deploiement Bentley" (gabarit run)
#   Carte statut + liste des 3 etapes + journal plein + barre
#   d'actions (Lancer le deploiement / Deploiement automatique).
#   Branchee sur le moteur reel (module 20) : callbacks -Log et
#   -OnProgress pilotent lignes, carte statut et journal.
# Depend de : src\50-Widgets.ps1 (New-RunView), src\60-Shell.ps1
#             (Add-ViewPanel, Show-View), moteur 20.
# ==================================================================

# --- Gabarit commun aux vues a etapes ---
$deployView = New-RunView -ReadyText "Choisissez une action pour commencer." -Steps @(
    @('Source de reference', 'it_st  ->  C:\IT_Config'),
    @('Profil par defaut',   'C:\Users\Default'),
    @('Profils utilisateurs', 'Tous les comptes du poste')
) -GoText 'Lancer le deploiement' -ExtraText "Deploiement automatique a l'ouverture de session" -ShowResume $false
Add-ViewPanel -Key 'Bentley' -Panel $deployView.Panel

# Aliases utilises par 90-App (garde de fermeture, AutoTest, journaux).
$mainStatus   = $deployView.Status
$textBoxLog   = $deployView.Log
$btnRun       = $deployView.BtnGo
$btnGpo       = $deployView.BtnExtra
$btnCancel    = $deployView.BtnCancel

# --- Pilotage des lignes d'etape selon la progression ---
function Set-DeployRows {
    param([int]$Active, [string]$ActiveText = 'EN COURS')
    for ($i = 0; $i -lt 3; $i++) {
        $st = if ($i -lt $Active) { 'OK' } elseif ($i -eq $Active) { $ActiveText } else { 'EN ATTENTE' }
        Set-RunRow $deployView $i $st
    }
}

# --- Journal et etat de la vue ---
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    Write-UiLog -Box $textBoxLog -Message $Message -Level $Level
    Set-Status $Message
}

function Set-State {
    param([bool]$Running, [string]$Status, [string]$Detail = '', [int]$Percent = -1,
          [string]$PillText = 'EN ATTENTE', [System.Drawing.Color]$PillColor = $script:C_Muted,
          [string]$BarColor = 'Accent')
    Set-UiStatus -Ctl $mainStatus -Running $Running -Status $Status -Detail $Detail -Percent $Percent `
                 -PillText $PillText -PillColor $PillColor -BarColor $BarColor `
                 -EnableWhenIdle @($btnRun, $btnGpo) -EnableWhenBusy @($btnCancel)
}

# ================= ACTION : DEPLOIEMENT AUTOMATIQUE (RunOnce) =================
$btnGpo.Add_Click({
    Set-State -Running $true -Status "Installation du deploiement automatique" -Detail "Preparation de la strategie d'ouverture de session..." -Percent 10 -PillText 'EN COURS' -PillColor $script:C_Accent
    try {
        Write-Log "==============================================="
        Write-Log "Installation du deploiement automatique a l'ouverture de session..."
        Write-Log "==============================================="
        $g = Install-AutoDeploy -Log { param($m, $l) Write-Log $m $l }
        Set-State -Running $false -Status "Installe" -Detail ("Le deploiement se lancera a chaque ouverture de session - " + $g.ScriptPath) -Percent 100 -PillText 'SUCCES' -PillColor $script:C_Green -BarColor 'Green'
        Show-Dialog ("Le deploiement automatique est installe.`r`n`r`nScript : {0}`r`nWrapper : {1}`r`nEntree : {2}`r`n`r`nLa configuration sera copiee automatiquement dans le profil de tout utilisateur qui ouvrira une session sur ce poste, sans jamais ecraser une configuration deja presente." -f $g.ScriptPath, $g.CmdPath, $g.RunOnceKey) "Deploiement installe" 'Information'
    }
    catch {
        Write-Log "Erreur : $($_.Exception.Message)" 'ERREUR'
        Set-State -Running $false -Status "Echec de l'installation" -Detail $_.Exception.Message -PillText 'ERREUR' -PillColor $script:C_Red -BarColor 'Red'
        Show-Dialog $_.Exception.Message "Erreur" 'Error'
    }
})

# ================= ACTION : DEPLOIEMENT BENTLEY =================
$btnRun.Add_Click({
    $textBoxLog.Clear()
    Reset-RunRows $deployView
    $script:CancelRequested = $false
    Set-State -Running $true -Status "En cours" -Detail "Etape 1 - preparation de la source de reference..." -Percent 0 -PillText 'EN COURS' -PillColor $script:C_Accent

    Write-Log "==============================================="
    Write-Log "Demarrage de la procedure de deploiement..."
    Write-Log "==============================================="

    $onProgress = {
        param($pct, $status)
        $active = if ($pct -lt 34) { 0 } elseif ($pct -lt 50) { 1 } else { 2 }
        Set-DeployRows -Active $active
        Set-State -Running $true -Status $status -Detail ("Progression : {0} %" -f $pct) -Percent $pct -PillText 'EN COURS' -PillColor $script:C_Accent
    }

    # Protections : desactivation automatique avant installation (best effort).
    Disable-PcInstallProtections -Simulate:($DryRun -or $AutoTest) -Log { param($m, $l) Write-Log $m $l }

    try {
        $result = Invoke-BentleyDeployment -OnProgress $onProgress -Log { param($m, $l) Write-Log $m $l }
        Write-Log "==============================================="
        if ($result.Success) {
            0..2 | ForEach-Object { Set-RunRow $deployView $_ 'OK' }
            Write-Log ("Deploiement termine avec succes : {0}/{1} profil(s), {2} fichiers de reference." -f $result.Updated, $result.Targets, $result.Files) 'OK'
            Write-Log "Redemarrage de PowerDraft recommande." 'INFO'
            Write-Log "==============================================="
            Set-State -Running $false -Status ("Termine - {0} profil(s) mis a jour" -f $result.Updated) -Detail ("Sur {0} profils analyses - Redemarrez PowerDraft pour appliquer." -f $result.Targets) -Percent 100 -PillText 'SUCCES' -PillColor $script:C_Green -BarColor 'Green'
            Show-Dialog ("Le deploiement de Bentley PowerDraft s'est deroule correctement.`r`n`r`n{0} profil(s) mis a jour sur {1}.`r`nRedemarrez PowerDraft pour appliquer." -f $result.Updated, $result.Targets) "Succes" 'Information'
        }
        else {
            # La ligne en cours passe en echec, les autres restent telles quelles.
            for ($i = 0; $i -lt 3; $i++) {
                if ($deployView.List.Items[$i].SubItems[2].Text -eq 'EN COURS') { Set-RunRow $deployView $i 'ERREUR' }
            }
            Write-Log ("Termine avec {0} echec(s) : {1}" -f $result.Failed.Count, ($result.Failed -join ', ')) 'ERREUR'
            Write-Log "==============================================="
            Set-State -Running $false -Status ("Termine - {0} echec(s)" -f $result.Failed.Count) -Detail ("Profils en echec : " + ($result.Failed -join ', ')) -Percent 100 -PillText 'ATTENTION' -PillColor $script:C_Amber -BarColor 'Amber'
            Show-Dialog ("Le deploiement est termine mais {0} profil(s) ont echoue :`r`n{1}`r`n`r`nConsultez le journal pour le detail." -f $result.Failed.Count, ($result.Failed -join ', ')) "Termine avec avertissement" 'Warning'
        }
    }
    catch {
        for ($i = 0; $i -lt 3; $i++) {
            if ($deployView.List.Items[$i].SubItems[2].Text -eq 'EN COURS') { Set-RunRow $deployView $i 'ARRET' }
        }
        Write-Log "Erreur : $($_.Exception.Message)" 'ERREUR'
        Set-State -Running $false -Status "Erreur durant le deploiement" -Detail $_.Exception.Message -PillText 'ERREUR' -PillColor $script:C_Red -BarColor 'Red'
        Show-Dialog $_.Exception.Message "Erreur" 'Error'
    }
})

$btnCancel.Add_Click({
    $script:CancelRequested = $true
    Write-Log "Annulation demandee, fin de l'operation en cours..." 'ATTENTION'
    Set-State -Running $true -Status "Annulation en cours" -Detail "Interruption en cours..." -Percent -1 -PillText 'ATTENTION' -PillColor $script:C_Amber -BarColor 'Amber'
})

# --- Initialisation de la vue ---
Write-Log "Vue Deploiement prete. Cliquez sur une action pour commencer."
Set-State -Running $false -Status "Pret" -Detail "Choisissez une action pour commencer." -Percent 0 -PillText 'EN ATTENTE' -PillColor $script:C_Muted
