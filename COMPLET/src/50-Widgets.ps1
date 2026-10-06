# ==================================================================
# src\50-Widgets.ps1  -  Controles reutilisables (generation Sarytany)
#   Gabarits du design Neo-Carbon Sarytany : cartes a titre gris,
#   boutons plats arrondis, items de navigation "pastille + libelle",
#   barre de statut (vue a gauche, horodatage a droite), carte de
#   statut (titre + detail + pastille pleine + barre de progression),
#   journal sombre, et le gabarit shared "New-RunView" :
#   carte statut / liste d'etapes / journal plein / barre d'actions.
#   Aucune connaissance metier : reutilisable tel quel.
# Depend de : src\40-Theme.ps1 (polices, palette, dessin).
# ==================================================================

# ================= DIALOGUE =================
function Show-Dialog {
    param([string]$Text, [string]$Title, [string]$Icon = 'Information')
    if ($NoDialogs) { Write-Out ("[{0}] {1}" -f $Title, ($Text -replace "`r`n", ' | ')) -ForegroundColor Cyan; return }
    $ico = [System.Windows.Forms.MessageBoxIcon]::$Icon
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $ico)
}

# ================= ESPACEUR (Dock=Top) =================
function New-Gap {
    param([int]$H = 12)
    $g = New-Object System.Windows.Forms.Panel
    $g.Dock = 'Top'
    $g.Height = $H
    $g.BackColor = $script:C_Bg
    return $g
}

# ================= PANNEAU ARRONDI =================
function New-RoundedPanel {
    param([int]$W, [int]$H, [int]$R = 12, [System.Drawing.Color]$Fill = $script:C_Card, [System.Windows.Forms.Control]$Parent = $null)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($W, $H)
    $panel.BackColor = $Fill
    $panel.Tag = @{ R = $R }
    Set-DoubleBuffer $panel
    Set-RoundRegion $panel $R
    $panel.Add_Resize({ Set-RoundRegion $this $this.Tag.R })
    $panel.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(226, 232, 240))
        Set-SmoothingMode $e.Graphics 'AntiAlias'
        $rp = Get-RoundedPath -W ($s.Width - 1) -H ($s.Height - 1) -R $s.Tag.R
        $e.Graphics.DrawPath($pen, $rp)
        $rp.Dispose()
        $pen.Dispose()
    })
    if ($Parent) { $Parent.Controls.Add($panel) }
    return $panel
}

# ================= LABEL =================
function New-TextLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 300, [int]$H = 20,
          [System.Drawing.Font]$Font = $script:FontUI,
          [System.Drawing.Color]$Fore = $script:C_Text,
          [string]$Align = 'Left',
          [System.Windows.Forms.Control]$Parent = $null)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($W, $H)
    $l.Font = $Font
    $l.ForeColor = $Fore
    $l.BackColor = [System.Drawing.Color]::Transparent
    switch ($Align) {
        'Center' { $l.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter }
        'Right'  { $l.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight }
        default  { $l.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft }
    }
    if ($Parent) { $Parent.Controls.Add($l) }
    return $l
}

# ================= CARTE (panneau blanc + titre gris) =================
function New-Card {
    param([string]$Title, [int]$X = 0, [int]$Y = 0, [int]$W = 660, [int]$H = 100,
          [System.Drawing.Color]$Fill = $script:C_Card, [System.Windows.Forms.Control]$Parent = $null)
    $card = New-RoundedPanel -W $W -H $H -R 12 -Fill $Fill -Parent $Parent
    $card.Location = New-Object System.Drawing.Point($X, $Y)
    if ($Title) {
        New-TextLabel -Text $Title -X 16 -Y 12 -W ($W - 32) -H 20 -Font $script:FontStep -Fore $script:C_Muted -Parent $card | Out-Null
    }
    return $card
}

# ================= BOUTON MODERNE =================
function New-ModernButton {
    param(
        [string]$Text, [int]$X, [int]$Y, [int]$W = 240, [int]$H = 38,
        [System.Drawing.Color]$Fill = $script:C_Accent,
        [System.Drawing.Color]$Hover = $script:C_AccentHi,
        [System.Drawing.Color]$Fore = [System.Drawing.Color]::White,
        [System.Drawing.Font]$Font = $script:FontSemB
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $Fill
    $b.Font = $Font
    $b.Text = ''
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.UseVisualStyleBackColor = $false
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $b.Tag = @{ Fill = $Fill; Hover = $Hover; Fore = $Fore; Text = $Text; Hot = $false }
    Set-DoubleBuffer $b
    $b.Add_Resize({
        try { Set-RoundRegion $this 8 } catch { }
    })
    try { Set-RoundRegion $b 8 } catch { }
    $b.Add_MouseEnter({ param($s, $e) $s.Tag.Hot = $true; $s.Invalidate() })
    $b.Add_MouseLeave({ param($s, $e) $s.Tag.Hot = $false; $s.Invalidate() })
    $b.Add_EnabledChanged({ param($s, $e) $s.Invalidate() })
    $b.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        Set-SmoothingMode $g 'AntiAlias'
        Set-TextRenderingHint $g 'AntiAliasGridFit'
        $t = $s.Tag
        if (-not $s.Enabled) {
            $fill = [System.Drawing.Color]::FromArgb(226, 232, 240)
            $fore = [System.Drawing.Color]::FromArgb(148, 163, 184)
        } else {
            $fill = if ($t.Hot) { $t.Hover } else { $t.Fill }
            $fore = $t.Fore
        }
        $br = New-Object System.Drawing.SolidBrush $fill
        $rp = Get-RoundedPath -W $s.Width -H $s.Height -R 8
        $g.FillPath($br, $rp)
        $rp.Dispose()
        $br.Dispose()
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'
        $sf.LineAlignment = 'Center'
        $tb = New-Object System.Drawing.SolidBrush $fore
        $g.DrawString($t.Text, $s.Font, $tb, (New-Object System.Drawing.RectangleF(0, 0, $s.Width, $s.Height)), $sf)
        $tb.Dispose()
        $sf.Dispose()
    })
    return $b
}

# ================= BOUTON SECONDAIRE (gris clair) =================
function New-SecondaryButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 120, [int]$H = 38, [System.Drawing.Font]$Font = $script:FontUI)
    return (New-ModernButton -Text $Text -X $X -Y $Y -W $W -H $H `
        -Fill ([System.Drawing.Color]::FromArgb(232, 237, 244)) `
        -Hover ([System.Drawing.Color]::FromArgb(214, 222, 232)) `
        -Fore $script:C_Text -Font $Font)
}

# ================= BOUTON TERNAIRE (annuler / quitter) =================
function New-GreyButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 120, [int]$H = 38)
    return (New-ModernButton -Text $Text -X $X -Y $Y -W $W -H $H `
        -Fill ([System.Drawing.Color]::FromArgb(226, 232, 240)) `
        -Hover ([System.Drawing.Color]::FromArgb(203, 213, 225)) `
        -Fore $script:C_Text)
}

# ================= ITEM DE NAVIGATION SIDEBAR =================
# Label arrondi "●  Nom" : fond accent quand actif, plus clair au survol.
function New-SidebarItem {
    param([string]$Text, [string]$Key, [int]$W = 206, [int]$H = 40)
    $b = New-Object System.Windows.Forms.Button
    $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $script:C_Sidebar
    $b.ForeColor = $script:C_Slate
    $b.Font = $script:FontSemB
    $b.Text = (([string][char]0x25CF) + '  ' + $Text)
    $b.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $b.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.UseVisualStyleBackColor = $false
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $b.Tag = @{ Key = $Key; Active = $false; Hot = $false }
    Set-DoubleBuffer $b
    try { Set-RoundRegion $b 8 } catch { }
    $b.Add_Resize({ try { Set-RoundRegion $this 8 } catch { } })
    $b.Add_MouseEnter({ param($s, $e) $s.Tag.Hot = $true; Update-SidebarVisual $s })
    $b.Add_MouseLeave({ param($s, $e) $s.Tag.Hot = $false; Update-SidebarVisual $s })
    return $b
}

function Update-SidebarVisual {
    param($Item)
    if ($Item.Tag.Active) {
        $Item.BackColor = $script:C_Accent
        $Item.ForeColor = [System.Drawing.Color]::White
    } elseif ($Item.Tag.Hot) {
        $Item.BackColor = $script:C_SidebarHover
        $Item.ForeColor = [System.Drawing.Color]::White
    } else {
        $Item.BackColor = $script:C_Sidebar
        $Item.ForeColor = $script:C_Slate
    }
}

# ================= BARRE DE STATUS =================
# Gauche : vue courante. Droite : "HH:mm:ss  message" (Set-Status).
function New-StatusBar {
    param([int]$W, [int]$H = 32, [System.Windows.Forms.Control]$Parent = $null)
    $bar = New-Object System.Windows.Forms.Panel
    $bar.Size = New-Object System.Drawing.Size($W, $H)
    $bar.BackColor = $script:C_StatusBar
    Set-DoubleBuffer $bar
    $bar.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(226, 232, 240))
        $g.DrawLine($pen, 0, 0, $s.Width, 0)
        $pen.Dispose()
    })
    $lblLeft = New-TextLabel -Text '' -X 16 -Y 8 -W 460 -H 18 -Font $script:FontMini -Fore $script:C_Muted
    $bar.Controls.Add($lblLeft)
    $lblRight = New-TextLabel -Text 'Pret' -X 0 -Y 8 -W 400 -H 18 -Font $script:FontMini -Fore $script:C_Accent -Align 'Right'
    $lblRight.Dock = 'Right'
    $bar.Controls.Add($lblRight)
    $bar.Tag = @{ Left = $lblLeft; State = $lblRight }
    if ($Parent) { $Parent.Controls.Add($bar) }
    return $bar
}

# Ecrit un message horodate dans le pied de page (drapeau par 60-Shell).
function Set-Status {
    param([string]$Message)
    if ($script:StatusBarRef -and $script:StatusBarRef.Tag.State) {
        $script:StatusBarRef.Tag.State.Text = ("{0:HH:mm:ss}  {1}" -f (Get-Date), $Message)
    }
}

# ================= PASTILLE DE STATUT =================
# Label arrondi a fond plein : blanc sur vert/bleu/rouge, sombre sur ambre.
function Set-Pill {
    param($Pill, [string]$Text, [System.Drawing.Color]$Color)
    $Pill.Text = $Text
    $Pill.BackColor = $Color
    if ($Color -eq $script:C_Amber) {
        $Pill.ForeColor = $script:C_Text
    } else {
        $Pill.ForeColor = [System.Drawing.Color]::White
    }
}

# ================= CARTE DE STATUT (titre + detail + pastille + barre) =================
# Pensee pour etre dockee en haut d'une vue (Dock=Top) ; la pastille et la
# barre suivent le resize grace a leurs ancres.
function New-StatusCard {
    param([int]$W = 660, [int]$H = 78, [string]$ReadyText = 'Pret', [string]$Title = 'Pret')
    $card = New-RoundedPanel -W $W -H $H -R 12
    $card.Dock = 'Top'

    $lbl = New-TextLabel -Text $Title -X 16 -Y 10 -W ($W - 160) -H 22 -Font $script:FontTitle
    $card.Controls.Add($lbl)
    $sub = New-TextLabel -Text $ReadyText -X 16 -Y 35 -W ($W - 160) -H 18 -Font $script:FontUI -Fore $script:C_Muted
    $card.Controls.Add($sub)

    $pl = New-Object System.Windows.Forms.Label
    $pl.Text = 'EN ATTENTE'
    $pl.Size = New-Object System.Drawing.Size(104, 26)
    $pl.Location = New-Object System.Drawing.Point(($W - 124), 14)
    $pl.Font = $script:FontSemB
    $pl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $pl.Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
    Set-Pill $pl 'EN ATTENTE' $script:C_Muted
    Set-RoundRegion $pl 13
    $card.Controls.Add($pl)

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Size = New-Object System.Drawing.Size(($W - 32), 8)
    $bar.Location = New-Object System.Drawing.Point(16, 60)
    $bar.BackColor = [System.Drawing.Color]::Transparent
    $bar.Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
    $bar.Tag = @{ Pct = 0; Color = $script:C_Accent }
    Set-DoubleBuffer $bar
    $bar.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        Set-SmoothingMode $g 'AntiAlias'
        $tr = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(233, 238, 244))
        $rp = Get-RoundedPath -W $s.Width -H $s.Height -R 4
        $g.FillPath($tr, $rp)
        $rp.Dispose()
        $tr.Dispose()
        $w = [int]($s.Width * ($s.Tag.Pct / 100.0))
        if ($w -gt 0) {
            $b = New-Object System.Drawing.SolidBrush $s.Tag.Color
            $rp2 = Get-RoundedPath -W ([Math]::Max(10, $w)) -H $s.Height -R 4
            $g.FillPath($b, $rp2)
            $rp2.Dispose()
            $b.Dispose()
        }
    })
    $card.Controls.Add($bar)

    return @{ Card = $card; Label = $lbl; Sub = $sub; Pill = $pl; Bar = $bar }
}

# Met a jour une carte de statut + l'etat des boutons (contrat shared).
function Set-UiStatus {
    param(
        $Ctl,
        [bool]$Running,
        [string]$Status,
        [string]$Detail = '',
        [int]$Percent = -1,
        [string]$PillText = 'EN ATTENTE',
        [System.Drawing.Color]$PillColor = $script:C_Muted,
        [string]$BarColor = 'Accent',
        [object[]]$EnableWhenIdle = @(),
        [object[]]$EnableWhenBusy = @()
    )
    foreach ($b in @($EnableWhenIdle)) { if ($b) { $b.Enabled = (-not $Running) } }
    foreach ($b in @($EnableWhenBusy)) { if ($b) { $b.Enabled = $Running } }

    $Ctl.Label.Text = $Status
    if ($Detail) { $Ctl.Sub.Text = $Detail }
    Set-Pill $Ctl.Pill $PillText $PillColor
    $Ctl.Bar.Tag.Color = switch ($BarColor) {
        'Green' { $script:C_Green }
        'Red'   { $script:C_Red }
        'Amber' { $script:C_Amber }
        default { $script:C_Accent }
    }
    if ($Percent -ge 0) {
        $Ctl.Bar.Tag.Pct = [Math]::Min(100, [Math]::Max(0, $Percent))
    }
    $Ctl.Bar.Invalidate()
}

# ================= CARTE JOURNAL (sombre, dans une carte) =================
function New-LogCard {
    param([int]$X, [int]$Y, [int]$W = 660, [int]$H = 142, [string]$Title = "JOURNAL D'EXECUTION", [System.Windows.Forms.Control]$Parent = $null)
    $card = New-Card -X $X -Y $Y -W $W -H $H -Fill $script:C_Log -Parent $Parent
    $tl = New-TextLabel -Text $Title -X 16 -Y 12 -W 400 -H 16 -Font $script:FontStep -Fore $script:C_TxtIn -Parent $card
    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Location = New-Object System.Drawing.Point(16, 34)
    $box.Size = New-Object System.Drawing.Size(($W - 32), ($H - 46))
    $box.Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
    $box.ReadOnly = $true
    $box.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
    $box.BackColor = $script:C_Log
    $box.ForeColor = $script:C_TxtIn2
    $box.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $box.Font = $script:FontMono
    $box.WordWrap = $true
    $box.DetectUrls = $false
    $box.HideSelection = $true
    $card.Controls.Add($box)
    $clr = New-ModernButton -Text 'Effacer' -X ($W - 92) -Y 8 -W 76 -H 24 -Fill ([System.Drawing.Color]::FromArgb(38, 45, 58)) -Hover ([System.Drawing.Color]::FromArgb(56, 66, 84)) -Fore $script:C_TxtIn2 -Font $script:FontMini
    $card.Controls.Add($clr)
    $clr.Tag.Box = $box
    $clr.Add_Click({ param($s, $e) $s.Tag.Box.Clear() })
    $clr.BringToFront()
    return @{ Card = $card; Box = $box }
}

# ================= GABARIT "RUN" (views a etapes) =================
# Carte statut (haut) + liste des etapes + journal plein + barre d'actions
# (bas) : meme structure que la maquette Interface-Sarytany.
# $Steps : array de triplet @(Libelle, Description, Manuel) ; la colonne
# statut est pilotee par Set-RunRow / Reset-RunRows depuis la vue.
function New-RunView {
    param(
        [string]$ReadyText = 'Pret',
        [array]$Steps = @(),
        [string]$GoText = 'Lancer',
        [string]$ExtraText = '',
        [bool]$ShowResume = $true
    )
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Fill'
    $panel.Visible = $false
    $panel.BackColor = $script:C_Bg
    $panel.Padding = New-Object System.Windows.Forms.Padding(24, 20, 24, 16)
    Set-DoubleBuffer $panel

    # Journal plein (ajoute en premier : recoit l'espace restant)
    $log = New-Object System.Windows.Forms.RichTextBox
    $log.Dock = 'Fill'
    $log.ReadOnly = $true
    $log.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $log.BackColor = $script:C_Log
    $log.ForeColor = $script:C_TxtIn2
    $log.Font = $script:FontMono
    $log.WordWrap = $true
    $log.DetectUrls = $false
    $log.HideSelection = $true

    # Barre d'actions (bas)
    $bar = New-Object System.Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Bottom'
    $bar.Height = 54
    $bar.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
    $bar.BackColor = $script:C_Bg
    $bar.WrapContents = $false

    $btnExtra = $null
    if ($ExtraText) {
        $btnExtra = New-ModernButton -Text $ExtraText -X 0 -Y 0 -W 330 -H 38 -Fill $script:C_Green -Hover ([System.Drawing.Color]::FromArgb(17, 138, 102))
        $bar.Controls.Add($btnExtra)
    }
    $btnGo = New-ModernButton -Text $GoText -X 0 -Y 0 -W 300 -H 38
    $bar.Controls.Add($btnGo)
    $btnResume = $null
    if ($ShowResume) {
        $btnResume = New-ModernButton -Text 'Reprendre apres action manuelle' -X 0 -Y 0 -W 260 -H 38 -Fill $script:C_Amber -Hover ([System.Drawing.Color]::FromArgb(250, 173, 42)) -Fore $script:C_Text
        $btnResume.Enabled = $false
        $bar.Controls.Add($btnResume)
    }
    $btnCancel = New-GreyButton -Text 'Annuler' -X 0 -Y 0 -W 120 -H 38
    $btnCancel.Enabled = $false
    $bar.Controls.Add($btnCancel)

    # Liste des etapes : "01  Libelle | Description | Statut"
    $list = New-Object System.Windows.Forms.ListView
    $list.Dock = 'Top'
    $list.Height = [Math]::Min(24 + ($Steps.Count * 24), 250)
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.MultiSelect = $false
    $list.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $list.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::None
    $list.Font = $script:FontUI
    $list.HideSelection = $false
    [void]$list.Columns.Add('', 340)
    [void]$list.Columns.Add('', 320)
    [void]$list.Columns.Add('', 150)
    $n = 0
    foreach ($s in $Steps) {
        $n++
        $it = New-Object System.Windows.Forms.ListViewItem(('{0:00}  {1}' -f $n, [string]$s[0]))
        [void]$it.SubItems.Add([string]$s[1])
        [void]$it.SubItems.Add('EN ATTENTE')
        [void]$list.Items.Add($it)
    }

    # Carte statut (haut)
    $status = New-StatusCard -ReadyText $ReadyText

    # Ordre d'ajout important : Fill d'abord, les Dock=Top ensuite,
    # la carte statut en dernier (elle est d'abord placee en haut).
    $panel.Controls.AddRange(@($log, $bar, (New-Gap 12), $list, (New-Gap 12), $status.Card))

    return @{
        Panel     = $panel
        Status    = $status
        List      = $list
        Log       = $log
        BtnGo     = $btnGo
        BtnExtra  = $btnExtra
        BtnResume = $btnResume
        BtnCancel = $btnCancel
    }
}

# Met le statut d'une ligne de la liste d'etapes (index 0-based).
function Set-RunRow {
    param($View, [int]$Index, [string]$Status)
    if (-not $View -or -not $View.List) { return }
    if ($Index -lt 0 -or $Index -ge $View.List.Items.Count) { return }
    $View.List.Items[$Index].SubItems[2].Text = $Status
}

# Remet toutes les lignes de la liste a "EN ATTENTE".
function Reset-RunRows {
    param($View)
    if (-not $View -or -not $View.List) { return }
    foreach ($it in $View.List.Items) { $it.SubItems[2].Text = 'EN ATTENTE' }
}

# ================= COULEURS DU JOURNAL =================
function Get-UiLogColor {
    param([string]$Level = 'INFO')
    switch ($Level) {
        'OK'        { return [System.Drawing.Color]::FromArgb(72, 205, 148) }
        'ERREUR'    { return [System.Drawing.Color]::FromArgb(255, 122, 122) }
        'ATTENTION' { return [System.Drawing.Color]::FromArgb(255, 190, 100) }
        default     { return [System.Drawing.Color]::FromArgb(178, 190, 206) }
    }
}

function Write-UiLog {
    param($Box, [string]$Message, [string]$Level = 'INFO')
    if (-not $Box) { return }
    $color = Get-UiLogColor -Level $Level
    $default = $Box.ForeColor
    $Box.SelectionStart = $Box.Text.Length
    $Box.SelectionLength = 0
    $Box.SelectionColor = $color
    $Box.AppendText(("{0}   {1}`r`n" -f (Get-Date).ToString('HH:mm:ss'), $Message))
    $Box.SelectionStart = $Box.Text.Length
    $Box.ScrollToCaret()
    $Box.SelectionColor = $default
}
