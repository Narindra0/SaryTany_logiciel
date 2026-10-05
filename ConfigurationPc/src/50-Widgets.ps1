# ==================================================================
# src\50-Widgets.ps1  -  Controles reutilisables
#   Boites de dialogue, panneaux arrondis, labels, boutons modernes,
#   onglets, cartes d'etape / statut / journal, et les deux helpers
#   partages par toutes les vues : Write-UiLog et Set-UiStatus.
#   Aucune connaissance metier : reutilisable tel quel.
# Depend de : src\40-Theme.ps1 (polices, palette, dessin).
# ==================================================================

function Show-Dialog {
    param([string]$Text, [string]$Title, [string]$Icon = 'Information')
    if ($NoDialogs) { Write-Out ("[{0}] {1}" -f $Title, ($Text -replace "`r`n", ' | ')) -ForegroundColor Cyan; return }
    $ico = [System.Windows.Forms.MessageBoxIcon]::$Icon
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $ico)
}

function New-RoundedPanel {
    param([int]$W, [int]$H, [int]$R = 12, [System.Drawing.Color]$Fill = $script:C_Card)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($W, $H)
    $panel.BackColor = $Fill
    $panel.Tag = @{ R = $R }
    Set-DoubleBuffer $panel
    Set-RoundRegion $panel $R
    $panel.Add_Resize({ Set-RoundRegion $this $this.Tag.R })
    $panel.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(228, 233, 240))
        $e.Graphics.SmoothingMode = 'AntiAlias'
        $e.Graphics.DrawPath($pen, (Get-RoundedPath -W ($s.Width - 1) -H ($s.Height - 1) -R $s.Tag.R))
        $pen.Dispose()
    })
    return $panel
}

function New-TextLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 300, [int]$H = 20,
          [System.Drawing.Font]$Font = $script:FontUI,
          [System.Drawing.Color]$Fore = $script:C_Text,
          [string]$Align = 'Left')
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
    return $l
}

# ================= BOUTON MODERNE =================
function New-ModernButton {
    param(
        [string]$Text, [int]$X, [int]$Y, [int]$W = 200, [int]$H = 42,
        [System.Drawing.Color]$Fill = $script:C_Accent,
        [System.Drawing.Color]$Hover = ([System.Drawing.Color]::FromArgb(0, 100, 180)),
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
    $b.Tag = @{ Fill = $Fill; Hover = $Hover; Fore = $Fore; Text = $Text; Hot = $false }
    Set-DoubleBuffer $b
    Set-RoundRegion $b 10
    $b.Add_Resize({ Set-RoundRegion $this 10 })
    $b.Add_MouseEnter({ param($s, $e) $s.Tag.Hot = $true; $s.Invalidate() })
    $b.Add_MouseLeave({ param($s, $e) $s.Tag.Hot = $false; $s.Invalidate() })
    $b.Add_EnabledChanged({ param($s, $e) $s.Invalidate() })
    $b.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $g.TextRenderingHint = 'AntiAliasGridFit'
        $t = $s.Tag
        if (-not $s.Enabled) {
            $fill = [System.Drawing.Color]::FromArgb(206, 212, 220)
            $fore = [System.Drawing.Color]::FromArgb(142, 150, 162)
        } else {
            $fill = if ($t.Hot) { $t.Hover } else { $t.Fill }
            $fore = $t.Fore
        }
        $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(26, 0, 0, 0))
        $g.FillRectangle($sh, 3, 4, $s.Width - 3, $s.Height - 3)
        $sh.Dispose()
        $br = New-Object System.Drawing.SolidBrush $fill
        $g.FillPath($br, (Get-RoundedPath -W $s.Width -H $s.Height -R 10))
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

# ================= ONGLET =================
function New-Tab {
    param([string]$Text, [int]$X, [int]$W = 380)
    $t = New-Object System.Windows.Forms.Button
    $t.Text = ''
    $t.Location = New-Object System.Drawing.Point($X, 0)
    $t.Size = New-Object System.Drawing.Size($W, 44)
    $t.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $t.FlatAppearance.BorderSize = 0
    $t.BackColor = $script:C_Title
    $t.Cursor = [System.Windows.Forms.Cursors]::Hand
    $t.UseVisualStyleBackColor = $false
    $t.Tag = @{ Text = $Text; Active = $false; Hot = $false }
    $t.Add_MouseEnter({ param($s, $e) $s.Tag.Hot = $true; $s.Invalidate() })
    $t.Add_MouseLeave({ param($s, $e) $s.Tag.Hot = $false; $s.Invalidate() })
    $t.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.TextRenderingHint = 'AntiAliasGridFit'
        $t = $s.Tag
        if ($t.Active) {
            $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(34, 41, 54))
            $g.FillRectangle($bg, 0, 0, $s.Width, $s.Height)
            $bg.Dispose()
        } elseif ($t.Hot) {
            $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(28, 34, 45))
            $g.FillRectangle($bg, 0, 0, $s.Width, $s.Height)
            $bg.Dispose()
        }
        $fore = if ($t.Active) { [System.Drawing.Color]::White } else { $script:C_TxtIn }
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'
        $sf.LineAlignment = 'Center'
        $tb = New-Object System.Drawing.SolidBrush $fore
        $g.DrawString($t.Text, (New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold)), $tb, (New-Object System.Drawing.RectangleF(0, 0, $s.Width, $s.Height)), $sf)
        $tb.Dispose(); $sf.Dispose()
        if ($t.Active) {
            $accent = New-Object System.Drawing.SolidBrush $script:C_Accent
            $g.FillRectangle($accent, 0, $s.Height - 3, $s.Width, 3)
            $accent.Dispose()
        }
    })
    return $t
}

# ================= CARTE D'ETAPE (stepper) =================
function New-StepCard {
    param([int]$Index, [string]$Title, [string]$Sub, [int]$X)
    $card = New-RoundedPanel -W 236 -H 78 -R 12
    $card.Location = New-Object System.Drawing.Point($X, 78)
    $card.Tag = @{ R = 12; N = $Index; State = 'pending'; Title = $Title; Sub = $Sub }
    $card.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $t = $s.Tag
        $accent = switch ($t.State) {
            'done'   { $script:C_Green }
            'active' { $script:C_Accent }
            'error'  { $script:C_Red }
            default  { [System.Drawing.Color]::FromArgb(214, 220, 228) }
        }
        $txt = if ($t.State -eq 'pending') { $script:C_Muted } else { $script:C_Text }
        $br = New-Object System.Drawing.SolidBrush $accent
        $g.FillEllipse($br, 16, 20, 38, 38)
        $br.Dispose()
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'
        $sf.LineAlignment = 'Center'
        $fb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        $mark = if ($t.State -eq 'done') { [string][char]0x2713 } else { [string]$t.N }
        $fontBadge = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
        $g.DrawString($mark, $fontBadge, $fb, (New-Object System.Drawing.RectangleF(16, 20, 38, 38)), $sf)
        $fontBadge.Dispose()
        $fb.Dispose()
        $tb = New-Object System.Drawing.SolidBrush $txt
        $mb = New-Object System.Drawing.SolidBrush $script:C_Muted
        $ft = New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold)
        $g.DrawString($t.Title, $ft, $tb, 64, 24)
        $g.DrawString($t.Sub, $script:FontMini, $mb, 64, 45)
        $ft.Dispose()
        $tb.Dispose(); $mb.Dispose(); $sf.Dispose()
    })
    $form.Controls.Add($card)
    return $card
}

# ================= CARTE STATUT (libelle + pastille + barre) =================
function New-MiniStatus {
    param([int]$X, [int]$Y, [int]$W = 728)
    $card = New-RoundedPanel -W $W -H 78 -R 12
    $card.Location = New-Object System.Drawing.Point($X, $Y)

    $lbl = New-TextLabel -Text "Pret" -X 20 -Y 14 -W ($W - 160) -H 22 -Font $script:FontSemB
    $card.Controls.Add($lbl)
    $sub = New-TextLabel -Text "Aucune modification effectuee." -X 20 -Y 37 -W ($W - 160) -H 18 -Font $script:FontUI -Fore $script:C_Muted
    $card.Controls.Add($sub)

    $pl = New-Object System.Windows.Forms.Panel
    $pl.Size = New-Object System.Drawing.Size(104, 26)
    $pl.Location = New-Object System.Drawing.Point(($W - 124), 16)
    $pl.Tag = @{ Text = 'EN ATTENTE'; Color = $script:C_Muted }
    Set-RoundRegion $pl 13
    $pl.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(26, $s.Tag.Color))
        $g.FillPath($br, (Get-RoundedPath -W $s.Width -H $s.Height -R 13))
        $br.Dispose()
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'
        $sf.LineAlignment = 'Center'
        $tb = New-Object System.Drawing.SolidBrush $s.Tag.Color
        $f = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Bold)
        $g.DrawString($s.Tag.Text, $f, $tb, (New-Object System.Drawing.RectangleF(0, 0, $s.Width, $s.Height)), $sf)
        $f.Dispose(); $tb.Dispose(); $sf.Dispose()
    })
    $card.Controls.Add($pl)

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Size = New-Object System.Drawing.Size(($W - 40), 8)
    $bar.Location = New-Object System.Drawing.Point(20, 58)
    $bar.BackColor = $script:C_Card
    $bar.Tag = @{ Pct = 0; Color = $script:C_Accent }
    $bar.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $tr = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(233, 238, 244))
        $g.FillPath($tr, (Get-RoundedPath -W $s.Width -H $s.Height -R 4))
        $tr.Dispose()
        $w = [int]($s.Width * ($s.Tag.Pct / 100.0))
        if ($w -gt 0) {
            $b = New-Object System.Drawing.SolidBrush $s.Tag.Color
            $g.FillPath($b, (Get-RoundedPath -W ([Math]::Max(10, $w)) -H $s.Height -R 4))
            $b.Dispose()
        }
    })
    $card.Controls.Add($bar)
    return @{ Card = $card; Label = $lbl; Sub = $sub; Pill = $pl; Bar = $bar }
}

# ================= CARTE JOURNAL =================
function New-LogCard {
    param([int]$X, [int]$Y, [int]$W = 728, [int]$H = 142, [string]$Title = "JOURNAL D'EXECUTION")
    $card = New-RoundedPanel -W $W -H $H -R 12 -Fill $script:C_Log
    $card.Location = New-Object System.Drawing.Point($X, $Y)
    $tl = New-TextLabel -Text $Title -X 18 -Y 12 -W 400 -H 16 -Font $script:FontStep -Fore $script:C_TxtIn
    $card.Controls.Add($tl)
    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Location = New-Object System.Drawing.Point(16, 34)
    $box.Size = New-Object System.Drawing.Size(($W - 32), ($H - 46))
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
    Set-RoundRegion $clr 8
    # NOTE : un handler ne voit pas les variables locales de cette fonction ; il
    # passe par le Tag du bouton.
    $clr.Tag.Box = $box
    $clr.Add_Click({ param($s, $e) $s.Tag.Box.Clear() })
    $card.Controls.Add($clr)
    $clr.BringToFront()
    return @{ Card = $card; Box = $box }
}

# ================= HELPERS PARTAGES (journal + etat) =================
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
    # Horodate un message colore dans n'importe quelle RichTextBox de l'interface.
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

function Set-UiStatus {
    # Etat d'une carte statut (libelle, sous-libelle, pastille, barre de
    # progression) et activation des boutons associes a la vue.
    param(
        $Ctl,                               # hashtable renvoyee par New-MiniStatus
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
    $Ctl.Pill.Tag.Text = $PillText
    $Ctl.Pill.Tag.Color = $PillColor
    $Ctl.Pill.Invalidate()
    $Ctl.Bar.Tag.Color = switch ($BarColor) {
        'Green' { $script:C_Green }
        'Red'   { $script:C_Red }
        'Amber' { $script:C_Amber }
        default { $script:C_Accent }
    }
    if ($Percent -ge 0) {
        $Ctl.Bar.Tag.Pct = [Math]::Min(100, [Math]::Max(0, $Percent))
        $Ctl.Bar.Invalidate()
    }
}
