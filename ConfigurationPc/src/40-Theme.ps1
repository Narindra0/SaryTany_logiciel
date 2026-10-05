# ==================================================================
# src\40-Theme.ps1  -  Theme visuel
#   Activation des styles natifs, polices, palette de couleurs,
#   icone de l'application (app.ico) et primitives de dessin
#   (coins arrondis, regions, double buffering).
# Depend de : assemblies chargees par src\10-Core.ps1, $script:AppRoot.
# ==================================================================
[System.Windows.Forms.Application]::EnableVisualStyles()
if ($env:BENTLEY_DEBUG) { "ENTRE UI Mode=$Mode SelfTest=$SelfTest" | Add-Content -Path "$env:TEMP\bentley_debug.txt" -Encoding UTF8 }

# --- Polices ---
$script:FontUI   = New-Object System.Drawing.Font('Segoe UI', 9)
$script:FontSemB = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
$script:FontBig  = New-Object System.Drawing.Font('Segoe UI Semibold', 16, [System.Drawing.FontStyle]::Bold)
$script:FontStep = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
$script:FontMini = New-Object System.Drawing.Font('Segoe UI', 8)
$script:FontMono = New-Object System.Drawing.Font('Consolas', 9)

# --- Palette ---
$script:C_Bg     = [System.Drawing.Color]::FromArgb(240, 243, 247)
$script:C_Title  = [System.Drawing.Color]::FromArgb(23, 28, 38)
$script:C_Accent = [System.Drawing.Color]::FromArgb(0, 122, 204)
$script:C_Green  = [System.Drawing.Color]::FromArgb(22, 163, 122)
$script:C_Amber  = [System.Drawing.Color]::FromArgb(224, 150, 40)
$script:C_Red    = [System.Drawing.Color]::FromArgb(211, 63, 63)
$script:C_Text   = [System.Drawing.Color]::FromArgb(28, 33, 41)
$script:C_Muted  = [System.Drawing.Color]::FromArgb(122, 132, 146)
$script:C_Card   = [System.Drawing.Color]::White
$script:C_Log    = [System.Drawing.Color]::FromArgb(21, 25, 33)
$script:C_TxtIn  = [System.Drawing.Color]::FromArgb(120, 132, 150)
$script:C_TxtIn2 = [System.Drawing.Color]::FromArgb(165, 178, 196)

# --- Primitives ---
function Set-DoubleBuffer {
    # DoubleBuffered n'est pas expose publiquement sur les controles WinForms
    param($Control, [bool]$Value = $true)
    try {
        $prop = [System.Windows.Forms.Control].GetProperty('DoubleBuffered')
        $prop.SetValue($Control, $Value, $null)
    } catch { }
}

function Get-RoundedPath {
    param([int]$W, [int]$H, [int]$R = 12)
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $p.AddArc(0, 0, $d, $d, 180, 90)
    $p.AddArc($W - $d, 0, $d, $d, 270, 90)
    $p.AddArc($W - $d, $H - $d, $d, $d, 0, 90)
    $p.AddArc(0, $H - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function Set-RoundRegion {
    param($Control, [int]$R = 12)
    $Control.Region = New-Object System.Drawing.Region((Get-RoundedPath -W $Control.Width -H $Control.Height -R $R))
}

# ================= ICONE DE L'APPLICATION (app.ico) =================
# app.ico habille la fenetre (barre des taches / alt-tab) et, apres compilation,
# sert aussi d'icone a l'executable (voir Build-Exe.ps1 : -iconFile app.ico).
$script:AppIcon = $null
function Get-AppIcon {
    if ($script:AppIcon) { return $script:AppIcon }

    # 1. app.ico pose a cote du projet ou de l'executable
    $dirs = @()
    if ($script:AppRoot) { $dirs += $script:AppRoot }
    try   { $dirs += (Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)) } catch { }
    $dirs += (Get-Location).Path

    foreach ($d in ($dirs | Where-Object { $_ } | Select-Object -Unique)) {
        $p = Join-Path $d 'app.ico'
        if (Test-Path -LiteralPath $p) {
            try {
                # Copie en memoire : app.ico reste modifiable (recompilation) pendant l'execution.
                $bytes = [System.IO.File]::ReadAllBytes($p)
                $ms = New-Object System.IO.MemoryStream(,$bytes)
                try   { $ico = New-Object System.Drawing.Icon($ms, 48, 48) }
                catch { $ms.Position = 0; $ico = New-Object System.Drawing.Icon($ms) }
                $script:AppIcon = $ico
                return $script:AppIcon
            } catch { }
        }
    }

    # 2. Repli : icone embarquee dans l'executable lui-meme (compile avec -iconFile)
    try {
        $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ([System.IO.File]::Exists($exe)) {
            $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
            if ($ico) { $script:AppIcon = $ico; return $script:AppIcon }
        }
    } catch { }

    return $null
}
