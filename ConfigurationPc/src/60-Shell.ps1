# ==================================================================
# src\60-Shell.ps1  -  Coque de l'application
#   Fenetre principale (icone, barre de titre deplacee, bouton fermer),
#   barre d'onglets et creation des deux panneaux. Les contenus des
#   vues sont construits dans les modules 70 et 80.
# Depend de : src\40-Theme.ps1, src\50-Widgets.ps1.
# ==================================================================

# ================= FENETRE =================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Assistant Deploiement Bentley PowerDraft - Sarytany"
$form.ClientSize = New-Object System.Drawing.Size(760, 760)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.BackColor = $script:C_Bg
$form.Font = $script:FontUI
$appIcon = Get-AppIcon
if ($appIcon) { $form.Icon = $appIcon; $form.ShowIcon = $true }
Set-DoubleBuffer $form

# ================= BARRE DE TITRE =================
$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Dock = "Top"
$titleBar.Height = 62
$titleBar.BackColor = $script:C_Title
$form.Controls.Add($titleBar)

$brand = New-Object System.Windows.Forms.Panel
$brand.Location = New-Object System.Drawing.Point(20, 14)
$brand.Size = New-Object System.Drawing.Size(34, 34)
$brand.BackColor = $script:C_Accent
Set-RoundRegion $brand 9
$brand.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $pts = @(
        (New-Object System.Drawing.PointF(17, 7)),
        (New-Object System.Drawing.PointF(27, 17)),
        (New-Object System.Drawing.PointF(17, 27)),
        (New-Object System.Drawing.PointF(7, 17))
    )
    $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $g.FillPolygon($br, $pts)
    $br.Dispose()
})
$titleBar.Controls.Add($brand)

$lblTitle = New-TextLabel -Text "Bentley PowerDraft" -X 66 -Y 13 -W 420 -H 24 -Font $script:FontBig -Fore ([System.Drawing.Color]::White)
$titleBar.Controls.Add($lblTitle)
$lblSub = New-TextLabel -Text "Gestionnaire de configuration  -  Poste PC-002  -  Sarytany" -X 68 -Y 35 -W 520 -H 18 -Font $script:FontMini -Fore $script:C_TxtIn2
$titleBar.Controls.Add($lblSub)

$btnCloseBox = New-ModernButton -Text ([string][char]0x2715) -X 706 -Y 16 -W 32 -H 30 -Fill ([System.Drawing.Color]::FromArgb(45, 54, 68)) -Hover $script:C_Red -Font (New-Object System.Drawing.Font('Segoe UI', 10))
$titleBar.Controls.Add($btnCloseBox)

# Deplacement de la fenetre par la barre de titre
$script:DragStart = $null
$titleBar.Add_MouseDown({ $script:DragStart = $this.PointToScreen($e.Location) })
$titleBar.Add_MouseMove({
    if ($script:DragStart) {
        $f = [System.Windows.Forms.Form]::ActiveForm
        if ($f) { $f.Location = New-Object System.Drawing.Point(($e.X - $script:DragStart.X), ($e.Y - $script:DragStart.Y)) }
    }
})
$titleBar.Add_MouseUp({ $script:DragStart = $null })

# ================= BARRE D'ONGLETS =================
$contentTop = 106

$navBar = New-Object System.Windows.Forms.Panel
$navBar.Location = New-Object System.Drawing.Point(0, 62)
$navBar.Size = New-Object System.Drawing.Size(760, 44)
$navBar.BackColor = $script:C_Title
$form.Controls.Add($navBar)

$tabBentley = New-Tab -Text "Deploiement Bentley PowerDraft" -X 0 -W 380
$tabPc      = New-Tab -Text "Configuration PC" -X 380 -W 380
$navBar.Controls.Add($tabBentley)
$navBar.Controls.Add($tabPc)
$script:Tabs = @($tabBentley, $tabPc)

# ================= PANNEAUX DES VUES =================
$panelBentley = New-Object System.Windows.Forms.Panel
$panelBentley.Location = New-Object System.Drawing.Point(0, $contentTop)
$panelBentley.Size = New-Object System.Drawing.Size(760, ($form.ClientSize.Height - $contentTop))
$panelBentley.BackColor = $script:C_Bg
$form.Controls.Add($panelBentley)

$panelPc = New-Object System.Windows.Forms.Panel
$panelPc.Location = New-Object System.Drawing.Point(0, $contentTop)
$panelPc.Size = New-Object System.Drawing.Size(760, ($form.ClientSize.Height - $contentTop))
$panelPc.BackColor = $script:C_Bg
$panelPc.Visible = $false
$form.Controls.Add($panelPc)

# ================= NAVIGATION =================
function Activate-Module {
    param([string]$Which)
    $panelBentley.Visible = ($Which -eq 'Bentley')
    $panelPc.Visible = ($Which -eq 'Pc')
    foreach ($t in $script:Tabs) { $t.Tag.Active = $false; $t.Invalidate() }
    switch ($Which) {
        'Bentley' { $tabBentley.Tag.Active = $true; $tabBentley.Invalidate() }
        'Pc'      { $tabPc.Tag.Active = $true; $tabPc.Invalidate() }
        default   { $tabBentley.Tag.Active = $true; $tabBentley.Invalidate() }
    }
}

$tabBentley.Add_Click({ Activate-Module -Which 'Bentley' })
$tabPc.Add_Click({ Activate-Module -Which 'Pc' })
