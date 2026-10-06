# ==================================================================
# src\40-Theme.ps1  -  Theme visuel (generation Sarytany)
#   Palettes de couleurs, polices, icone de l'application et
#   primitives de dessin (coins arrondis, regions, double buffering).
#
#   Design : "Neo-Carbon Sarytany" - fenetre standard, bandeau de
#   titre sombre, barre laterale sombre dockee 230px, cartes blanches
#   a titre gris, vues "run" (carte statut + liste d'etapes + journal
#   sombre plein + barre d'actions), accents bleus.
# ==================================================================
[System.Windows.Forms.Application]::EnableVisualStyles()
if ($env:BENTLEY_DEBUG) { "ENTRE UI Mode=$Mode" | Add-Content -Path "$env:TEMP\bentley_debug.txt" -Encoding UTF8 }

# --- Polices ---
$script:FontUI    = New-Object System.Drawing.Font('Segoe UI', 9)
$script:FontSemB  = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
$script:FontBig   = New-Object System.Drawing.Font('Segoe UI Semibold', 16, [System.Drawing.FontStyle]::Bold)
$script:FontStep  = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
$script:FontMini  = New-Object System.Drawing.Font('Segoe UI', 8)
$script:FontMono  = New-Object System.Drawing.Font('Consolas', 9)
$script:FontNav   = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
$script:FontTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 12, [System.Drawing.FontStyle]::Bold)

# --- Palette Neo-Carbon ---
# Fond principal : gris clair avec tout petit grain
$script:C_Bg       = [System.Drawing.Color]::FromArgb(240, 243, 247)
# Barre de titre et sidebar : gris anthracite profond
$script:C_Title    = [System.Drawing.Color]::FromArgb(15, 23, 42)
$script:C_Sidebar  = [System.Drawing.Color]::FromArgb(22, 30, 50)
$script:C_SidebarHover = [System.Drawing.Color]::FromArgb(35, 45, 70)
# Accents : dégradé bleu technologique
$script:C_Accent   = [System.Drawing.Color]::FromArgb(0, 114, 210)
$script:C_AccentHi = [System.Drawing.Color]::FromArgb(30, 140, 230)
$script:C_Green    = [System.Drawing.Color]::FromArgb(16, 185, 129)
$script:C_Amber    = [System.Drawing.Color]::FromArgb(245, 158, 11)
$script:C_Red      = [System.Drawing.Color]::FromArgb(239, 68, 68)
$script:C_Text     = [System.Drawing.Color]::FromArgb(15, 23, 42)
$script:C_TextInv  = [System.Drawing.Color]::White
$script:C_Muted    = [System.Drawing.Color]::FromArgb(100, 116, 139)
$script:C_Slate    = [System.Drawing.Color]::FromArgb(148, 163, 184)
$script:C_Card     = [System.Drawing.Color]::White
$script:C_CardAlt  = [System.Drawing.Color]::FromArgb(248, 250, 254)
$script:C_Log      = [System.Drawing.Color]::FromArgb(21, 25, 33)
$script:C_TxtIn    = [System.Drawing.Color]::FromArgb(120, 132, 150)
$script:C_TxtIn2   = [System.Drawing.Color]::FromArgb(165, 178, 196)
$script:C_StatusBar= [System.Drawing.Color]::FromArgb(245, 247, 251)
$script:C_Separator= [System.Drawing.Color]::FromArgb(226, 232, 240)

# --- Primitives ---
function Set-DoubleBuffer {
    param($Control, [bool]$Value = $true)
    try {
        $prop = [System.Windows.Forms.Control].GetProperty('DoubleBuffered')
        $prop.SetValue($Control, $Value, $null)
    } catch { }
}

# Helper to get Drawing2D enum values via reflection
function Get-Drawing2DEnum {
    param([string]$EnumName, [string]$Value)
    $enumType = [System.Drawing.Graphics].Assembly.GetType("System.Drawing.Drawing2D.$EnumName")
    return [System.Enum]::Parse($enumType, $Value)
}

function Get-RoundedPath {
    param([int]$W, [int]$H, [int]$R = 12)
    # Use reflection to create GraphicsPath to avoid ps2exe type resolution issues
    $gpType = [System.Drawing.Graphics].Assembly.GetType('System.Drawing.Drawing2D.GraphicsPath')
    $p = [System.Activator]::CreateInstance($gpType)
    $d = $R * 2
    # Convert angles to float (Single) to avoid parameter errors
    $p.AddArc(0, 0, $d, $d, [float]180, [float]90)
    $p.AddArc(($W - $d), 0, $d, $d, [float]270, [float]90)
    $p.AddArc(($W - $d), ($H - $d), $d, $d, [float]0, [float]90)
    $p.AddArc(0, ($H - $d), $d, $d, [float]90, [float]90)
    $p.CloseFigure()
    return $p
}

function Set-SmoothingMode {
    param($Graphics, [string]$Mode = 'AntiAlias')
    $smType = [System.Drawing.Graphics].Assembly.GetType('System.Drawing.Drawing2D.SmoothingMode')
    $Graphics.SmoothingMode = [System.Enum]::Parse($smType, $Mode)
}

function Set-TextRenderingHint {
    param($Graphics, [string]$Hint = 'AntiAliasGridFit')
    $trhType = [System.Drawing.Graphics].Assembly.GetType('System.Drawing.Text.TextRenderingHint')
    $Graphics.TextRenderingHint = [System.Enum]::Parse($trhType, $Hint)
}

function Set-RoundRegion {
    param($Control, [int]$R = 12)
    # Les objets GraphicsPath et Region sont finalisables : sans liberation,
    # leur finalisation concurrente par le thread du GC peut contenter le
    # verrou GDI+ pendant une peinture (deadlock aleatoire observe au
    # DrawToBitmap). On libere donc explicitement le chemin ET l'ancienne
    # region remplacee (Set-RoundRegion est appele a chaque resize).
    $path = Get-RoundedPath -W $Control.Width -H $Control.Height -R $R
    $region = New-Object System.Drawing.Region($path)
    $path.Dispose()
    $oldRegion = $Control.Region
    $Control.Region = $region
    if ($oldRegion) { $oldRegion.Dispose() }
}

function Get-AccentGradient {
    # Degrade lineaire pour les boutons primaires
    param([int]$Y, [int]$H)
    $c1 = [System.Drawing.Color]::FromArgb(0, 114, 210)
    $c2 = [System.Drawing.Color]::FromArgb(30, 140, 230)
    $rect = New-Object System.Drawing.Rectangle(0, 0, 1, $H)
    # Use reflection to create LinearGradientBrush
    $lgbType = [System.Drawing.Graphics].Assembly.GetType('System.Drawing.Drawing2D.LinearGradientBrush')
    $lgmType = [System.Drawing.Graphics].Assembly.GetType('System.Drawing.Drawing2D.LinearGradientMode')
    $mode = [System.Enum]::Parse($lgmType, 'Vertical')
    $lg = [System.Activator]::CreateInstance($lgbType, @($rect, $c1, $c2, $mode))
    return $lg
}

# ================= ICONE DE L'APPLICATION (app.ico) =================
$script:AppIcon = $null
function Get-AppIcon {
    if ($script:AppIcon) { return $script:AppIcon }

    $dirs = @()
    if ($script:AppRoot) { $dirs += $script:AppRoot }
    try   { $dirs += (Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)) } catch { }
    $dirs += (Get-Location).Path

    foreach ($d in ($dirs | Where-Object { $_ } | Select-Object -Unique)) {
        $p = Join-Path $d 'app.ico'
        if (Test-Path -LiteralPath $p) {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($p)
                $ms = New-Object System.IO.MemoryStream(,$bytes)
                try   { $ico = New-Object System.Drawing.Icon($ms, 48, 48) }
                catch { $ms.Position = 0; $ico = New-Object System.Drawing.Icon($ms) }
                $script:AppIcon = $ico
                return $script:AppIcon
            } catch { }
        }
    }

    try {
        $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ([System.IO.File]::Exists($exe)) {
            $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
            if ($ico) { $script:AppIcon = $ico; return $script:AppIcon }
        }
    } catch { }

    return $null
}
