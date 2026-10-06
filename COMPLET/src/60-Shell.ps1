# ==================================================================
# src\60-Shell.ps1  -  Coque principale Neo-Carbon Sarytany
#   Fenetre standard (cadre OS, 1100x720, min 980x640), bandeau de
#   titre sombre 52px (nom + licence a droite), barre laterale
#   dockee 230px (5 vues, ordre : Configuration PC, Bentley, Suite,
#   Sintegra, Terra), zone de contenu Dock=Fill, pied de page 32px.
#   Les vues creent leurs panneaux (70-73 via New-RunView, 80 via
#   New-Card) et les enregistrent avec Add-ViewPanel.
# Design : maquette Interface-Sarytany - docks, pas d'absolu global.
# Depend de : src\40-Theme.ps1, src\50-Widgets.ps1.
# Variabilise : $StartView (Pc|Bentley|Suite|Sintegra|Terra).
# ==================================================================

# Cotes de mise en page Neo-Carbon Sarytany
$script:Layout = @{
    FormW  = 1100
    FormH  = 720
    MinW   = 980
    MinH   = 640
    HeadH  = 52         # bandeau de titre interne
    SideW  = 230        # barre laterale
    FootH  = 32         # pied de page
}

# ================= FENETRE =================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Assistant Sarytany - Neo-Carbon v2.0'
$form.ClientSize = New-Object System.Drawing.Size($Layout.FormW, $Layout.FormH)
$form.MinimumSize = New-Object System.Drawing.Size($Layout.MinW, $Layout.MinH)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $script:C_Bg
$form.Font = $script:FontUI
$appIcon = Get-AppIcon
if ($appIcon) { $form.Icon = $appIcon; $form.ShowIcon = $true }
Set-DoubleBuffer $form

# ================= ZONES DOCKEES =================
# Ordre d'ajout : contenu (Fill) d'abord, puis les bords ; la mise en
# place dockee traite les controles du dernier ajoute au premier,
# le Fill recoit donc l'espace restant.
$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
Set-DoubleBuffer $content

$side = New-Object System.Windows.Forms.Panel
$side.Dock = 'Left'
$side.Width = $Layout.SideW
$side.BackColor = $script:C_Sidebar
$side.Padding = New-Object System.Windows.Forms.Padding(12, 16, 12, 0)

$head = New-Object System.Windows.Forms.Panel
$head.Dock = 'Top'
$head.Height = $Layout.HeadH
$head.BackColor = $script:C_Title
Set-DoubleBuffer $head

$foot = New-StatusBar -W $Layout.FormW -H $Layout.FootH
$foot.Dock = 'Bottom'
$script:StatusBarRef = $foot

$form.Controls.AddRange(@($content, $side, $head, $foot))

# ================= BANDEAU DE TITRE =================
$sep = [string][char]0x00B7   # point median : 'Assistant Sarytany  ·  Neo-Carbon v2.0'
New-TextLabel -Text ("Assistant Sarytany  {0}  Neo-Carbon v2.0" -f $sep) -X 20 -Y 14 -W 560 -H 24 -Font $script:FontTitle -Fore ([System.Drawing.Color]::White) -Parent $head | Out-Null

$script:LblLicense = New-TextLabel -Text 'Licence : -' -X 0 -Y 0 -W 190 -H 24 -Font $script:FontMini -Fore ([System.Drawing.Color]::FromArgb(110, 231, 183)) -Align 'Right'
$script:LblLicense.Dock = 'Right'
$head.Controls.Add($script:LblLicense)

# ================= VUES =====================
# Cle -> libelle de navigation (ordre = celui de la maquette).
$script:Views = [ordered]@{
    Pc       = 'Configuration PC'
    Bentley  = 'Deploiement Bentley'
    Suite    = 'Installation Suite'
    Sintegra = 'SintegraLidar'
    Terra    = 'Installation Terra'
}
$script:ViewPanels = @{}
$script:NavItems   = @{}

# Enregistre le panneau d'une vue dans la zone de contenu.
function Add-ViewPanel {
    param([string]$Key, [System.Windows.Forms.Panel]$Panel)
    if (-not $script:Views.Contains($Key)) { return }
    $script:ViewPanels[$Key] = $Panel
    $content.Controls.Add($Panel)
    $Panel.Visible = ($script:ActiveView -eq $Key)
}

# Active une vue : visibilite, surbrillance nav, pied de page.
function Show-View {
    param([string]$Key)
    if (-not $script:Views.Contains($Key)) { $Key = 'Pc' }
    $script:ActiveView = $Key
    foreach ($k in @($script:Views.Keys)) {
        $p = $script:ViewPanels[$k]
        if ($p) { $p.Visible = ($k -eq $Key) }
        $it = $script:NavItems[$k]
        if ($it) { $it.Tag.Active = ($k -eq $Key); Update-SidebarVisual $it }
    }
    $script:StatusBarRef.Tag.Left.Text = ('Vue : {0}' -f $script:Views[$Key])
    $script:StatusBarRef.Tag.State.Invalidate()
}

# ================= NAVIGATION LATERALE =================
$navHost = New-Object System.Windows.Forms.FlowLayoutPanel
$navHost.Dock = 'Top'
$navHost.AutoSize = $true
$navHost.FlowDirection = 'TopDown'
$navHost.WrapContents = $false
$navHost.BackColor = [System.Drawing.Color]::Transparent
foreach ($k in @($script:Views.Keys)) {
    $item = New-SidebarItem -Text $script:Views[$k] -Key $k -W ($Layout.SideW - 24)
    $item.Add_Click({ param($s, $e) Show-View $s.Tag.Key })
    $navHost.Controls.Add($item)
    $script:NavItems[$k] = $item
}
$side.Controls.Add($navHost)

# ================= COMPATIBILITE ANCIENNE =================
# Activate-View : ancien contrat (-Which / -Index) utilisait 1=Bentley,
# 2=Pc, 3=Suite, 4=Sintegra, 5=Terra. Active-Module : alias conserve pour
# l'AutoTest (90-App) et les appels internes.
function Activate-View {
    param(
        [ValidateSet('Bentley', 'Pc', 'Suite', 'Sintegra', 'Terra')]
        [string]$Which = 'Pc',
        [int]$Index = 0
    )
    if ($Index -gt 0) {
        $Which = switch ($Index) { 1 { 'Bentley' } 2 { 'Pc' } 3 { 'Suite' } 4 { 'Sintegra' } 5 { 'Terra' } default { $Which } }
    }
    Show-View $Which
}
New-Item -Path function:\Activate-Module -Value ${function:Activate-View} -Force | Out-Null
