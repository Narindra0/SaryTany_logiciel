# ==================================================================
# src\80-View-PcConfig.ps1  -  Vue "Configuration PC" (maquette)
#   Deux cartes posees sur un panneau AutoScroll, comme la maquette
#   Interface-Sarytany : "Reseau" (carte reseau, IPv6, DNS, action)
#   et "Domaine Active Directory" (poste, domaine, compte, mot de
#   passe, simulation, action). Carte unique "Verifications et
#   protections" : etat jonction AD + DNS + protections (lecture seule,
#   reactivation manuelle) ; la DESACTIVATION Defender/pare-feu est
#   AUTOMATIQUE avant chaque installation, puis journal.
#   Le pied de page porte l'etat horodate (Set-Status).
# Depend de : src\60-Shell.ps1 (Add-ViewPanel), src\50-Widgets.ps1,
#             moteur 21 (Get-PcAdapters, Set-AdapterNetwork,
#             Invoke-PcDomainJoin, Get-PcDomainStatus,
#             Test-PcDnsConnectivity, Get-PcProtectionsState,
#             Disable-PcInstallProtections, Enable-PcProtections).
# ==================================================================

# --- Panneau de vue (defilable, contenu en coordonnees locales) ---
$panelPc = New-Object System.Windows.Forms.Panel
$panelPc.Dock = 'Fill'
$panelPc.Visible = $false
$panelPc.AutoScroll = $true
$panelPc.BackColor = $script:C_Bg
Set-DoubleBuffer $panelPc
Add-ViewPanel -Key 'Pc' -Panel $panelPc

# ================= CARTE 1 : RESEAU =================
$cardNet = New-Card -Title 'Reseau' -X 24 -Y 20 -W 660 -H 216 -Parent $panelPc

New-TextLabel -Text 'Carte reseau' -X 16 -Y 42 -W 200 -H 18 -Parent $cardNet | Out-Null
$cmbAdapter = New-Object System.Windows.Forms.ComboBox
$cmbAdapter.Location = New-Object System.Drawing.Point(16, 62)
$cmbAdapter.Size = New-Object System.Drawing.Size(440, 26)
$cmbAdapter.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbAdapter.Font = $script:FontUI
$cardNet.Controls.Add($cmbAdapter)

$btnRefreshAdapters = New-SecondaryButton -Text 'Rafraichir' -X 468 -Y 61 -W 92 -H 26 -Font $script:FontMini
$cardNet.Controls.Add($btnRefreshAdapters)

$chkIPv6 = New-Object System.Windows.Forms.CheckBox
$chkIPv6.Text = 'Desactiver IPv6 (Protocole Internet Version 6)'
$chkIPv6.Location = New-Object System.Drawing.Point(16, 98)
$chkIPv6.Size = New-Object System.Drawing.Size(320, 22)
$chkIPv6.Font = $script:FontUI
$chkIPv6.Checked = $true
$chkIPv6.BackColor = $script:C_Card
$cardNet.Controls.Add($chkIPv6)

$chkValidate = New-Object System.Windows.Forms.CheckBox
$chkValidate.Text = 'Valider les parametres en quittant'
$chkValidate.Location = New-Object System.Drawing.Point(16, 120)
$chkValidate.Size = New-Object System.Drawing.Size(260, 22)
$chkValidate.Font = $script:FontUI
$chkValidate.Checked = $true
$chkValidate.BackColor = $script:C_Card
$cardNet.Controls.Add($chkValidate)

New-TextLabel -Text 'DNS prefere' -X 16 -Y 150 -W 140 -H 18 -Parent $cardNet | Out-Null
New-TextLabel -Text 'DNS auxiliaire' -X 200 -Y 150 -W 140 -H 18 -Parent $cardNet | Out-Null
$txtDns1 = New-Object System.Windows.Forms.TextBox
$txtDns1.Location = New-Object System.Drawing.Point(16, 170)
$txtDns1.Size = New-Object System.Drawing.Size(160, 24)
$txtDns1.Font = $script:FontUI
$txtDns1.Text = $DnsPrimary
$cardNet.Controls.Add($txtDns1)
$txtDns2 = New-Object System.Windows.Forms.TextBox
$txtDns2.Location = New-Object System.Drawing.Point(200, 170)
$txtDns2.Size = New-Object System.Drawing.Size(160, 24)
$txtDns2.Font = $script:FontUI
$txtDns2.Text = $DnsSecondary
$cardNet.Controls.Add($txtDns2)

# Bouton d'action colonne droite, comme la maquette (380,138 -> 280x38).
$btnApplyNet = New-ModernButton -Text 'Appliquer la configuration reseau' -X 372 -Y 150 -W 272 -H 38
$cardNet.Controls.Add($btnApplyNet)

# ================= CARTE 2 : DOMAINE ACTIVE DIRECTORY =================
$cardDom = New-Card -Title 'Domaine Active Directory' -X 24 -Y 250 -W 660 -H 264 -Parent $panelPc

$domLabels = @('Nom du poste', 'Domaine', 'Compte administrateur', 'Mot de passe')
$tb = @{}
for ($i = 0; $i -lt 4; $i++) {
    $x = 16 + ($i % 2) * 320
    $y = 42 + [Math]::Floor($i / 2) * 62
    New-TextLabel -Text $domLabels[$i] -X $x -Y $y -W 300 -H 18 -Parent $cardDom | Out-Null
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x, ($y + 22))
    $t.Size = New-Object System.Drawing.Size(292, 24)
    $t.Font = $script:FontUI
    $tb[$i] = $t
    $cardDom.Controls.Add($t)
}
if ($ComputerName) { $tb[0].Text = $ComputerName } else { $tb[0].Text = $env:COMPUTERNAME }
$tb[1].Text = $DomainName
$tb[2].Text = $DomainUser
$tb[3].Text = $DomainPassword
$tb[3].UseSystemPasswordChar = $true

$chkSim = New-Object System.Windows.Forms.CheckBox
$chkSim.Text = 'Mode simulation (aucune modification)'
$chkSim.Location = New-Object System.Drawing.Point(16, 168)
$chkSim.Size = New-Object System.Drawing.Size(340, 22)
$chkSim.Font = $script:FontUI
$chkSim.Checked = [bool]$DryRun
$chkSim.BackColor = $script:C_Card
$cardDom.Controls.Add($chkSim)

New-TextLabel -Text 'Le redemarrage est reporte : redemarrez le poste quand vous etes pret.' -X 16 -Y 194 -W 620 -H 18 -Font $script:FontMini -Fore $script:C_Muted -Parent $cardDom | Out-Null
$btnJoin = New-ModernButton -Text 'Renommer et joindre le domaine' -X 16 -Y 214 -W 320 -H 38 -Fill ([System.Drawing.Color]::FromArgb(23, 125, 95)) -Hover ([System.Drawing.Color]::FromArgb(28, 148, 114))
$cardDom.Controls.Add($btnJoin)

# ================= CARTE 3 : VERIFICATIONS ET PROTECTIONS =================
#   Une seule carte compacte : trois lignes d'etat (lecture seule) et deux
#   boutons secondaires. La desactivation des protections est AUTOMATIQUE
#   avant chaque installation (moteur : Disable-PcInstallProtections) ;
#   ici on ne propose que la reactivation manuelle apres deploiement.
$cardSys = New-Card -Title 'Verifications et protections' -X 24 -Y 530 -W 660 -H 150 -Parent $panelPc

$lblChkDomain = New-TextLabel -Text 'Jonction AD : non verifiee' -X 16 -Y 42 -W 628 -H 18 -Parent $cardSys
$lblChkDns = New-TextLabel -Text 'Connectivite DNS : non verifiee' -X 16 -Y 64 -W 628 -H 18 -Parent $cardSys
$lblProtState = New-TextLabel -Text 'Protections : non verifiees' -X 16 -Y 86 -W 628 -H 18 -Parent $cardSys

$btnPreChecks = New-SecondaryButton -Text 'Verifier' -X 16 -Y 112 -W 100 -H 26 -Font $script:FontMini
$cardSys.Controls.Add($btnPreChecks)
$btnRestore = New-SecondaryButton -Text 'Reactiver les protections' -X 126 -Y 112 -W 190 -H 26 -Font $script:FontMini
$cardSys.Controls.Add($btnRestore)
New-TextLabel -Text 'Se coupent automatiquement avant chaque installation.' -X 326 -Y 116 -W 320 -H 16 -Font $script:FontMini -Fore $script:C_Muted -Parent $cardSys | Out-Null

# ================= JOURNAL =================
$pcLog = New-LogCard -X 24 -Y 700 -W 660 -H 140 -Title "JOURNAL D'EXECUTION - CONFIGURATION PC" -Parent $panelPc

# ================= HELPERS DE LA VUE =================
function Write-PcLog {
    param([string]$Message, [string]$Level = 'INFO')
    Write-UiLog -Box $pcLog.Box -Message $Message -Level $Level
    Set-Status $Message
}

function Set-PcState {
    param([bool]$Running, [string]$Status, [string]$Detail = '')
    foreach ($b in @($btnApplyNet, $btnJoin, $btnRefreshAdapters, $btnPreChecks, $btnRestore)) { if ($b) { $b.Enabled = (-not $Running) } }
    if ($Status) { Set-Status $Status }
}

# --- Liste et selection des cartes reseau ---
function Update-AdapterList {
    $cmbAdapter.Items.Clear()
    foreach ($a in @(Get-PcAdapters)) {
        [void]$cmbAdapter.Items.Add(("{0}  ({1})  -  {2}" -f $a.Name, $a.Status, $a.Index))
    }
    if ($cmbAdapter.Items.Count -gt 0) {
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

# --- Controles prealables (lecture seule) : jonction AD + DNS ---
function Invoke-PcPreChecks {
    $st = Get-PcDomainStatus
    if ($st.Error) {
        $lblChkDomain.Text = ("Jonction AD : lecture impossible ({0})" -f $st.Error)
        $lblChkDomain.ForeColor = $script:C_Red
        Write-PcLog ("Jonction AD : lecture impossible ({0})" -f $st.Error) 'ATTENTION'
    } elseif ($st.Joined) {
        $lblChkDomain.Text = ("Jonction AD : poste '{0}' deja membre du domaine '{1}'" -f $st.Name, $st.Domain)
        $lblChkDomain.ForeColor = $script:C_Green
        Write-PcLog ("Jonction AD verifiee : '{0}' membre de '{1}'." -f $st.Name, $st.Domain) 'OK'
    } else {
        $lblChkDomain.Text = ("Jonction AD : poste '{0}' non joint (workgroup)" -f $st.Name)
        $lblChkDomain.ForeColor = $script:C_Amber
        Write-PcLog ("Jonction AD : '{0}' n'est pas membre d'un domaine." -f $st.Name) 'ATTENTION'
    }

    $dns = Test-PcDnsConnectivity -Servers @($txtDns1.Text, $txtDns2.Text) -TestName $tb[1].Text
    if ($dns.Results.Count -eq 0) {
        $lblChkDns.Text = 'Connectivite DNS : aucun serveur indique'
        $lblChkDns.ForeColor = $script:C_Amber
        Write-PcLog 'Controle DNS : aucun serveur indique.' 'ATTENTION'
        return
    }
    $parts = @($dns.Results | ForEach-Object { ("{0} : {1} ({2} ms)" -f $_.Server, $_.Detail, $_.Ms) })
    $lblChkDns.Text = ("DNS : {0}" -f ($parts -join '   |   '))
    if ($dns.Ok) {
        $lblChkDns.ForeColor = $script:C_Green
        Write-PcLog ("Connectivite DNS verifiee : {0}." -f ($parts -join ' ; ')) 'OK'
    } else {
        $lblChkDns.ForeColor = $script:C_Red
        Write-PcLog ("Connectivite DNS en echec : {0}." -f ($parts -join ' ; ')) 'ERREUR'
    }

    # Ligne protections : pure information, pas de journal (evite le bruit).
    $prot = Get-PcProtectionsState
    $dTxt = if ($null -eq $prot.DefenderOn) { 'Defender : illisible (antivirus tiers ?)' }
            elseif ($prot.DefenderOn) { 'Defender : actif' }
            else { 'Defender : arrete' }
    $fTxt = if ($prot.FirewallOn.Count) { 'Pare-feu : actif (' + ($prot.FirewallOn -join ', ') + ')' }
            else { 'Pare-feu : arrete' }
    $lblProtState.Text = ("Protections : {0}   |   {1}" -f $dTxt, $fTxt)
    $allOff = (($null -eq $prot.DefenderOn) -or (-not $prot.DefenderOn)) -and (-not $prot.FirewallOn.Count)
    $lblProtState.ForeColor = if ($allOff) { $script:C_Green } else { $script:C_Amber }
}

$btnPreChecks.Add_Click({ Invoke-PcPreChecks })

# --- Reactivation manuelle (la desactivation, elle, est automatique) ---
$btnRestore.Add_Click({
    Set-PcState -Running $true -Status "Reactivation des protections en cours"
    try {
        $r = Enable-PcProtections -Simulate:$DryRun -Log { param($m, $l) Write-PcLog $m $l }
        Invoke-PcPreChecks
        if ($DryRun) {
            Set-PcState -Running $false -Status "Simulation de reactivation terminee"
        } elseif ($r.Ok) {
            Set-PcState -Running $false -Status "Protections reactivees"
            Show-Dialog "Defender et le pare-feu Windows sont reactivees." "Protections systeme" 'Information'
        } else {
            Set-PcState -Running $false -Status "Reactivation partielle"
            Show-Dialog "Reactivation incomplete : voir le journal." "Protections systeme" 'Warning'
        }
    }
    catch {
        Write-PcLog "Erreur : $($_.Exception.Message)" 'ERREUR'
        Set-PcState -Running $false -Status "Echec de la reactivation"
        Show-Dialog $_.Exception.Message "Erreur protections" 'Error'
    }
})
$btnRefreshAdapters.Add_Click({ Update-AdapterList; Write-PcLog "Liste des cartes reseau actualisee." 'INFO' })

# ================= ACTION 1 : RESEAU (IPv6 + DNS) =================
$btnApplyNet.Add_Click({
    $adapter = Get-SelectedAdapterName
    $simulate = $chkSim.Checked
    Set-PcState -Running $true -Status "Configuration reseau en cours"
    Write-PcLog "==============================================="
    Write-PcLog "Configuration reseau - carte '$adapter'$(if ($simulate) { '  [MODE SIMULATION]' })"
    Write-PcLog "==============================================="
    Invoke-PcPreChecks   # controles prealables automatiques (jonction AD + DNS)
    try {
        Set-AdapterNetwork -AdapterName $adapter `
                           -DnsPrimary $txtDns1.Text -DnsSecondary $txtDns2.Text `
                           -DisableIPv6:$chkIPv6.Checked -ValidateUponExit:$chkValidate.Checked `
                           -Simulate:$simulate -Log { param($m, $l) Write-PcLog $m $l } | Out-Null
        if ($simulate) {
            Set-PcState -Running $false -Status "Simulation reseau terminee"
            Write-PcLog "Aucune modification appliquee (mode simulation)." 'ATTENTION'
        } else {
            Set-PcState -Running $false -Status "Reseau configure"
            Write-PcLog ("IPv6 desactive : {0} | DNS : {1}, {2}" -f $chkIPv6.Checked, $txtDns1.Text, $txtDns2.Text) 'OK'
        }
        Show-Dialog ("Etape 1 - Configuration reseau`r`n`r`nCarte : {0}`r`nIPv6 desactive : {1}`r`nDNS prefere : {2}`r`nDNS auxiliaire : {3}`r`n`r`n{4}" -f $adapter, $chkIPv6.Checked, $txtDns1.Text, $txtDns2.Text, $(if ($simulate) { 'Mode simulation : rien n a ete applique.' } else { 'La configuration a ete appliquee.' })) "Configuration reseau" 'Information'
    }
    catch {
        Write-PcLog "Erreur : $($_.Exception.Message)" 'ERREUR'
        Set-PcState -Running $false -Status "Echec de la configuration reseau"
        Show-Dialog $_.Exception.Message "Erreur reseau" 'Error'
    }
})

# ================= ACTION 2 : RENOMMAGE + JONCTION AU DOMAINE =================
$btnJoin.Add_Click({
    $simulate = $chkSim.Checked
    Set-PcState -Running $true -Status "Jonction au domaine en cours"
    Write-PcLog "==============================================="
    Write-PcLog "Renommage et jonction au domaine$(if ($simulate) { '  [MODE SIMULATION]' })"
    Write-PcLog "==============================================="
    Invoke-PcPreChecks   # controles prealables automatiques (jonction AD + DNS)
    Disable-PcInstallProtections -Simulate:($simulate -or $AutoTest) -Log { param($m, $l) Write-PcLog $m $l }
    try {
        Invoke-PcDomainJoin -ComputerName $tb[0].Text -DomainName $tb[1].Text `
                            -DomainUser $tb[2].Text -DomainPassword $tb[3].Text `
                            -Simulate:$simulate -Log { param($m, $l) Write-PcLog $m $l } | Out-Null
        if ($simulate) {
            Set-PcState -Running $false -Status "Simulation domaine terminee"
            Write-PcLog "Aucune modification appliquee (mode simulation)." 'ATTENTION'
        } else {
            Set-PcState -Running $false -Status "Poste joint au domaine"
            Write-PcLog ("{0} est membre de {1} - redemarrage requis (reporte)." -f $tb[0].Text, $tb[1].Text) 'OK'
        }
        Show-Dialog ("Etape 2 - Integration Active Directory`r`n`r`nNom du poste : {0}`r`nDomaine : {1}`r`nCompte : {2}`r`n`r`n{3}" -f $tb[0].Text, $tb[1].Text, $tb[2].Text, $(if ($simulate) { 'Mode simulation : rien n a ete applique.' } else { 'Le poste est joint au domaine. Redemarrez le PC pour finaliser.' })) "Integration au domaine" 'Information'
    }
    catch {
        Write-PcLog "Erreur : $($_.Exception.Message)" 'ERREUR'
        Set-PcState -Running $false -Status "Echec de la jonction au domaine"
        Show-Dialog $_.Exception.Message "Erreur domaine" 'Error'
    }
})

# NOTE : la desactivation Defender + pare-feu n'est plus une action manuelle ;
# elle est declenchee automatiquement par Disable-PcInstallProtections avant
# chaque installation (vues 70-73) et avant la jonction au domaine ci-dessus.

# ================= INIT DU MODULE PC =================
Update-AdapterList
Invoke-PcPreChecks   # etat initial : jonction AD + connectivite DNS
Write-PcLog "Module pret. Carte detectee : $(Get-SelectedAdapterName)"
if ($chkSim.Checked) { Write-PcLog "Mode simulation actif : aucune modification ne sera appliquee." 'ATTENTION' }
Set-PcState -Running $false -Status "Pret"
