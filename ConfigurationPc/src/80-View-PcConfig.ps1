# ==================================================================
# src\80-View-PcConfig.ps1  -  Vue "Configuration PC"
#   Carte reseau (IPv6 + DNS), carte domaine Active Directory, carte
#   de statut, journal et actions du module PC, puis initialisation
#   (liste des cartes, journal de demarrage, onglet actif).
# Depend de : src\60-Shell.ps1 ($panelPc, $form), moteur du module 21.
# ==================================================================

# --- Carte 1 : reseau (DNS + IPv6) ---
$cardNet = New-RoundedPanel -W 728 -H 196 -R 12
$cardNet.Location = New-Object System.Drawing.Point(20, 10)
$panelPc.Controls.Add($cardNet)

$cardNet.Controls.Add((New-TextLabel -Text "RESEAU" -X 18 -Y 12 -W 200 -H 16 -Font $script:FontStep -Fore $script:C_Muted))
$cardNet.Controls.Add((New-TextLabel -Text "Carte reseau" -X 18 -Y 38 -W 200 -H 16 -Font $script:FontUI))
$cmbAdapter = New-Object System.Windows.Forms.ComboBox
$cmbAdapter.Location = New-Object System.Drawing.Point(18, 58)
$cmbAdapter.Size = New-Object System.Drawing.Size(560, 26)
$cmbAdapter.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbAdapter.Font = $script:FontUI
$cardNet.Controls.Add($cmbAdapter)

$btnRefreshAdapters = New-ModernButton -Text 'Rafraichir' -X 588 -Y 58 -W 120 -H 26 -Fill ([System.Drawing.Color]::FromArgb(232, 237, 244)) -Hover ([System.Drawing.Color]::FromArgb(214, 222, 232)) -Fore $script:C_Text -Font $script:FontUI
Set-RoundRegion $btnRefreshAdapters 8
$cardNet.Controls.Add($btnRefreshAdapters)

$chkIPv6 = New-Object System.Windows.Forms.CheckBox
$chkIPv6.Text = "Desactiver IPv6 (Protocole Internet Version 6)"
$chkIPv6.Location = New-Object System.Drawing.Point(18, 94)
$chkIPv6.Size = New-Object System.Drawing.Size(280, 22)
$chkIPv6.Font = $script:FontUI
$chkIPv6.Checked = $true
$chkIPv6.BackColor = $script:C_Card
$cardNet.Controls.Add($chkIPv6)

$chkValidate = New-Object System.Windows.Forms.CheckBox
$chkValidate.Text = "Valider les parametres en quittant"
$chkValidate.Location = New-Object System.Drawing.Point(304, 94)
$chkValidate.Size = New-Object System.Drawing.Size(260, 22)
$chkValidate.Font = $script:FontUI
$chkValidate.Checked = $true
$chkValidate.BackColor = $script:C_Card
$cardNet.Controls.Add($chkValidate)

$cardNet.Controls.Add((New-TextLabel -Text "DNS prefere" -X 18 -Y 126 -W 90 -H 16 -Font $script:FontUI))
$txtDns1 = New-Object System.Windows.Forms.TextBox
$txtDns1.Location = New-Object System.Drawing.Point(110, 124)
$txtDns1.Size = New-Object System.Drawing.Size(160, 24)
$txtDns1.Font = $script:FontUI
$txtDns1.Text = $DnsPrimary
$cardNet.Controls.Add($txtDns1)

$cardNet.Controls.Add((New-TextLabel -Text "DNS auxiliaire" -X 288 -Y 126 -W 100 -H 16 -Font $script:FontUI))
$txtDns2 = New-Object System.Windows.Forms.TextBox
$txtDns2.Location = New-Object System.Drawing.Point(400, 124)
$txtDns2.Size = New-Object System.Drawing.Size(160, 24)
$txtDns2.Font = $script:FontUI
$txtDns2.Text = $DnsSecondary
$cardNet.Controls.Add($txtDns2)

$cardNet.Controls.Add((New-TextLabel -Text "Recommandation : 192.168.1.214  puis  8.8.8.8" -X 440 -Y 11 -W 270 -H 16 -Font $script:FontMini -Fore $script:C_Muted -Align 'Right'))

$btnApplyNet = New-ModernButton -Text "Appliquer la configuration reseau" -X 18 -Y 154 -W 320 -H 34
$cardNet.Controls.Add($btnApplyNet)

# --- Carte 2 : domaine Active Directory ---
$cardDom = New-RoundedPanel -W 728 -H 210 -R 12
$cardDom.Location = New-Object System.Drawing.Point(20, 216)
$panelPc.Controls.Add($cardDom)

$cardDom.Controls.Add((New-TextLabel -Text "DOMAINE ACTIVE DIRECTORY" -X 18 -Y 12 -W 300 -H 16 -Font $script:FontStep -Fore $script:C_Muted))
$cardDom.Controls.Add((New-TextLabel -Text "Nom du poste" -X 18 -Y 38 -W 140 -H 16 -Font $script:FontUI))
$txtPcName = New-Object System.Windows.Forms.TextBox
$txtPcName.Location = New-Object System.Drawing.Point(18, 58)
$txtPcName.Size = New-Object System.Drawing.Size(180, 24)
$txtPcName.Font = $script:FontUI
$txtPcName.Text = $ComputerName
$cardDom.Controls.Add($txtPcName)

$cardDom.Controls.Add((New-TextLabel -Text "Domaine" -X 212 -Y 38 -W 140 -H 16 -Font $script:FontUI))
$txtDomain = New-Object System.Windows.Forms.TextBox
$txtDomain.Location = New-Object System.Drawing.Point(212, 58)
$txtDomain.Size = New-Object System.Drawing.Size(180, 24)
$txtDomain.Font = $script:FontUI
$txtDomain.Text = $DomainName
$cardDom.Controls.Add($txtDomain)

$cardDom.Controls.Add((New-TextLabel -Text "Compte du domaine (administrateur)" -X 406 -Y 38 -W 300 -H 16 -Font $script:FontUI))
$txtDomainUser = New-Object System.Windows.Forms.TextBox
$txtDomainUser.Location = New-Object System.Drawing.Point(406, 58)
$txtDomainUser.Size = New-Object System.Drawing.Size(300, 24)
$txtDomainUser.Font = $script:FontUI
$txtDomainUser.Text = $DomainUser
$cardDom.Controls.Add($txtDomainUser)

$cardDom.Controls.Add((New-TextLabel -Text "Mot de passe" -X 18 -Y 94 -W 140 -H 16 -Font $script:FontUI))
$txtDomainPwd = New-Object System.Windows.Forms.TextBox
$txtDomainPwd.Location = New-Object System.Drawing.Point(18, 114)
$txtDomainPwd.Size = New-Object System.Drawing.Size(180, 24)
$txtDomainPwd.Font = $script:FontUI
$txtDomainPwd.UseSystemPasswordChar = $true
$txtDomainPwd.Text = $DomainPassword
$cardDom.Controls.Add($txtDomainPwd)

$chkSim = New-Object System.Windows.Forms.CheckBox
$chkSim.Text = "Mode simulation (aucune modification appliquee)"
$chkSim.Location = New-Object System.Drawing.Point(212, 114)
$chkSim.Size = New-Object System.Drawing.Size(340, 24)
$chkSim.Font = $script:FontUI
$chkSim.Checked = [bool]$DryRun
$chkSim.BackColor = $script:C_Card
$cardDom.Controls.Add($chkSim)

$cardDom.Controls.Add((New-TextLabel -Text "Le redemarrage est volontairement reporte (equivalent 'Redemarrer ulterieurement')." -X 18 -Y 148 -W 690 -H 16 -Font $script:FontMini -Fore $script:C_Muted))

$btnJoin = New-ModernButton -Text "Renommer et joindre le domaine" -X 18 -Y 166 -W 340 -H 34 -Fill ([System.Drawing.Color]::FromArgb(23, 125, 95))
$cardDom.Controls.Add($btnJoin)

# --- Statut + journal du module PC (independants du module Bentley) ---
$pcStatus = New-MiniStatus -X 20 -Y 436
$panelPc.Controls.Add($pcStatus.Card)
$pcLog = New-LogCard -X 20 -Y 524 -H 120 -Title "JOURNAL D'EXECUTION - CONFIGURATION PC"
$panelPc.Controls.Add($pcLog.Card)

# --- Journal et etat de la vue (surcharge des helpers partages) ---
function Write-PcLog {
    param([string]$Message, [string]$Level = 'INFO')
    Write-UiLog -Box $pcLog.Box -Message $Message -Level $Level
}

function Set-PcState {
    param([bool]$Running, [string]$Status, [string]$Detail = '', [int]$Percent = -1,
          [string]$PillText = 'EN ATTENTE', [System.Drawing.Color]$PillColor = $script:C_Muted,
          [string]$BarColor = 'Accent')
    Set-UiStatus -Ctl $pcStatus -Running $Running -Status $Status -Detail $Detail -Percent $Percent `
                 -PillText $PillText -PillColor $PillColor -BarColor $BarColor `
                 -EnableWhenIdle @($btnApplyNet, $btnJoin, $btnRefreshAdapters)
}

# --- Listes et selection des cartes ---
function Update-AdapterList {
    $cmbAdapter.Items.Clear()
    foreach ($a in @(Get-PcAdapters)) {
        [void]$cmbAdapter.Items.Add(("{0}  ({1})  -  {2}" -f $a.Name, $a.Status, $a.Index))
    }
    if ($cmbAdapter.Items.Count -gt 0) {
        # Preselection : carte specifiee, sinon premiere carte connectee, sinon premiere
        $target = -1
        if ($AdapterName) {
            for ($i = 0; $i -lt $cmbAdapter.Items.Count; $i++) {
                if ($cmbAdapter.Items[$i] -like "$AdapterName *") { $target = $i; break }
            }
        }
        if ($target -lt 0) {
            for ($i = 0; $i -lt $cmbAdapter.Items.Count; $i++) {
                if ($cmbAdapter.Items[$i] -like '*Up*') { $target = $i; break }
            }
        }
        $cmbAdapter.SelectedIndex = if ($target -ge 0) { $target } else { 0 }
    }
}

function Get-SelectedAdapterName {
    if ($cmbAdapter.SelectedIndex -lt 0) { return $null }
    return ($cmbAdapter.Items[$cmbAdapter.SelectedIndex] -split '  ')[0].Trim()
}

# --- Action : rafraichissement de la liste ---
$btnRefreshAdapters.Add_Click({ Update-AdapterList; Write-PcLog "Liste des cartes reseau actualisee." 'INFO' })

# --- Action PC 1 : reseau (IPv6 + DNS) ---
$btnApplyNet.Add_Click({
    $adapter = Get-SelectedAdapterName
    $simulate = $chkSim.Checked
    Set-PcState -Running $true -Status "Configuration reseau en cours" -Detail ("Carte : {0}" -f $adapter) -Percent 20 -PillText 'EN COURS' -PillColor $script:C_Accent
    Write-PcLog "==============================================="
    Write-PcLog "Configuration reseau - carte '$adapter'$(if ($simulate) { '  [MODE SIMULATION]' })"
    Write-PcLog "==============================================="
    try {
        Set-AdapterNetwork -AdapterName $adapter `
                           -DnsPrimary $txtDns1.Text -DnsSecondary $txtDns2.Text `
                           -DisableIPv6:$chkIPv6.Checked -ValidateUponExit:$chkValidate.Checked `
                           -Simulate:$simulate -Log { param($m, $l) Write-PcLog $m $l } | Out-Null
        if ($simulate) {
            Set-PcState -Running $false -Status "Simulation reseau terminee" -Detail "Aucune modification appliquee (mode simulation)." -Percent 100 -PillText 'SIMULE' -PillColor $script:C_Amber -BarColor 'Amber'
        } else {
            Set-PcState -Running $false -Status "Reseau configure" -Detail ("IPv6 desactive : {0} | DNS : {1}, {2}" -f $chkIPv6.Checked, $txtDns1.Text, $txtDns2.Text) -Percent 100 -PillText 'SUCCES' -PillColor $script:C_Green -BarColor 'Green'
        }
        Show-Dialog ("Etape 1 - Configuration reseau`r`n`r`nCarte : {0}`r`nIPv6 desactive : {1}`r`nDNS prefere : {2}`r`nDNS auxiliaire : {3}`r`n`r`n{4}" -f $adapter, $chkIPv6.Checked, $txtDns1.Text, $txtDns2.Text, $(if ($simulate) { 'Mode simulation : rien n a ete applique.' } else { 'La configuration a ete appliquee.' })) "Configuration reseau" 'Information'
    }
    catch {
        Write-PcLog "Erreur : $($_.Exception.Message)" 'ERREUR'
        Set-PcState -Running $false -Status "Echec de la configuration reseau" -Detail $_.Exception.Message -PillText 'ERREUR' -PillColor $script:C_Red -BarColor 'Red'
        Show-Dialog $_.Exception.Message "Erreur reseau" 'Error'
    }
})

# --- Action PC 2 : renommage + jonction au domaine ---
$btnJoin.Add_Click({
    $simulate = $chkSim.Checked
    Set-PcState -Running $true -Status "Jonction au domaine en cours" -Detail ("Poste '{0}' -> {1}" -f $txtPcName.Text, $txtDomain.Text) -Percent 20 -PillText 'EN COURS' -PillColor $script:C_Accent
    Write-PcLog "==============================================="
    Write-PcLog "Renommage et jonction au domaine$(if ($simulate) { '  [MODE SIMULATION]' })"
    Write-PcLog "==============================================="
    try {
        Invoke-PcDomainJoin -ComputerName $txtPcName.Text -DomainName $txtDomain.Text `
                            -DomainUser $txtDomainUser.Text -DomainPassword $txtDomainPwd.Text `
                            -Simulate:$simulate -Log { param($m, $l) Write-PcLog $m $l } | Out-Null
        if ($simulate) {
            Set-PcState -Running $false -Status "Simulation domaine terminee" -Detail "Aucune modification appliquee (mode simulation)." -Percent 100 -PillText 'SIMULE' -PillColor $script:C_Amber -BarColor 'Amber'
        } else {
            Set-PcState -Running $false -Status "Poste joint au domaine" -Detail ("{0} est membre de {1} - redemarrage requis (reporte)." -f $txtPcName.Text, $txtDomain.Text) -Percent 100 -PillText 'SUCCES' -PillColor $script:C_Green -BarColor 'Green'
        }
        Show-Dialog ("Etape 2 - Integration Active Directory`r`n`r`nNom du poste : {0}`r`nDomaine : {1}`r`nCompte : {2}`r`n`r`n{3}" -f $txtPcName.Text, $txtDomain.Text, $txtDomainUser.Text, $(if ($simulate) { 'Mode simulation : rien n a ete applique.' } else { 'Le poste est joint au domaine. Redemarrez le PC pour finaliser.' })) "Integration au domaine" 'Information'
    }
    catch {
        Write-PcLog "Erreur : $($_.Exception.Message)" 'ERREUR'
        Set-PcState -Running $false -Status "Echec de la jonction au domaine" -Detail $_.Exception.Message -PillText 'ERREUR' -PillColor $script:C_Red -BarColor 'Red'
        Show-Dialog $_.Exception.Message "Erreur domaine" 'Error'
    }
})

# ================= INIT DU MODULE PC =================
Update-AdapterList
Write-PcLog "Module pret. Carte detectee : $(Get-SelectedAdapterName)"
if ($chkSim.Checked) { Write-PcLog "Mode simulation actif : aucune modification ne sera appliquee." 'ATTENTION' }
Set-PcState -Running $false -Status "Pret" -Detail "Selectionnez une carte, puis appliquez la configuration." -Percent 0 -PillText 'EN ATTENTE' -PillColor $script:C_Muted
Activate-Module -Which $StartTab
