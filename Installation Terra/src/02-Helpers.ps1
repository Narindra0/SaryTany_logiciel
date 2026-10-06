# ==============================================================================
# 02-Helpers.ps1 - Privilèges, journal, etats, progression, toast
# ==============================================================================

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Now {
    return (Get-Date).ToString('HH:mm:ss')
}

# --- Journal (double buffee : lignes + rendu RichTextBox colore) ---
function Add-Log {
    param([string]$Text, [string]$Level = 'INFO')
    $script:LogLines += @{ t = Get-Now; l = $Level; m = $Text }
    Paint-Log
}

function Get-LevelPad {
    param([string]$Level)
    switch ($Level) {
        'OK'   { return ' OK ' }
        'INFO' { return 'INFO' }
        'WARN' { return 'WARN' }
        'ERR'  { return 'ERR ' }
        default { return $Level }
    }
}

# Vide la memoire du journal (appelee depuis les handlers UI : acces live)
function Clear-LogBuffer {
    $script:LogLines = @()
    $script:LogPainted = 0
}

function Paint-Log {
    $rtb = $script:LogRtB
    if (-not $rtb) { return }

    $colTm   = Get-Col $script:Hex.logTm
    $colInfo = Get-Col $script:Hex.info
    $colOk   = Get-Col $script:Hex.ok
    $colWarn = Get-Col $script:Hex.warn
    $colErr  = Get-Col $script:Hex.err
    $colDef  = Get-Col $script:Hex.logInk

    while ($script:LogPainted -lt $script:LogLines.Count) {
        $e = $script:LogLines[$script:LogPainted]
        $script:LogPainted++

        $rtb.SelectionStart  = $rtb.TextLength
        $rtb.SelectionLength = 0

        $rtb.SelectionColor = $colTm
        $rtb.AppendText($e.t + ' ')

        $rtb.SelectionColor = switch ($e.l) { 'OK' { $colOk } 'WARN' { $colWarn } 'ERR' { $colErr } default { $colInfo } }
        $rtb.AppendText('[' + (Get-LevelPad $e.l) + '] ')

        $rtb.SelectionColor = $colDef
        $rtb.AppendText($e.m + "`r`n")
    }

    $rtb.SelectionStart = $rtb.TextLength
    $rtb.ScrollToCaret()
}

# --- Etat d'une carte ---
function Set-Step {
    param(
        [int]$Index,
        [ValidateSet('wait','run','ok','err')][string]$State,
        [string]$Msg = ''
    )

    $script:StepsState[$Index] = @{ s = $State; m = $Msg }
    Update-UI  # mise a jour de la carte + boutons + barre
    [System.Windows.Forms.Application]::DoEvents()
}

# --- Progression (0..100, texte) ---
function Set-Progress {
    param([int]$Value, [string]$Text)
    $pc = [Math]::Max(0, [Math]::Min(100, $Value))
    if ($script:FillBar -and $script:FillMax) {
        $script:FillBar.Width = [int](($pc / 100) * $script:FillMax)
    }
    if ($script:BandStatusText) { $script:BandStatusText.Text = $Text }
    [System.Windows.Forms.Application]::DoEvents()
}

# --- Toast (notification bas de fenetre, 2.6 s) ---
function Show-Toast {
    param([string]$Text)

    if ($script:ToastForm) {
        try { $script:ToastForm.Close() } catch {}
        try { $script:ToastForm.Dispose() } catch {}
        $script:ToastForm = $null
    }
    if ($script:ToastTimer) {
        try { $script:ToastTimer.Stop(); $script:ToastTimer.Dispose() } catch {}
        $script:ToastTimer = $null
    }

    $t = New-Object System.Windows.Forms.Form
    $t.FormBorderStyle = 'None'
    $t.StartPosition   = 'Manual'
    $t.ShowInTaskbar   = $false
    $t.TopMost         = $false
    $t.BackColor       = Get-Col '#212529'
    $t.ForeColor       = [System.Drawing.Color]::White
    $t.Font            = New-Object System.Drawing.Font('Segoe UI', 9)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text   = $Text
    $lbl.ForeColor = [System.Drawing.Color]::White
    $lbl.AutoSize = $true
    $lbl.Padding = New-Object System.Windows.Forms.Padding(6,4,6,4)
    $t.Controls.Add($lbl)

    $t.ClientSize = New-Object System.Drawing.Size (($lbl.PreferredSize.Width + 12), ($lbl.PreferredSize.Height + 12))

    if ($script:Form) {
        $x = $script:Form.Left + (($script:Form.Width - $t.Width) / 2)
        $y = $script:Form.Bottom - $t.Height - 28
    } else {
        $x = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Width / 2 - ($t.Width / 2)
        $y = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Bottom - $t.Height - 30
    }
    $t.Location = New-Object System.Drawing.Point ([int]$x, [int]$y)

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 2600
    $timer.Add_Tick({
        $timer.Stop()
        $t.Close()
    }.GetNewClosure())

    $script:ToastForm = $t
    $script:ToastTimer = $timer

    $t.Add_Shown({ $timer.Start() }.GetNewClosure())
    $t.Show()
}