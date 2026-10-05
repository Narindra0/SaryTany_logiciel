# ==================================================================
# src\70-View-Deployment.ps1  -  Vue "Deploiement Bentley PowerDraft"
#   Stepper des 3 etapes, carte de statut, journal, barre d'actions,
#   actions de deploiement et transfert des controles dans le panneau.
# Depend de : src\60-Shell.ps1 ($form, $panelBentley, les panneaux),
#             moteur du module 20.
# ==================================================================

# --- Cartes des 3 etapes (stepper) ---
$script:StepCards = @(
    (New-StepCard -Index 1 -Title 'Source de reference' -Sub 'it_st  ->  C:\IT_Config' -X 20),
    (New-StepCard -Index 2 -Title 'Profil par defaut' -Sub 'C:\Users\Default' -X 266),
    (New-StepCard -Index 3 -Title 'Profils utilisateurs' -Sub 'Tous les comptes du poste' -X 512)
)

function Set-StepState {
    param([int]$Number, [string]$State)
    $c = $script:StepCards[$Number - 1]
    if ($c) { $c.Tag.State = $State; $c.Invalidate() }
}

function Reset-Steps {
    1..3 | ForEach-Object { Set-StepState -Number $_ -State 'pending' }
}

# --- Carte statut + progression ---
$mainStatus = New-MiniStatus -X 20 -Y 168
$form.Controls.Add($mainStatus.Card)
$cardStatus   = $mainStatus.Card
$lblStatus    = $mainStatus.Label
$lblStatusSub = $mainStatus.Sub
$pill         = $mainStatus.Pill
$bar          = $mainStatus.Bar

# --- Journal ---
$mainLog = New-LogCard -X 20 -Y 256 -H 346 -Title "JOURNAL D'EXECUTION"
$form.Controls.Add($mainLog.Card)
$cardLog    = $mainLog.Card
$textBoxLog = $mainLog.Box

# --- Barre d'actions ---
$btnGpo = New-ModernButton -Text "Deploiement automatique a l'ouverture de session" -X 20 -Y 614 -W 728 -H 42 -Fill $script:C_Green -Hover ([System.Drawing.Color]::FromArgb(17, 138, 102))
$form.Controls.Add($btnGpo)

$btnRun = New-ModernButton -Text "Lancer le deploiement" -X 20 -Y 662 -W 300 -H 42
$form.Controls.Add($btnRun)

$btnCancel = New-ModernButton -Text "Annuler" -X 330 -Y 662 -W 150 -H 42 -Fill ([System.Drawing.Color]::FromArgb(198, 205, 214)) -Hover ([System.Drawing.Color]::FromArgb(176, 184, 194)) -Fore ([System.Drawing.Color]::FromArgb(45, 52, 62))
$btnCancel.Enabled = $false
$form.Controls.Add($btnCancel)

$btnClose = New-ModernButton -Text "Quitter" -X 490 -Y 662 -W 110 -H 42 -Fill ([System.Drawing.Color]::FromArgb(108, 116, 128)) -Hover ([System.Drawing.Color]::FromArgb(86, 94, 106))
$form.Controls.Add($btnClose)

$btnCloseBox.Add_Click({ $form.Close() })
$btnClose.Add_Click({ $form.Close() })
$btnCancel.Add_Click({
    $script:CancelRequested = $true
    Write-Log "Annulation demandee, fin de l'operation en cours..." 'ATTENTION'
    Set-State -Running $true -Status "Annulation en cours" -PillText 'ARRET' -PillColor $script:C_Amber -BarColor 'Amber'
})

# --- Journal et etat de la vue (surcharge des helpers partages) ---
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    Write-UiLog -Box $textBoxLog -Message $Message -Level $Level
}

function Set-State {
    param([bool]$Running, [string]$Status, [string]$Detail = '', [int]$Percent = -1,
          [string]$PillText = 'EN ATTENTE', [System.Drawing.Color]$PillColor = $script:C_Muted,
          [string]$BarColor = 'Accent')
    Set-UiStatus -Ctl $mainStatus -Running $Running -Status $Status -Detail $Detail -Percent $Percent `
                 -PillText $PillText -PillColor $PillColor -BarColor $BarColor `
                 -EnableWhenIdle @($btnRun, $btnClose, $btnGpo) -EnableWhenBusy @($btnCancel)
}

# ================= ACTION : DEPLOIEMENT AUTOMATIQUE (RunOnce) =================
$btnGpo.Add_Click({
    Set-State -Running $true -Status "Installation du deploiement automatique" -Detail "Preparation de la strategie d'ouverture de session..." -Percent 10 -PillText 'EN COURS' -PillColor $script:C_Accent
    try {
        Write-Log "==============================================="
        Write-Log "Installation du deploiement automatique a l'ouverture de session..."
        Write-Log "==============================================="
        $g = Install-AutoDeploy -Log { param($m, $l) Write-Log $m $l }
        Set-State -Running $false -Status "Deploiement automatique installe" -Detail ("Copie automatique a chaque ouverture de session - " + $g.ScriptPath) -Percent 100 -PillText 'PRET' -PillColor $script:C_Green -BarColor 'Green'
        Show-Dialog ("Le deploiement automatique est installe.`r`n`r`nScript : {0}`r`nWrapper : {1}`r`nEntree : {2}`r`n`r`nLa configuration sera copiee automatiquement dans le profil de tout utilisateur qui ouvrira une session sur ce poste, sans jamais ecraser une configuration deja presente." -f $g.ScriptPath, $g.CmdPath, $g.RunOnceKey) "Deploiement automatique installe" 'Information'
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
    $script:CancelRequested = $false
    Reset-Steps
    Set-State -Running $true -Status "Deploiement en cours" -Detail "Etape 1 - preparation de la source de reference..." -Percent 0 -PillText 'EN COURS' -PillColor $script:C_Accent
    Write-Log "==============================================="
    Write-Log "Demarrage de la procedure de deploiement..."
    Write-Log "==============================================="

    $onProgress = {
        param($pct, $status)
        if ($pct -lt 34) {
            Set-StepState -Number 1 -State 'active'
        }
        elseif ($pct -lt 50) {
            Set-StepState -Number 1 -State 'done'
            Set-StepState -Number 2 -State 'active'
        }
        else {
            Set-StepState -Number 1 -State 'done'
            Set-StepState -Number 2 -State 'done'
            Set-StepState -Number 3 -State 'active'
        }
        Set-State -Running $true -Status $status -Detail ("Progression : {0} %" -f $pct) -Percent $pct -PillText 'EN COURS' -PillColor $script:C_Accent
    }

    try {
        $result = Invoke-BentleyDeployment -OnProgress $onProgress -Log { param($m, $l) Write-Log $m $l }
        Write-Log "==============================================="
        if ($result.Success) {
            1..3 | ForEach-Object { Set-StepState -Number $_ -State 'done' }
            Write-Log ("Deploiement termine avec succes : {0}/{1} profil(s), {2} fichiers de reference." -f $result.Updated, $result.Targets, $result.Files) 'OK'
            Write-Log "Redemarrage de PowerDraft recommande." 'INFO'
            Write-Log "==============================================="
            Set-State -Running $false -Status ("Deploiement termine - {0} profil(s) mis a jour" -f $result.Updated) -Detail ("Sur {0} profil(s) analyse(s) - Redemarrez PowerDraft pour appliquer." -f $result.Targets) -Percent 100 -PillText 'SUCCES' -PillColor $script:C_Green -BarColor 'Green'
            Show-Dialog ("Le deploiement de Bentley PowerDraft s'est deroule correctement.`r`n`r`n{0} profil(s) mis a jour sur {1}.`r`nRedemarrez PowerDraft pour appliquer." -f $result.Updated, $result.Targets) "Succes" 'Information'
        }
        else {
            1..3 | ForEach-Object {
                if ($script:StepCards[$_ - 1].Tag.State -eq 'active') { Set-StepState -Number $_ -State 'error' }
            }
            Write-Log ("Termine avec {0} echec(s) : {1}" -f $result.Failed.Count, ($result.Failed -join ', ')) 'ERREUR'
            Write-Log "==============================================="
            Set-State -Running $false -Status ("Termine - {0} echec(s)" -f $result.Failed.Count) -Detail ("Profils en echec : " + ($result.Failed -join ', ')) -Percent 100 -PillText 'AVERTISSEMENT' -PillColor $script:C_Amber -BarColor 'Amber'
            Show-Dialog ("Le deploiement est termine mais {0} profil(s) ont echoue :`r`n{1}`r`n`r`nConsultez le journal pour le detail." -f $result.Failed.Count, ($result.Failed -join ', ')) "Termine avec avertissement" 'Warning'
        }
    }
    catch {
        Write-Log "Erreur : $($_.Exception.Message)" 'ERREUR'
        Set-State -Running $false -Status "Erreur durant le deploiement" -Detail $_.Exception.Message -PillText 'ERREUR' -PillColor $script:C_Red -BarColor 'Red'
        Show-Dialog $_.Exception.Message "Erreur" 'Error'
    }
})

# --- Deplacement de tous les controles Bentley deja construits dans leur panneau ---
$titleBarH = 62
foreach ($c in @($form.Controls)) {
    if (($c -ne $titleBar) -and ($c -ne $navBar) -and ($c -ne $panelBentley) -and ($c -ne $panelPc)) {
        $c.Location = New-Object System.Drawing.Point($c.Left, ($c.Top - $titleBarH))
        $panelBentley.Controls.Add($c)
    }
}
