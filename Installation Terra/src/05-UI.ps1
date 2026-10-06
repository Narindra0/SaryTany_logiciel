# ==============================================================================
# 05-UI.ps1 - Interface graphique (design "Maquette v2")
# ==============================================================================
#
# POLITIQUE DE CLOSURE (IMPORTANT) :
#   .GetNewClosure() capture une COPIE des variables $script: au moment de la
#   creation (lectures perimees, ecritures scalaires perdues). Seules les
#   mutations de membres d'objets (hashtables) traversent.
#   -> Les handlers qui n'utilisent que des variables/fonctions script sont
#      enregistres SANS closure (acces live).
#   -> Les handlers qui utilisent des variables LOCALES gardent la closure,
#      mais toute modification d'etat script passe par une FONCTION ou par
#      l'objet capture (ex. $f.Tag).

# ------------------------------------------------------------------------------
# Helpers de construction
# ------------------------------------------------------------------------------

function Add-TitleBarDrag {
    param($Tb)
    $Tb.Add_MouseDown({
        if ($this.Parent) {
            $script:DragF  = $this.Parent
            $script:DragPt = [System.Windows.Forms.Control]::MousePosition
            $this.Capture  = $true
        }
    })
    $Tb.Add_MouseMove({
        if ($script:DragF -and $script:DragPt) {
            $cur = [System.Windows.Forms.Control]::MousePosition
            $f   = $script:DragF
            $f.Location = New-Object System.Drawing.Point (($f.Location.X + $cur.X - $script:DragPt.X), ($f.Location.Y + $cur.Y - $script:DragPt.Y))
            $script:DragPt = $cur
        }
    })
    $Tb.Add_MouseUp({
        $script:DragF  = $null
        $script:DragPt = $null
    })
}

function New-TitleBar {
    param($Form, [string]$Title)

    $tb = New-Object System.Windows.Forms.Panel
    $tb.Dock      = 'Top'
    $tb.Height    = 32
    $tb.BackColor = Get-Col $script:Hex.tbBg

    $logo = New-Object System.Windows.Forms.Panel
    $logo.Size          = New-Object System.Drawing.Size(14,14)
    $logo.BackColor     = Get-Col $script:Hex.accent
    $logo.Location      = New-Object System.Drawing.Point(10,9)
    $tb.Controls.Add($logo)

    $name = New-Object System.Windows.Forms.Label
    $name.Text      = $Title
    $name.Font      = New-Object System.Drawing.Font('Segoe UI Semibold',10)
    $name.ForeColor = Get-Col $script:Hex.tbInk
    $name.AutoSize  = $true
    $name.Location  = New-Object System.Drawing.Point(30,6)
    $tb.Controls.Add($name)

    $x = New-Object System.Windows.Forms.Button
    $x.Text           = '✕'
    $x.FlatStyle      = 'Flat'
    $x.FlatAppearance.BorderSize = 0
    $x.Size           = New-Object System.Drawing.Size(44,32)
    $x.Dock           = 'Right'
    $x.BackColor      = Get-Col $script:Hex.tbBg
    $x.ForeColor      = Get-Col $script:Hex.tbInk
    $x.Font           = New-Object System.Drawing.Font('Segoe UI',10)
    $x.Cursor         = [System.Windows.Forms.Cursors]::Default
    $tb.Controls.Add($x)

    $x.Add_Click({ $Form.Close() }.GetNewClosure())
    $x.Add_MouseEnter({
        $x.BackColor = Get-Col '#D13438'
        $x.ForeColor = [System.Drawing.Color]::White
    }.GetNewClosure())
    $x.Add_MouseLeave({
        $x.BackColor = Get-Col $script:Hex.tbBg
        $x.ForeColor = Get-Col $script:Hex.tbInk
    }.GetNewClosure())

    return $tb
}

function New-Btn {
    param([string]$Text, [int]$Width, [string]$Hex, [bool]$Line)

    $b = New-Object System.Windows.Forms.Button
    $b.Text          = $Text
    $b.Height        = 36
    $b.Width         = $Width
    $b.Font          = New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $b.FlatStyle     = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.Cursor        = [System.Windows.Forms.Cursors]::Hand

    if ($Line) {
        $b.BackColor = Get-Col $script:Hex.win
        $b.ForeColor = Get-Col $script:Hex.pageInk
        $b.FlatAppearance.BorderSize = 1
        $b.FlatAppearance.BorderColor = Get-Col '#CED4DA'
        $b.FlatAppearance.MouseOverBackColor = Get-Col '#EEF1F3'
        $b.Add_MouseEnter({ $b.BackColor = Get-Col '#EEF1F3' }.GetNewClosure())
        $b.Add_MouseLeave({ $b.BackColor = Get-Col $script:Hex.win }.GetNewClosure())
    } else {
        $b.BackColor = Get-Col $Hex
        $b.ForeColor = [System.Drawing.Color]::White
        $b.Add_MouseEnter({ $b.BackColor = (Get-Col $Hex) }.GetNewClosure())
    }
    return $b
}

# ------------------------------------------------------------------------------
# Modales : activation et dossier Terra
# ------------------------------------------------------------------------------

function Show-ActivationModal {
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition   = 'CenterScreen'
    $f.ClientSize      = New-Object System.Drawing.Size(460,240)
    $f.BackColor       = Get-Col $script:Hex.win
    $f.Font            = New-Object System.Drawing.Font('Segoe UI',9)

    $band = New-Object System.Windows.Forms.Panel
    $band.Dock      = 'Top'
    $band.Height    = 54
    $band.BackColor = Get-Col $script:Hex.accent
    $f.Controls.Add($band)

    $bh = New-Object System.Windows.Forms.Label
    $bh.Text      = 'Activation requise'
    $bh.ForeColor = [System.Drawing.Color]::White
    $bh.Font      = New-Object System.Drawing.Font('Segoe UI Semibold',13)
    $bh.AutoSize  = $true
    $bh.Location  = New-Object System.Drawing.Point(20,15)
    $band.Controls.Add($bh)

    $lead = New-Object System.Windows.Forms.Label
    $lead.Text      = 'Saisissez le code d''activation fourni avec le programme.'
    $lead.ForeColor = Get-Col $script:Hex.muted
    $lead.AutoSize  = $true
    $lead.Location  = New-Object System.Drawing.Point(20,70)
    $f.Controls.Add($lead)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(20,94)
    $txt.Size     = New-Object System.Drawing.Size(420,26)
    $txt.UseSystemPasswordChar = $true
    $f.Controls.Add($txt)

    $msg = New-Object System.Windows.Forms.Label
    $msg.Text      = ''
    $msg.ForeColor = Get-Col $script:Hex.errInk
    $msg.AutoSize  = $true
    $msg.Location  = New-Object System.Drawing.Point(20,126)
    $msg.Font      = New-Object System.Drawing.Font('Segoe UI',8)
    $f.Controls.Add($msg)

    $foot = New-Object System.Windows.Forms.Panel
    $foot.Dock = 'Bottom'
    $foot.Height = 56
    $f.Controls.Add($foot)

    $bQuit = New-Btn 'Quitter' 110 (($script:Hex).grey) $false
    $bQuit.Location = New-Object System.Drawing.Point(214,12)
    $foot.Controls.Add($bQuit)

    $bAct  = New-Btn 'Activer' 110 (($script:Hex).go) $false
    $bAct.Location = New-Object System.Drawing.Point(330,12)
    $foot.Controls.Add($bAct)

    $f.Tag = 'cancel'
    $bAct.Add_Click({
        $code = $txt.Text.Trim()
        if (-not $code) { $msg.Text = 'Saisissez un code d''activation.'; return }
        if (Test-ActivationCode $code) {
            $f.Tag = 'ok'
            $f.Close()
        } else {
            $msg.Text = 'Code d''activation incorrect. Vérifiez-le et réessayez.'
            $txt.SelectAll()
            $txt.Focus()
        }
    }.GetNewClosure())

    $bQuit.Add_Click({ $f.Tag = 'cancel'; $f.Close() }.GetNewClosure())
    $txt.Add_KeyDown({
        if ($_.KeyCode -eq 'Enter') { $bAct.PerformClick() }
        if ($_.KeyCode -eq 'Escape') { $bQuit.PerformClick() }
    }.GetNewClosure())
    $f.Add_Shown({ $txt.Focus() }.GetNewClosure())

    $null = $f.ShowDialog()
    $r = ($f.Tag -eq 'ok')
    $f.Dispose()
    return $r
}

function Show-TerraRootModal {
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition   = 'CenterScreen'
    $f.ClientSize      = New-Object System.Drawing.Size(540,250)
    $f.BackColor       = Get-Col $script:Hex.win
    $f.Font            = New-Object System.Drawing.Font('Segoe UI',9)

    $band = New-Object System.Windows.Forms.Panel
    $band.Dock      = 'Top'
    $band.Height    = 54
    $band.BackColor = Get-Col $script:Hex.accent
    $f.Controls.Add($band)

    $bh = New-Object System.Windows.Forms.Label
    $bh.Text      = 'Où se trouve le dossier Terra ?'
    $bh.ForeColor = [System.Drawing.Color]::White
    $bh.Font      = New-Object System.Drawing.Font('Segoe UI Semibold',13)
    $bh.AutoSize  = $true
    $bh.Location  = New-Object System.Drawing.Point(20,15)
    $band.Controls.Add($bh)

    $lead = New-Object System.Windows.Forms.Label
    $lead.Text      = 'Le programme y retrouvera lui-même le sous-dossier eng puis setup.exe.'
    $lead.ForeColor = Get-Col $script:Hex.muted
    $lead.AutoSize  = $true
    $lead.Location  = New-Object System.Drawing.Point(20,70)
    $f.Controls.Add($lead)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(20,94)
    $txt.Size     = New-Object System.Drawing.Size(390,26)
    $txt.Text     = $script:Cfg.TerraRoot
    $f.Controls.Add($txt)

    $bb = New-Object System.Windows.Forms.Button
    $bb.Text      = 'Parcourir…'
    $bb.Location  = New-Object System.Drawing.Point(416,94)
    $bb.Size      = New-Object System.Drawing.Size(104,26)
    $bb.FlatStyle = 'Flat'
    $bb.FlatAppearance.BorderSize = 1
    $bb.FlatAppearance.BorderColor = Get-Col '#CED4DA'
    $bb.BackColor = Get-Col $script:Hex.win
    $bb.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Sélectionnez le dossier principal Terra'
        if ($txt.Text -and (Test-Path $txt.Text)) { $dlg.SelectedPath = $txt.Text }
        if ($dlg.ShowDialog() -eq 'OK') { $txt.Text = $dlg.SelectedPath }
    }.GetNewClosure())
    $f.Controls.Add($bb)

    $msg = New-Object System.Windows.Forms.Label
    $msg.Text      = ''
    $msg.ForeColor = Get-Col $script:Hex.errInk
    $msg.AutoSize  = $true
    $msg.Location  = New-Object System.Drawing.Point(20,126)
    $msg.Font      = New-Object System.Drawing.Font('Segoe UI',8)
    $f.Controls.Add($msg)

    $foot = New-Object System.Windows.Forms.Panel
    $foot.Dock = 'Bottom'
    $foot.Height = 56
    $f.Controls.Add($foot)

    $bLater = New-Btn 'Plus tard' 110 (($script:Hex).win) $true
    $bLater.Location = New-Object System.Drawing.Point(294,12)
    $foot.Controls.Add($bLater)

    $bOk = New-Btn 'Continuer' 110 (($script:Hex).go) $false
    $bOk.Location = New-Object System.Drawing.Point(410,12)
    $foot.Controls.Add($bOk)

    $f.Tag = 'later'
    $bLater.Add_Click({ $f.Tag = 'later'; $f.Close() }.GetNewClosure())
    $bOk.Add_Click({
        $v = $txt.Text.Trim()
        if (-not $v) { $msg.Text = 'Le champ est vide. Indiquez un dossier ou cliquez sur Parcourir.'; return }
        if (-not (Test-Path $v)) { $msg.Text = 'Dossier introuvable. Exemple : C:\Bentley\Terra'; return }
        $script:Cfg.TerraRoot = $v
        Save-Settings | Out-Null
        $f.Tag = 'ok'
        $f.Close()
    }.GetNewClosure())
    $f.Add_Shown({ $txt.Focus() }.GetNewClosure())
    $f.Add_KeyDown({
        if ($_.KeyCode -eq 'Enter') { $bOk.PerformClick() }
        if ($_.KeyCode -eq 'Escape') { $bLater.PerformClick() }
    }.GetNewClosure())

    $null = $f.ShowDialog()
    $r = ($f.Tag -eq 'ok')
    $f.Dispose()
    return $r
}

# ------------------------------------------------------------------------------
# Construction de la fenêtre principale
# ------------------------------------------------------------------------------

function Build-MainForm {
    $script:Form = New-Object System.Windows.Forms.Form
    $script:Form.FormBorderStyle = 'None'
    $script:Form.StartPosition   = 'CenterScreen'
    $script:Form.ClientSize      = New-Object System.Drawing.Size(720,690)
    $script:Form.BackColor       = Get-Col $script:Hex.win
    $script:Form.Font            = New-Object System.Drawing.Font('Segoe UI',9)
    $script:Form.Text            = 'Terra Setup'
    $script:Form.KeyPreview      = $true

    $script:FormSize = $script:Form.ClientSize
    $contentWidth = $script:Form.ClientSize.Width - 36

    # --- Liste (ajoutee en premier : Dock Fill, traitee en dernier) ---
    $list = New-Object System.Windows.Forms.FlowLayoutPanel
    $list.Dock   = 'Fill'
    $list.Padding = New-Object System.Windows.Forms.Padding(18,14,18,6)
    $list.FlowDirection = 'TopDown'
    $list.WrapContents  = $false
    $list.AutoScroll    = $true
    $list.BackColor     = Get-Col $script:Hex.win
    $script:Form.Controls.Add($list)

    for ($i = 1; $i -le $script:StepCount; $i++) {
        $p = $script:Steps[$i - 1]

        $row = New-Object System.Windows.Forms.Panel
        $row.Width     = $contentWidth
        $row.Height    = 56
        $row.Margin    = New-Object System.Windows.Forms.Padding(0,0,0,8)
        $row.BackColor = Get-Col $script:Hex.pendBg

        $icon = New-Object System.Windows.Forms.Panel
        $icon.Size      = New-Object System.Drawing.Size(28,28)
        $icon.Location  = New-Object System.Drawing.Point(14,14)
        $icon.BackColor = [System.Drawing.Color]::Transparent
        $icon.Tag       = $i
        $icon.Add_Paint({
            param($s, $e)
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $idx = $s.Tag
            $st  = $script:StepsState[$idx]
            $fg  = Get-Col ($script:Hex[$st.s + 'Ink'])
            # RectangleF explicite : DrawString n'accepte pas un Rectangle (erreur de liaison PointF)
            $r   = New-Object System.Drawing.RectangleF(2,2,24,24)
            $g.FillEllipse([System.Drawing.Brushes]::White, $r)
            $pen = New-Object System.Drawing.Pen($fg, 1.6)
            $g.DrawEllipse($pen, $r)
            $txt = if ($st.s -eq 'wait') { [string]$idx } else { [string]$script:StepGlyphs[$st.s] }
            $fnt = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
            $sf  = New-Object System.Drawing.StringFormat
            $sf.Alignment = 'Center'
            $sf.LineAlignment = 'Center'
            $g.DrawString($txt, $fnt, (New-Object System.Drawing.SolidBrush $fg), $r, $sf)
        })
        $row.Controls.Add($icon)

        $tt = New-Object System.Windows.Forms.Label
        $tt.Text      = $p.Title
        $tt.Font      = New-Object System.Drawing.Font('Segoe UI Semibold',9)
        $tt.ForeColor = Get-Col $script:Hex.ink
        $tt.AutoSize  = $true
        $tt.Location  = New-Object System.Drawing.Point(52,10)
        $row.Controls.Add($tt)

        $tdc = New-Object System.Windows.Forms.Label
        $tdc.Text      = $p.Desc
        $tdc.Font      = New-Object System.Drawing.Font('Segoe UI',8)
        $tdc.ForeColor = Get-Col $script:Hex.muted
        $tdc.AutoSize  = $false
        $tdc.Width     = $contentWidth - 52 - 110
        $tdc.Location  = New-Object System.Drawing.Point(52,29)
        $row.Controls.Add($tdc)

        $det = New-Object System.Windows.Forms.Label
        $det.Text      = ''
        $det.Font      = New-Object System.Drawing.Font('Segoe UI',8)
        $det.ForeColor = Get-Col $script:Hex.pendInk
        $det.AutoSize  = $false
        $det.Width     = $contentWidth - 52 - 110
        $det.Location  = New-Object System.Drawing.Point(52,43)
        $row.Controls.Add($det)

        $b = New-Object System.Windows.Forms.Label
        $b.Text      = $script:StepLabels['wait']
        $b.Font      = New-Object System.Drawing.Font('Segoe UI Semibold',8)
        $b.ForeColor = Get-Col $script:Hex.pendInk
        $b.AutoSize  = $true
        $b.Location  = New-Object System.Drawing.Point(($contentWidth - 86), 21)
        $row.Controls.Add($b)

        $list.Controls.Add($row)
        $script:StepRows[$i] = @{ row = $row; icon = $icon; badge = $b; detail = $det }
    }

    # --- Info Computer ID (bas) ---
    $info = New-Object System.Windows.Forms.Panel
    $info.Dock      = 'Bottom'
    $info.Height    = 36
    $info.BackColor = Get-Col $script:Hex.win
    $info.Visible   = $false
    $script:Form.Controls.Add($info)

    $script:BandInfoCid = New-Object System.Windows.Forms.Label
    $script:BandInfoCid.Text      = ''
    $script:BandInfoCid.Font      = New-Object System.Drawing.Font('Consolas',9)
    $script:BandInfoCid.ForeColor = Get-Col $script:Hex.pendInk
    $script:BandInfoCid.AutoSize  = $true
    $script:BandInfoCid.Location  = New-Object System.Drawing.Point(18,10)
    $info.Controls.Add($script:BandInfoCid)

    $btnCopy = New-Object System.Windows.Forms.Button
    $btnCopy.Text      = 'Copier'
    $btnCopy.Size      = New-Object System.Drawing.Size(70,26)
    $btnCopy.Anchor    = 'Top,Right'
    $btnCopy.Location  = New-Object System.Drawing.Point(($contentWidth - 60), 5)
    $btnCopy.FlatStyle = 'Flat'
    $btnCopy.FlatAppearance.BorderSize = 1
    $btnCopy.FlatAppearance.BorderColor = Get-Col '#CED4DA'
    $btnCopy.BackColor = Get-Col $script:Hex.win
    $btnCopy.Add_Click({
        try {
            [System.Windows.Forms.Clipboard]::SetText([string]$script:Cfg.ComputerId)
            Show-Toast 'Computer ID copié'
        } catch {}
    })
    $info.Controls.Add($btnCopy)
    $script:BandInfo = $info

    # --- Boutons (bas : au-dessus du statut) ---
    $tools = New-Object System.Windows.Forms.Panel
    $tools.Dock   = 'Bottom'
    $tools.Height = 56
    $tools.BackColor = Get-Col $script:Hex.win
    $script:Form.Controls.Add($tools)

    $script:BtnMain  = New-Btn '▶ Lancer l''installation' 190 (($script:Hex).go) $false
    $script:BtnMain.Location  = New-Object System.Drawing.Point(18,10)
    $tools.Controls.Add($script:BtnMain)

    $script:BtnStop  = New-Btn 'Arrêter' 90 (($script:Hex).grey) $false
    $script:BtnStop.Location  = New-Object System.Drawing.Point(216,10)
    $script:BtnStop.Visible   = $false
    $tools.Controls.Add($script:BtnStop)

    $script:BtnReset = New-Btn 'Réinitialiser' 120 (($script:Hex).win) $true
    $script:BtnReset.Location = New-Object System.Drawing.Point(($contentWidth - 120), 10)
    $tools.Controls.Add($script:BtnReset)

    $script:BtnLog = New-Btn 'Journal…' 100 (($script:Hex).win) $true
    $script:BtnLog.Location = New-Object System.Drawing.Point(($contentWidth - 228), 10)
    $tools.Controls.Add($script:BtnLog)

    $script:BtnSet = New-Btn 'Réglages…' 100 (($script:Hex).win) $true
    $script:BtnSet.Location = New-Object System.Drawing.Point(($contentWidth - 336), 10)
    $tools.Controls.Add($script:BtnSet)

    $script:BtnMain.Add_Click({ Invoke-AllSteps })
    $script:BtnStop.Add_Click({ $script:Abort = $true })
    $script:BtnReset.Add_Click({ Reset-Steps })
    $script:BtnSet.Add_Click({ Open-SettingsWindow })
    $script:BtnLog.Add_Click({ Open-LogWindow })

    # --- Barre de statut (tout en bas) ---
    $st = New-Object System.Windows.Forms.Panel
    $st.Dock      = 'Bottom'
    $st.Height    = 40
    $st.BackColor = Get-Col '#EEF1F3'
    $script:Form.Controls.Add($st)

    $script:BandStatusText = New-Object System.Windows.Forms.Label
    $script:BandStatusText.Text      = 'Prêt à démarrer'
    $script:BandStatusText.Font      = New-Object System.Drawing.Font('Segoe UI',8)
    $script:BandStatusText.ForeColor = Get-Col $script:Hex.pendInk
    $script:BandStatusText.AutoSize  = $true
    $script:BandStatusText.Location  = New-Object System.Drawing.Point(18,12)
    $st.Controls.Add($script:BandStatusText)

    $track = New-Object System.Windows.Forms.Panel
    $track.BackColor = Get-Col '#D5DADF'
    $track.Size      = New-Object System.Drawing.Size(240,6)
    $track.Location  = New-Object System.Drawing.Point(($contentWidth - 240), 17)
    $st.Controls.Add($track)

    $script:FillBar = New-Object System.Windows.Forms.Panel
    $script:FillBar.BackColor = Get-Col $script:Hex.go
    $script:FillBar.Size      = New-Object System.Drawing.Size(0,6)
    $script:FillBar.Location  = New-Object System.Drawing.Point(0,0)
    $track.Controls.Add($script:FillBar)
    $script:FillMax = $track.Width

    # --- Bande (haut, sous la barre de titre) ---
    $band = New-Object System.Windows.Forms.Panel
    $band.Dock      = 'Top'
    $band.Height    = 76
    $band.BackColor = Get-Col $script:Hex.accent
    $script:Form.Controls.Add($band)

    $hh = New-Object System.Windows.Forms.Label
    $hh.Text          = 'Bentley PowerDraft – Modules Terra'
    $hh.ForeColor     = [System.Drawing.Color]::White
    $hh.Font          = New-Object System.Drawing.Font('Segoe UI Semibold',15)
    $hh.AutoSize      = $true
    $hh.Location      = New-Object System.Drawing.Point(18,14)
    $band.Controls.Add($hh)

    $ss = New-Object System.Windows.Forms.Label
    $ss.Text          = "Assistant d'installation et de configuration"
    $ss.ForeColor     = Get-Col $script:Hex.accentSoft
    $ss.Font          = New-Object System.Drawing.Font('Segoe UI',9)
    $ss.AutoSize      = $true
    $ss.Location      = New-Object System.Drawing.Point(18,41)
    $band.Controls.Add($ss)

    $rr = New-Object System.Windows.Forms.Label
    $rr.Text          = if (Test-Admin) { 'Administrateur' } else { 'Droits insuffisants' }
    $rr.ForeColor     = [System.Drawing.Color]::White
    $rr.Font          = New-Object System.Drawing.Font('Segoe UI',9)
    $rr.TextAlign     = 'MiddleCenter'
    $rr.AutoSize      = $false
    $rr.Size          = New-Object System.Drawing.Size(150,26)
    $rr.Anchor        = 'Top,Right'
    $rr.Location      = New-Object System.Drawing.Point(($contentWidth - 150), 14)
    $band.Controls.Add($rr)

    # --- Barre de titre (ajoutee en dernier : dockee en premier) ---
    $tb = New-TitleBar $script:Form 'Terra Setup'
    $script:Form.Controls.Add($tb)

    Add-TitleBarDrag $tb

    $script:Form.Add_Shown({
        if (-not (Test-Admin)) { Add-Log 'WARN' 'Exécutez en administrateur pour l''installation.' }
        if (-not (Test-Path 'I:\')) { Add-Log 'WARN' 'Lecteur I: injoignable.' }
        Update-UI
    })
}

# ------------------------------------------------------------------------------
# Fenêtre Réglages (flottante)
# ------------------------------------------------------------------------------

function Open-SettingsWindow {
    if ($script:SetWin -and -not $script:SetWin.IsDisposed) {
        $script:SetWin.Activate()
        return
    }

    Save-Config

    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition   = 'Manual'
    $f.ClientSize      = New-Object System.Drawing.Size(560,640)
    $f.BackColor       = Get-Col $script:Hex.win
    $f.Font            = New-Object System.Drawing.Font('Segoe UI',9)
    $f.Location        = New-Object System.Drawing.Point (($script:Form.Left + 40), ($script:Form.Top + 40))
    $script:SetWin = $f

    $c = @{}
    $body = New-Object System.Windows.Forms.Panel
    $body.Dock       = 'Fill'
    $body.AutoScroll = $true
    $f.Controls.Add($body)

    $X  = 18
    $W  = 420
    $BW = 96
    $BX = $X + $W + 8

    function Add-Field {
        param([string]$Key, [string]$Label, [bool]$Folder, [string]$Val, [int]$Y)

        $g = New-Object System.Windows.Forms.Label
        $g.Text          = $Label
        $g.Font          = New-Object System.Drawing.Font('Segoe UI Semibold',8)
        $g.ForeColor     = Get-Col $script:Hex.muted
        $g.AutoSize      = $true
        $g.Location      = New-Object System.Drawing.Point($X, $Y)
        $body.Controls.Add($g)

        $t = New-Object System.Windows.Forms.TextBox
        $t.Text     = $Val
        $t.Location = New-Object System.Drawing.Point($X, ($Y + 18))
        $t.Size     = New-Object System.Drawing.Size($W, 26)
        $body.Controls.Add($t)

        $b = New-Object System.Windows.Forms.Button
        $b.Text      = 'Parcourir…'
        $b.Location  = New-Object System.Drawing.Point($BX, ($Y + 18))
        $b.Size      = New-Object System.Drawing.Size($BW, 26)
        $b.FlatStyle = 'Flat'
        $b.FlatAppearance.BorderSize = 1
        $b.FlatAppearance.BorderColor = Get-Col '#CED4DA'
        $b.BackColor = Get-Col $script:Hex.win
        $b.Add_Click({
            if ($Folder) {
                $d = New-Object System.Windows.Forms.FolderBrowserDialog
                $d.Description = $Label
                if ($t.Text -and (Test-Path $t.Text)) { $d.SelectedPath = $t.Text }
                if ($d.ShowDialog() -eq 'OK') { $t.Text = $d.SelectedPath }
            } else {
                $d = New-Object System.Windows.Forms.OpenFileDialog
                $d.Filter = 'Tous les fichiers (*.*)|*.*'
                if ($t.Text -and (Test-Path $t.Text)) { $d.InitialDirectory = (Split-Path $t.Text) }
                if ($d.ShowDialog() -eq 'OK') { $t.Text = $d.FileName }
            }
        }.GetNewClosure())
        $body.Controls.Add($b)

        $c[$Key] = $t
    }

    # --- Groupe 1 : Fichiers Terra ---
    $g1 = New-Object System.Windows.Forms.Label
    $g1.Text          = 'Fichiers Terra'
    $g1.ForeColor     = Get-Col $script:Hex.accent
    $g1.Font          = New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $g1.AutoSize      = $true
    $g1.Location      = New-Object System.Drawing.Point(18,10)
    $body.Controls.Add($g1)

    Add-Field 'terra' 'Dossier principal Terra'  $true  ($script:Cfg.TerraRoot) 40
    Add-Field 'setup' 'Fichier setup.exe'        $false ($script:Cfg.SetupExe)   96
    Add-Field 'ptc'   'Fichier PTC_LAS.ptc'      $false ($script:Cfg.PtcSource)  152

    # --- Groupe 2 : Installation ---
    $g2 = New-Object System.Windows.Forms.Label
    $g2.Text          = 'Installation'
    $g2.ForeColor     = Get-Col $script:Hex.accent
    $g2.Font          = New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $g2.AutoSize      = $true
    $g2.Location      = New-Object System.Drawing.Point(18,212)
    $body.Controls.Add($g2)

    Add-Field 'pd' 'PowerDraft.exe' $false ($script:Cfg.PowerDraftExe) 242

    $gl = New-Object System.Windows.Forms.Label
    $gl.Text          = 'Version à installer'
    $gl.Font          = New-Object System.Drawing.Font('Segoe UI Semibold',8)
    $gl.ForeColor     = Get-Col $script:Hex.muted
    $gl.AutoSize      = $true
    $gl.Location      = New-Object System.Drawing.Point(18,298)
    $body.Controls.Add($gl)

    $cbo = New-Object System.Windows.Forms.ComboBox
    $cbo.DropDownStyle = 'DropDownList'
    $cbo.Location = New-Object System.Drawing.Point(18,316)
    $cbo.Size     = New-Object System.Drawing.Size(526,26)
    foreach ($v in $script:VersionChoices) { [void]$cbo.Items.Add($v) }
    if ($script:Cfg.SetupVersion) {
        $cbo.SelectedItem = $script:Cfg.SetupVersion
    }
    if (-not $cbo.SelectedItem) { $cbo.SelectedIndex = 0 }
    $body.Controls.Add($cbo)
    $c['ver'] = $cbo

    Add-Field 'dest' 'Dossier cible TerraScan' $true ($script:Cfg.TscanDir) 368

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text                = 'Installation silencieuse (version laissée par défaut)'
    $chk.Font                = New-Object System.Drawing.Font('Segoe UI',8)
    $chk.ForeColor           = Get-Col $script:Hex.runInk
    $chk.BackColor           = Get-Col $script:Hex.runBg
    $chk.Padding             = New-Object System.Windows.Forms.Padding(10,7,10,7)
    $chk.AutoSize            = $false
    $chk.Size                = New-Object System.Drawing.Size(526,34)
    $chk.Location            = New-Object System.Drawing.Point(18,424)
    $chk.Checked             = $script:Cfg.Silent
    $body.Controls.Add($chk)
    $c['silent'] = $chk

    # --- Groupe 3 : Système ---
    $g3 = New-Object System.Windows.Forms.Label
    $g3.Text          = 'Système'
    $g3.ForeColor     = Get-Col $script:Hex.accent
    $g3.Font          = New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $g3.AutoSize      = $true
    $g3.Location      = New-Object System.Drawing.Point(18,474)
    $body.Controls.Add($g3)

    Add-Field 'cid' 'Computer ID (Tools > About > Copy for email)' $false ($script:Cfg.ComputerId) 504

    $sec = New-Object System.Windows.Forms.Button
    $sec.Text      = 'Ouvrir Windows Security'
    $sec.Location  = New-Object System.Drawing.Point(18,560)
    $sec.Size      = New-Object System.Drawing.Size(190,30)
    $sec.FlatStyle = 'Flat'
    $sec.FlatAppearance.BorderSize = 1
    $sec.FlatAppearance.BorderColor = Get-Col '#CED4DA'
    $sec.BackColor = Get-Col $script:Hex.win
    $sec.Add_Click({ Start-Process 'ms-settings:windowsdefender' }.GetNewClosure())
    $body.Controls.Add($sec)
    $script:BtnSecurity = $sec

    $foot = New-Object System.Windows.Forms.Panel
    $foot.Dock   = 'Bottom'
    $foot.Height = 56
    $f.Controls.Add($foot)

    $bCancel = New-Btn 'Annuler' 110 (($script:Hex).win) $true
    $bCancel.Location = New-Object System.Drawing.Point(320,12)
    $foot.Controls.Add($bCancel)

    $bSave = New-Btn 'Enregistrer' 120 (($script:Hex).go) $false
    $bSave.Location = New-Object System.Drawing.Point(438,12)
    $foot.Controls.Add($bSave)

    $script:SetCtrls = $c

    $bCancel.Add_Click({ $f.Close() }.GetNewClosure())
    $bSave.Add_Click({
        Save-Config
        Save-Settings | Out-Null
        Update-UI
        Show-Toast 'Réglages enregistrés'
        $f.Close()
    }.GetNewClosure())
    $f.Add_FormClosed({
        $script:SetCtrls = $null
        $script:SetWin   = $null
    })

    $tb = New-TitleBar $f 'Réglages'
    $f.Controls.Add($tb)
    Add-TitleBarDrag $tb
    $f.Show()
}

# ------------------------------------------------------------------------------
# Fenêtre Journal (flottante)
# ------------------------------------------------------------------------------

function Open-LogWindow {
    if ($script:LogWin -and -not $script:LogWin.IsDisposed) {
        $script:LogWin.Activate()
        return
    }

    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition   = 'Manual'
    $f.ClientSize      = New-Object System.Drawing.Size(600,430)
    $f.BackColor       = Get-Col $script:Hex.logBg
    $f.Font            = New-Object System.Drawing.Font('Segoe UI',9)
    $f.Location        = New-Object System.Drawing.Point (($script:Form.Left + 60), ($script:Form.Top + 80))
    $script:LogWin = $f

    $logbar = New-Object System.Windows.Forms.Panel
    $logbar.Dock   = 'Bottom'
    $logbar.Height = 44
    $logbar.BackColor = Get-Col '#15171A'
    $f.Controls.Add($logbar)

    # --- Boutons sombres du bas (barre de journal) ---
    $bExp = New-Object System.Windows.Forms.Button
    $bExp.Text      = 'Exporter…'
    $bExp.Size      = New-Object System.Drawing.Size(110,28)
    $bExp.Location  = New-Object System.Drawing.Point(360,8)
    $bExp.FlatStyle = 'Flat'
    $bExp.FlatAppearance.BorderSize = 1
    $bExp.FlatAppearance.BorderColor = Get-Col '#3A3E44'
    $bExp.FlatAppearance.MouseOverBackColor = Get-Col '#24272C'
    $bExp.BackColor = Get-Col '#1B1D21'
    $bExp.ForeColor = Get-Col $script:Hex.logInk
    $bExp.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $bExp.Add_MouseEnter({ $bExp.BackColor = Get-Col '#24272C' }.GetNewClosure())
    $bExp.Add_MouseLeave({ $bExp.BackColor = Get-Col '#1B1D21' }.GetNewClosure())
    $logbar.Controls.Add($bExp)

    $bCle = New-Object System.Windows.Forms.Button
    $bCle.Text      = 'Effacer'
    $bCle.Size      = New-Object System.Drawing.Size(90,28)
    $bCle.Location  = New-Object System.Drawing.Point(478,8)
    $bCle.FlatStyle = 'Flat'
    $bCle.FlatAppearance.BorderSize = 1
    $bCle.FlatAppearance.BorderColor = Get-Col '#3A3E44'
    $bCle.FlatAppearance.MouseOverBackColor = Get-Col '#24272C'
    $bCle.BackColor = Get-Col '#1B1D21'
    $bCle.ForeColor = Get-Col $script:Hex.logInk
    $bCle.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $bCle.Add_MouseEnter({ $bCle.BackColor = Get-Col '#24272C' }.GetNewClosure())
    $bCle.Add_MouseLeave({ $bCle.BackColor = Get-Col '#1B1D21' }.GetNewClosure())
    $logbar.Controls.Add($bCle)

    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Dock        = 'Fill'
    $rtb.BackColor   = Get-Col $script:Hex.logBg
    $rtb.ForeColor   = Get-Col $script:Hex.logInk
    $rtb.BorderStyle = 'None'
    $rtb.Font        = New-Object System.Drawing.Font('Consolas',9)
    $rtb.ReadOnly    = $true
    $f.Controls.Add($rtb)
    $script:LogRtB = $rtb

    $bExp.Add_Click({
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = 'Journal (*.log)|*.log|Texte (*.txt)|*.txt'
        $dlg.FileName = 'PowerDraft-install-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.log'
        if ($dlg.ShowDialog() -eq 'OK') {
            $lines = $script:LogLines | ForEach-Object {
                "$($_.t) [$($_.l.PadRight(4))] $($_.m)"
            }
            [System.IO.File]::WriteAllLines($dlg.FileName, $lines)
            Show-Toast 'Journal exporté'
        }
    }.GetNewClosure())

    $bCle.Add_Click({
        Clear-LogBuffer
        $rtb.Clear()
    }.GetNewClosure())

    $f.Add_FormClosed({
        $script:LogRtB = $null
        $script:LogWin = $null
    })

    $tb = New-TitleBar $f 'Journal'
    $f.Controls.Add($tb)
    Add-TitleBarDrag $tb

    # Creer le handle AVANT toute manipulation du RichTextBox (sinon blocage)
    $null = $f.CreateControl()
    $rtb.Clear()
    $script:LogPainted = 0
    Paint-Log
    $f.Show()
}