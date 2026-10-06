<#
==============================================================================
 PowerDraft / Terra - Assistant d'installation et de configuration
------------------------------------------------------------------------------
 Interface graphique (Windows Forms) pour l'installation, l'initialisation,
 la collecte d'identifiants systeme et la configuration des modules
 TerraMatch / TerraModeler / TerraScan.

 Etape 5 : liaison de licences via le client de licence officiel Bentley
            (import de fichiers .lic) - aucune activation hors licence.

 Execution : powershell -ExecutionPolicy Bypass -File .\PowerDraft-Setup-GUI.ps1
             (en tant qu'administrateur)
==============================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

#------------------------------------------------------------------------------
# Configuration par defaut (modifiable dans l'interface)
#------------------------------------------------------------------------------
$script:Cfg = [ordered]@{
    SetupExe        = 'I:\lidar\eng\versionPowerDraft CE\setup.exe'
    PtcSource       = 'I:\lidar\eng\versionPowerDraft CE\PTC_LAS.ptc'
    TscanDir        = 'C:\terra64\tscan'
    PowerDraftExe   = 'C:\Program Files\Bentley\PowerDraft\PowerDraft.exe'
    LicenseSource   = 'I:\lidar\licences_bentley'
    Silent          = $false
    ComputerId      = ''
}

#------------------------------------------------------------------------------
# Palette / etats
#------------------------------------------------------------------------------
$script:Color = @{
    PendingBg = [System.Drawing.Color]::FromArgb(241,243,245)
    PendingFg = [System.Drawing.Color]::FromArgb(73,80,87)
    RunBg     = [System.Drawing.Color]::FromArgb(255,243,205)
    RunFg     = [System.Drawing.Color]::FromArgb(133,101,4)
    DoneBg    = [System.Drawing.Color]::FromArgb(209,231,221)
    DoneFg    = [System.Drawing.Color]::FromArgb(15,81,50)
    ErrBg     = [System.Drawing.Color]::FromArgb(248,215,218)
    ErrFg     = [System.Drawing.Color]::FromArgb(132,32,39)
    Accent    = [System.Drawing.Color]::FromArgb(0,80,120)
    PanelBg   = [System.Drawing.Color]::FromArgb(248,249,250)
}

$script:Steps = @(
    @{ Id=1; Title='Securite & antivirus'
       Desc='Etat de la protection Windows, restauration des elements bloques' },
    @{ Id=2; Title='Initialisation PowerDraft'
       Desc='Lancement unique pour generer %LocalAppData%\Bentley\PowerDraft\10.0.0' },
    @{ Id=3; Title='Installation des modules Terra'
       Desc='TerraMatch / TerraModeler / TerraScan via setup.exe' },
    @{ Id=4; Title='Collecte systeme'
       Desc='Nom d''ordinateur et Computer id (option Copy for email)' },
    @{ Id=5; Title='Licences Bentley'
       Desc='Import des fichiers .lic via le client de licence officiel' },
    @{ Id=6; Title='Configuration finale'
       Desc='Copie de PTC_LAS.ptc vers C:\terra64\tscan et validation' }
)

$script:StepPanels = @{}
$script:StepBadges = @{}
$script:StepStates = @{}
$script:IsRunning  = $false

#------------------------------------------------------------------------------
# Helpers
#------------------------------------------------------------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Add-Log {
    param([string]$Text, [string]$Level = 'INFO')
    $stamp = (Get-Date).ToString('HH:mm:ss')
    $prefix = switch ($Level) {
        'OK'   { '[ OK ]' }
        'ERR'  { '[ERR ]' }
        'WARN' { '[WARN]' }
        default{ '[INFO]' }
    }
    if ($script:LogBox) {
        $script:LogBox.AppendText("$stamp $prefix $Text`r`n")
        $script:LogBox.SelectionStart = $script:LogBox.Text.Length
        $script:LogBox.ScrollToCaret()
    }
}

function Set-Step {
    param([int]$Index, [ValidateSet('pending','running','done','error')][string]$State,
          [string]$Detail = '')
    $script:StepStates[$Index] = $State
    $panel = $script:StepPanels[$Index]
    $badge = $script:StepBadges[$Index]

    switch ($State) {
        'running' {
            $panel.BackColor = $script:Color.RunBg
            $badge.ForeColor = $script:Color.RunFg
            $badge.Text = [char]0x25CF + ' EN COURS'
            if ($Detail) { $script:StepDetails[$Index].Text = $Detail }
        }
        'done' {
            $panel.BackColor = $script:Color.DoneBg
            $badge.ForeColor = $script:Color.DoneFg
            $badge.Text = [char]0x2713 + ' TERMINE'
            if ($Detail) { $script:StepDetails[$Index].Text = $Detail }
        }
        'error' {
            $panel.BackColor = $script:Color.ErrBg
            $badge.ForeColor = $script:Color.ErrFg
            $badge.Text = [char]0x2717 + ' ECHEC'
            if ($Detail) { $script:StepDetails[$Index].Text = $Detail }
        }
        default {
            $panel.BackColor = $script:Color.PendingBg
            $badge.ForeColor = $script:Color.PendingFg
            $badge.Text = [char]0x25CB + ' EN ATTENTE'
            if ($Detail) { $script:StepDetails[$Index].Text = $Detail }
        }
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Progress {
    param([int]$Value, [string]$Text)
    if ($script:ProgressBar) {
        $script:ProgressBar.Value = [Math]::Max(0,[Math]::Min(100,$Value))
        $script:ProgressLabel.Text = $Text
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-Buttons {
    param([bool]$Running)
    $script:BtnAll.Enabled   = -not $Running
    $script:BtnStep.Enabled  = -not $Running
    $script:BtnReset.Enabled = -not $Running
    $script:CfgPanel.Enabled = -not $Running
}

#------------------------------------------------------------------------------
# Etapes
#------------------------------------------------------------------------------
function Invoke-Step1 {
    Set-Step 1 'running' 'Analyse de la protection Windows...'
    Add-Log 'Etape 1 : verification de la protection Windows.'

    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $rt = if ($mp.RealTimeProtectionEnabled) { 'activee' } else { 'desactivee' }
        Add-Log "Defender temps reel : $rt" 'OK'

        if ($mp.RealTimeProtectionEnabled) {
            Add-Log 'Protection activee. Ajoutez une exclusion de dossier pour le' 'WARN'
            Add-Log 'repertoire d''installation (menus Security > Virus & threat' 'WARN'
            Add-Log 'protection > Exclusions) plutot que de desactiver la protection.' 'WARN'
        } else {
            Add-Log 'Protection desactivee : pensez a la reactiver apres installation.' 'WARN'
        }

        # Emplacement des elements bloques / quarantaine
        $q = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Quarantine'
        if (Test-Path $q) {
            $items = @(Get-ChildItem $q -Force -ErrorAction SilentlyContinue)
            Add-Log "Elements en quarantaine : $($items.Count)"
            if ($items.Count -gt 0) {
                Add-Log 'Restaurer manuellement via Windows Security > Protection' 'WARN'
                Add-Log 'contre les virus > historique > Restaurer.' 'WARN'
            }
        }

        $script:BtnSecurity.Visible = $true
        Set-Step 1 'done' 'Etat analyse - restauration via Windows Security'
        return $true
    } catch {
        Add-Log "Etat Defender indisponible : $_" 'WARN'
        Set-Step 1 'done' 'Analyse partielle'
        return $true
    }
}

function Invoke-Step2 {
    $exe = $script:Cfg.PowerDraftExe
    Set-Step 2 'running' 'Lancement unique de PowerDraft...'
    Add-Log "Etape 2 : initialisation de $exe"

    if (-not (Test-Path $exe)) {
        Add-Log "Executable introuvable : $exe" 'ERR'
        Set-Step 2 'error' 'PowerDraft.exe introuvable - verifiez le chemin'
        return $false
    }

    try {
        $p = Start-Process -FilePath $exe -PassThru
        Add-Log "Processe lance (PID $($p.Id))"
        Start-Sleep -Seconds 8

        if (-not $p.HasExited) {
            $p.CloseMainWindow() | Out-Null
            Start-Sleep -Seconds 2
            if (-not $p.HasExited) { $p.Kill() }
        }
        Add-Log 'Processe ferme.' 'OK'

        $target = Join-Path $env:LocalAppData 'Bentley\PowerDraft\10.0.0'
        for ($i=0; $i -lt 12; $i++) {
            if (Test-Path $target) {
                Add-Log "Arborescence generee : $target" 'OK'
                Set-Step 2 'done' 'Arborescence 10.0.0 presente'
                return $true
            }
            Start-Sleep -Seconds 5
        }

        Add-Log "Arborescence 10.0.0 non detectee : $target" 'WARN'
        Set-Step 2 'error' 'Dossier 10.0.0 absent apres initialisation'
        return $false
    } catch {
        Add-Log "Echec du lancement : $_" 'ERR'
        Set-Step 2 'error' 'Lancement impossible'
        return $false
    }
}

function Invoke-Step3 {
    $setup = $script:Cfg.SetupExe
    Set-Step 3 'running' 'Execution de setup.exe...'
    Add-Log "Etape 3 : installation depuis $setup"

    if (-not (Test-Path $setup)) {
        Add-Log "setup.exe introuvable : $setup" 'ERR'
        Set-Step 3 'error' 'Setup absent - verifiez le partage reseau'
        return $false
    }

    $mods = @('TerraMatch','TerraModeler','TerraScan')
    Add-Log ('Modules selectionnes : ' + ($mods -join ', '))

    try {
        $argsList = @()
        if ($script:Cfg.Silent) {
            $argsList = '/quiet'
            Add-Log 'Mode silencieux active.' 'WARN'
            Add-Log 'Verifiez que les trois modules sont bien installes ensuite.' 'WARN'
        }

        $p = Start-Process -FilePath $setup -ArgumentList $argsList -Wait -PassThru
        Add-Log "Code de retour : $($p.ExitCode)"

        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
            if ($p.ExitCode -eq 3010) { Add-Log 'Redemarrage requis.' 'WARN' }
            Set-Step 3 'done' 'Installation terminee'
            return $true
        } else {
            Set-Step 3 'error' "Echec de l'installation (code $($p.ExitCode))"
            return $false
        }
    } catch {
        Add-Log "Echec de l'installation : $_" 'ERR'
        Set-Step 3 'error' 'Erreur durant setup.exe'
        return $false
    }
}

function Invoke-Step4 {
    $exe = $script:Cfg.PowerDraftExe
    Set-Step 4 'running' 'Collecte du Computer id'
    Add-Log 'Etape 4 : collecte systeme.'

    Add-Log "Nom d'ordinateur : $env:COMPUTERNAME" 'OK'
    $script:Cfg.ComputerId = $script:TxtComputerId.Text.Trim()

    if (-not $script:Cfg.ComputerId) {
        Add-Log 'Computer id non saisi : renseignez-le pour la demande de licence.' 'WARN'
        Set-Step 4 'error' 'Computer id manquant'
        return $false
    }

    if (Test-Path $exe) {
        try {
            Start-Process -FilePath $exe | Out-Null
            Add-Log 'PowerDraft lance : use Tools > About > Copy for email.' 'OK'
        } catch {
            Add-Log "Lancement impossible : $_" 'WARN'
        }
    }

    Set-Step 4 'done' "ID : $($script:Cfg.ComputerId)"
    return $true
}

function Invoke-Step5 {
    $src = $script:Cfg.LicenseSource
    Set-Step 5 'running' 'Recherche des licences Bentley...'
    Add-Log 'Etape 5 : liaison de licences officielles.'

    $dest = Join-Path $env:ProgramData 'Bentley\Licenses'
    $found = 0

    if (Test-Path $src) {
        $lic = @(Get-ChildItem -Path $src -Filter *.lic -Recurse -ErrorAction SilentlyContinue)
        $found = $lic.Count
        if ($found -gt 0) {
            Add-Log "$found fichier(s) .lic detecte(s) dans $src" 'OK'
            try {
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                foreach ($f in $lic) {
                    Copy-Item $f.FullName -Destination $dest -Force
                    Add-Log "Copie : $($f.Name)" 'OK'
                }
            } catch {
                Add-Log "Copie impossible : $_" 'ERR'
                Set-Step 5 'error' 'Echec de la copie des .lic'
                return $false
            }
        } else {
            Add-Log "Aucun fichier .lic dans $src" 'WARN'
        }
    } else {
        Add-Log "Dossier de licences absent : $src" 'WARN'
    }

    Add-Log "Dossier de licences systeme : $dest"
    Add-Log 'Demandez le pret de licence a votre fournisseur Bentley en'
    Add-Log 'transmettant le Computer id de l''etape 4, puis redemarrez'
    Add-Log 'PowerDraft : la licence est detectee automatiquement.'
    Add-Log 'Emplacement : ' + $(if ($found -gt 0) { "$found licence(s) importee(s)" } else { 'en attente de licence' })
    Set-Step 5 'done' $(if ($found -gt 0) { "$found licence(s) importee(s)" } else { 'en attente de licence' })
    return $true
}

function Invoke-Step6 {
    $src = $script:Cfg.PtcSource
    $dir = $script:Cfg.TscanDir
    $dst = Join-Path $dir 'PTC_LAS.ptc'

    Set-Step 6 'running' 'Copie de PTC_LAS.ptc...'
    Add-Log "Etape 6 : $src -> $dst"

    if (-not (Test-Path $src)) {
        Add-Log "Fichier source introuvable : $src" 'ERR'
        Set-Step 6 'error' 'PTC_LAS.ptc absent'
        return $false
    }

    try {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Add-Log "Dossier cree : $dir" 'OK'
        }
        Copy-Item -Path $src -Destination $dst -Force
        Add-Log "Fichier copie : $dst" 'OK'

        if (Test-Path $dst) {
            $sz = (Get-Item $dst).Length
            Add-Log ("Taille : {0:N0} octets" -f $sz) 'OK'
        }

        $exe = $script:Cfg.PowerDraftExe
        if (Test-Path $exe) {
            Add-Log 'Lancement de PowerDraft pour le premier chargement du PTC.'
            Start-Process -FilePath $exe | Out-Null
            Add-Log 'Verifiez le chargement des classes, puis fermez l''application.' 'OK'
        }

        Set-Step 6 'done' 'PTC_LAS.ptc en place'
        return $true
    } catch {
        Add-Log "Echec de la configuration : $_" 'ERR'
        Set-Step 6 'error' 'Copie impossible'
        return $false
    }
}

#------------------------------------------------------------------------------
# Orchestration
#------------------------------------------------------------------------------
$script:Runner = @{
    1 = { Invoke-Step1 }
    2 = { Invoke-Step2 }
    3 = { Invoke-Step3 }
    4 = { Invoke-Step4 }
    5 = { Invoke-Step5 }
    6 = { Invoke-Step6 }
}

function Save-Config {
    $script:Cfg.SetupExe      = $script:TxtSetup.Text.Trim()
    $script:Cfg.PtcSource     = $script:TxtPtc.Text.Trim()
    $script:Cfg.TscanDir      = $script:TxtTscan.Text.Trim()
    $script:Cfg.PowerDraftExe = $script:TxtPd.Text.Trim()
    $script:Cfg.LicenseSource = $script:TxtLic.Text.Trim()
    $script:Cfg.Silent        = $script:ChkSilent.Checked
}

function Invoke-SingleStep {
    param([int]$Index)
    if ($script:IsRunning) { return }
    Save-Config
    $script:IsRunning = $true
    Update-Buttons $true
    Set-Progress ((($Index - 1) / 6) * 100) "Etape $Index / 6 : $($script:Steps[$Index-1].Title)"
    try {
        & $script:Runner[$Index] | Out-Null
        Set-Progress (($Index / 6) * 100) "Etape $Index terminee"
    } catch {
        Add-Log "Exception etape ${Index}: $_" 'ERR'
        Set-Step $Index 'error' $_.Exception.Message
    }
    $script:IsRunning = $false
    Update-Buttons $false
}

function Invoke-AllSteps {
    if ($script:IsRunning) { return }
    Save-Config
    $script:IsRunning = $true
    Update-Buttons $true

    if (-not (Test-Admin)) {
        Add-Log 'Privilèges administrateur absents : etape 3 probablement bloquee.' 'WARN'
    }

    for ($i = 1; $i -le 6; $i++) {
        $name = $script:Steps[$i-1].Title
        Set-Progress ((($i - 1) / 6) * 100) "Etape $i / 6 : $name"
        $ok = $false
        try {
            $ok = & $script:Runner[$i]
        } catch {
            Add-Log "Exception etape ${i}: $_" 'ERR'
            Set-Step $i 'error' $_.Exception.Message
        }
        if (-not $ok) {
            Add-Log "Etape $i non aboutie : execution arretee." 'WARN'
            Set-Progress (($i / 6) * 100) "Arret a l'etape $i"
            $script:IsRunning = $false
            Update-Buttons $false
            return
        }
        Start-Sleep -Milliseconds 400
    }

    Set-Progress 100 'Procedure terminee'
    Add-Log 'Procedure terminee.' 'OK'
    $script:IsRunning = $false
    Update-Buttons $false
}

function Reset-Steps {
    for ($i = 1; $i -le 6; $i++) { Set-Step $i 'pending' '' }
    Set-Progress 0 'Pret'
    $script:LogBox.Clear()
    Add-Log 'Pret. Renseignez les chemins puis lancez la procedure.'
}

#------------------------------------------------------------------------------
# Construction de l'interface
#------------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text         = 'PowerDraft / Terra - Installation et configuration'
$form.Size         = New-Object System.Drawing.Size(1120,760)
$form.StartPosition= 'CenterScreen'
$form.BackColor    = $script:Color.PanelBg
$form.Font         = New-Object System.Drawing.Font('Segoe UI',9)
$form.MinimizeBox  = $false

# --- En-tete ---
$header = New-Object System.Windows.Forms.Panel
$header.Dock      = 'Top'
$header.Height    = 74
$header.BackColor = $script:Color.Accent
$form.Controls.Add($header)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = 'Bentley PowerDraft - Modules Terra'
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.Font      = New-Object System.Drawing.Font('Segoe UI Semibold',15)
$lblTitle.AutoSize  = $true
$lblTitle.Location  = New-Object System.Drawing.Point(20,14)
$header.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text      = 'Assistant d''installation, de collecte d''identifiants et de configuration'
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(190,215,232)
$lblSub.AutoSize  = $true
$lblSub.Location  = New-Object System.Drawing.Point(22,45)
$header.Controls.Add($lblSub)

$lblAdmin = New-Object System.Windows.Forms.Label
$lblAdmin.AutoSize = $true
$lblAdmin.Font     = New-Object System.Drawing.Font('Segoe UI Semibold',9)
$lblAdmin.Location = New-Object System.Drawing.Point(880,28)
if (Test-Admin) {
    $lblAdmin.Text      = 'Administrateur'
    $lblAdmin.ForeColor = [System.Drawing.Color]::FromArgb(150,230,180)
} else {
    $lblAdmin.Text      = 'Droits insuffisants'
    $lblAdmin.ForeColor = [System.Drawing.Color]::FromArgb(255,190,120)
}
$header.Controls.Add($lblAdmin)

# --- Corps : colonne etapes + panneau config ---
$body = New-Object System.Windows.Forms.Panel
$body.Dock   = 'Fill'
$body.Padding = New-Object System.Windows.Forms.Padding(14)
$form.Controls.Add($body)

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock       = 'Fill'
$split.FixedPanel = 'Panel1'
$split.SplitterWidth = 12
$body.Controls.Add($split)

# --- Colonne gauche : les etapes ---
$leftTitle = New-Object System.Windows.Forms.Label
$leftTitle.Text = 'PROCEDURE'
$leftTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)
$leftTitle.AutoSize = $true
$leftTitle.Location = New-Object System.Drawing.Point(0,0)
$split.Panel1.Controls.Add($leftTitle)

$flow = New-Object System.Windows.Forms.FlowLayoutPanel
$flow.Dock       = 'Top'
$flow.FlowDirection = 'TopDown'
$flow.WrapContents = $false
$flow.AutoSize   = $true
$flow.Location  = New-Object System.Drawing.Point(0,24)
$split.Panel1.Controls.Add($flow)

foreach ($s in $script:Steps) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Width      = 400
    $card.Height     = 62
    $card.Margin     = New-Object System.Windows.Forms.Padding(0,0,0,8)
    $card.BackColor  = $script:Color.PendingBg
    $card.Cursor     = [System.Windows.Forms.Cursors]::Hand

    $lblT = New-Object System.Windows.Forms.Label
    $lblT.Text     = "$($s.Id). $($s.Title)"
    $lblT.Font     = New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $lblT.AutoSize = $true
    $lblT.Location = New-Object System.Drawing.Point(12,9)
    $card.Controls.Add($lblT)

    $lblD = New-Object System.Windows.Forms.Label
    $lblD.Text     = $s.Desc
    $lblD.Font     = New-Object System.Drawing.Font('Segoe UI',8)
    $lblD.ForeColor= [System.Drawing.Color]::FromArgb(108,117,125)
    $lblD.AutoSize = $true
    $lblD.Location = New-Object System.Drawing.Point(12,29)
    $card.Controls.Add($lblD)

    $lblDetail = New-Object System.Windows.Forms.Label
    $lblDetail.Text     = ''
    $lblDetail.Font     = New-Object System.Drawing.Font('Segoe UI',8)
    $lblDetail.ForeColor= [System.Drawing.Color]::FromArgb(108,117,125)
    $lblDetail.AutoSize = $true
    $lblDetail.Location = New-Object System.Drawing.Point(12,44)
    $card.Controls.Add($lblDetail)

    $lblBadge = New-Object System.Windows.Forms.Label
    $lblBadge.Text     = [char]0x25CB + ' EN ATTENTE'
    $lblBadge.Font     = New-Object System.Drawing.Font('Segoe UI Semibold',8)
    $lblBadge.ForeColor= $script:Color.PendingFg
    $lblBadge.AutoSize = $true
    $lblBadge.Anchor   = 'Top,Right'
    $lblBadge.Location = New-Object System.Drawing.Point(310,10)
    $card.Controls.Add($lblBadge)

    $card.Add_MouseClick({
        if (-not $script:IsRunning) {
            $idx = $this.Tag
            Invoke-SingleStep ([int]$idx)
        }
    }.GetNewClosure())

    $card.Tag = $s.Id
    $flow.Controls.Add($card)

    $script:StepPanels[$s.Id] = $card
    $script:StepBadges[$s.Id] = $lblBadge
    $script:StepStates[$s.Id] = 'pending'
    $script:StepDetails[$s.Id] = $lblDetail
}

# --- Colonne droite : configuration ---
$cfg = New-Object System.Windows.Forms.Panel
$cfg.Dock   = 'Top'
$cfg.Height = 236
$cfg.AutoScroll = $true
$split.Panel2.Controls.Add($cfg)

function New-Field {
    param([string]$Key,[string]$Label,[string]$Value,[int]$Top)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Label
    $l.AutoSize = $true
    $l.Location = New-Object System.Drawing.Point(0,$Top)
    $l.Font = New-Object System.Drawing.Font('Segoe UI',8)
    $l.ForeColor = [System.Drawing.Color]::FromArgb(73,80,87)
    $cfg.Controls.Add($l)

    $t = New-Object System.Windows.Forms.TextBox
    $t.Text = $Value
    $t.Location = New-Object System.Drawing.Point(0,($Top+16))
    $t.Size = New-Object System.Drawing.Size(560,23)
    $cfg.Controls.Add($t)
    return $t
}

$script:TxtSetup = New-Field 'setup'  'setup.exe (installation des modules)' $script:Cfg.SetupExe 8
$script:TxtPtc    = New-Field 'ptc'    'PTC_LAS.ptc (fichier de configuration)' $script:Cfg.PtcSource 56
$script:TxtTscan  = New-Field 'tscan'  'Dossier cible TerraScan' $script:Cfg.TscanDir 104
$script:TxtPd     = New-Field 'pd'     'PowerDraft.exe' $script:Cfg.PowerDraftExe 152
$script:TxtLic    = New-Field 'lic'    'Dossier des licences Bentley (.lic)' $script:Cfg.LicenseSource 200

$script:ChkSilent = New-Object System.Windows.Forms.CheckBox
$script:ChkSilent.Text = 'Installation silencieuse (aucune selection de modules a l''ecran)'
$script:ChkSilent.AutoSize = $true
$script:ChkSilent.Location = New-Object System.Drawing.Point(0,248)
$script:ChkSilent.Font = New-Object System.Drawing.Font('Segoe UI',8)
$script:ChkSilent.ForeColor = [System.Drawing.Color]::FromArgb(133,101,4)
$cfg.Controls.Add($script:ChkSilent)

$lblId = New-Object System.Windows.Forms.Label
$lblId.Text = 'Computer id (colle via Tools > About > Copy for email)'
$lblId.AutoSize = $true
$lblId.Location = New-Object System.Drawing.Point(0,272)
$lblId.Font = New-Object System.Drawing.Font('Segoe UI',8)
$cfg.Controls.Add($lblId)

$script:TxtComputerId = New-Object System.Windows.Forms.TextBox
$script:TxtComputerId.Location = New-Object System.Drawing.Point(0,288)
$script:TxtComputerId.Size = New-Object System.Drawing.Size(560,23)
$cfg.Controls.Add($script:TxtComputerId)

$script:BtnSecurity = New-Object System.Windows.Forms.Button
$script:BtnSecurity.Text = 'Ouvrir Windows Security'
$script:BtnSecurity.Size = New-Object System.Drawing.Size(190,28)
$script:BtnSecurity.Location = New-Object System.Drawing.Point(0,320)
$script:BtnSecurity.Visible = $false
$script:BtnSecurity.Add_Click({ Start-Process 'ms-settings:windowsdefender' })
$cfg.Controls.Add($script:BtnSecurity)

$script:CfgPanel = $cfg

# --- Journal ---
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline  = $true
$logBox.ReadOnly   = $true
$logBox.ScrollBars = 'Vertical'
$logBox.Dock       = 'Bottom'
$logBox.Height     = 180
$logBox.BackColor  = [System.Drawing.Color]::FromArgb(30,32,36)
$logBox.ForeColor  = [System.Drawing.Color]::FromArgb(212,216,220)
$logBox.Font       = New-Object System.Drawing.Font('Consolas',9)
$logBox.BorderStyle= 'FixedSingle'
$script:LogBox = $logBox
$split.Panel2.Controls.Add($logBox)

# --- Barre de progression ---
$progPanel = New-Object System.Windows.Forms.Panel
$progPanel.Dock   = 'Bottom'
$progPanel.Height = 56
$progPanel.Padding = New-Object System.Windows.Forms.Padding(0,8,0,0)
$split.Panel2.Controls.Add($progPanel)

$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Dock   = 'Top'
$script:ProgressBar.Height = 18
$progPanel.Controls.Add($script:ProgressBar)

$script:ProgressLabel = New-Object System.Windows.Forms.Label
$script:ProgressLabel.Dock      = 'Top'
$script:ProgressLabel.Height   = 20
$script:ProgressLabel.Text     = 'Pret'
$script:ProgressLabel.Font     = New-Object System.Drawing.Font('Segoe UI',8)
$script:ProgressLabel.ForeColor= [System.Drawing.Color]::FromArgb(73,80,87)
$progPanel.Controls.Add($script:ProgressLabel)

# --- Boutons ---
$btnPanel = New-Object System.Windows.Forms.Panel
$btnPanel.Dock   = 'Top'
$btnPanel.Height = 46
$btnPanel.Padding = New-Object System.Windows.Forms.Padding(0,6,0,0)
$split.Panel2.Controls.Add($btnPanel)

function New-Btn {
    param([string]$Text,[int]$X,[int]$W,[string]$Color)
    $b = New-Object System.Windows.Forms.Button
    $b.Text     = $Text
    $b.Location = New-Object System.Drawing.Point($X,4)
    $b.Size     = New-Object System.Drawing.Size($W,30)
    $b.FlatStyle= 'Flat'
    $b.BackColor= [System.Drawing.ColorTranslator]::FromHtml($Color)
    $b.ForeColor= [System.Drawing.Color]::White
    $b.Font     = New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $b.FlatAppearance.BorderSize = 0
    return $b
}

$script:BtnAll   = New-Btn 'Lancer la procedure' 0   165 '#00723f'
$script:BtnStep  = New-Btn 'Executer l''etape selectionnee' 173 235 '#005a80'
$script:BtnReset = New-Btn 'Reinitialiser' 416 130 '#5a5f66'
$script:BtnSave  = New-Btn 'Exporter le journal' 554 165 '#343a40'

$script:BtnAll.Add_Click({ Invoke-AllSteps })
$script:BtnStep.Add_Click({
    if (-not $script:IsRunning) {
        $done = @()
        foreach ($k in 1..6) { if ($script:StepStates[$k] -ne 'pending') { $done += $k } }
        $next = if ($done.Count -eq 0) { 1 } else { ($done | Measure-Object -Maximum).Maximum + 1 }
        if ($next -gt 6) { $next = 1 }
        Invoke-SingleStep $next
    }
})
$script:BtnReset.Add_Click({ Reset-Steps })
$script:BtnSave.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'Journal (*.log)|*.log|Texte (*.txt)|*.txt'
    $dlg.FileName = 'PowerDraft-install-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.log'
    if ($dlg.ShowDialog() -eq 'OK') {
        [System.IO.File]::WriteAllText($dlg.FileName, $script:LogBox.Text)
        Add-Log "Journal exporte : $($dlg.FileName)" 'OK'
    }
})

foreach ($b in @($script:BtnAll,$script:BtnStep,$script:BtnReset,$script:BtnSave)) {
    $btnPanel.Controls.Add($b)
}

$form.AcceptButton = $script:BtnAll

# --- Initialisation de l'affichage ---
$split.Panel1Width = 420
$split.Panel2.Padding = New-Object System.Windows.Forms.Padding(0,0,0,0)
$form.Add_Shown({
    Reset-Steps
    if (-not (Test-Admin)) {
        Add-Log 'Executez PowerShell en administrateur pour l''installation.' 'WARN'
    }
    if (-not (Test-Path 'I:\')) {
        Add-Log 'Lecteur I: injoignable : les partages reseau doivent etre montes.' 'WARN'
    }
    Add-Log 'Chemin Bentley Shared : ' + $(if (Test-Path (Join-Path $env:ProgramFiles 'Bentley')) { 'trouve' } else { 'absent' })
})

[void]$form.ShowDialog()
