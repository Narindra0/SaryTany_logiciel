<#
.SYNOPSIS
    Bentley Suite Installer - installation automatique de 21 modules Bentley.

.DESCRIPTION
    Parcours en 3 étapes :
      1. Choisir le dossier contenant les installateurs
      2. Vérification automatique des fichiers
      3. Installation l'un après l'autre (MSI / MSP / EXE en silencieux,
         modules 13, 14 et 15 en manuel)

    Organisation du script (de haut en bas) :
      0. Démarrage       - droits administrateur
      1. Configuration   - infos, code d'activation, liste des modules
      2. Outils visuels  - couleurs, polices, boutons
      3. Petites fenêtres - activation, à propos / support
      4. Fenêtre principale
      5. Logique         - vérification et installation
      6. Lancement

.NOTES
    Lancer : powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\Install-BentleySuite_v2.ps1"
    Encodage : si vous modifiez ce fichier, enregistrez-le en "UTF-8 avec BOM"
               (nécessaire pour les accents sous PowerShell 5.1).
#>
#Requires -Version 5.1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# =====================================================================
# 0. DROITS ADMINISTRATEUR (compatible .ps1 et .exe compilé)
# =====================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try {
        $hostExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($hostExe -like "*powershell.exe" -or $hostExe -like "*pwsh.exe") {
            # Lancé comme script .ps1 : on relance PowerShell avec ce script
            $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
            Start-Process -FilePath "powershell.exe" -Verb RunAs `
                -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -File "{0}"' -f $scriptPath)
        } else {
            # Lancé comme .exe compilé : on relance l'exe lui-même
            Start-Process -FilePath $hostExe -Verb RunAs
        }
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show("Le lancement en administrateur a été refusé.", "Droits requis", "OK", "Error")
    }
    exit
}

# =====================================================================
# 1. CONFIGURATION
# =====================================================================
$App = @{
    Name        = "Bentley Suite Installer"
    Version     = "2.0.0.0"
    LicenseCode = "ICECREAM"
    Author      = "Narindra Ranjalahy"
    Mail        = "ranjalahy.narindraa@gmail.com"
    Phone       = "0328814081"
    WhatsApp    = "https://wa.me/261328814081"
}

$SilentExeArgs = "/S"
$LogFile = Join-Path $env:TEMP ("BentleyInstall_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

# Liste des modules, dans l'ordre d'installation.
#   Pattern = motif du nom de fichier à chercher dans le dossier
#   Manual  = $true si l'installation doit être faite à la main
$Modules = @(
    @{ Num="01"; Name="DgnIFilterSetUpx64";                   Pattern="01*FilterSet*";                Manual=$false },
    @{ Num="02"; Name="DgnIndexer";                           Pattern="02*DgnIndexer*";               Manual=$false },
    @{ Num="03"; Name="DgnPreviewHandlerx64";                 Pattern="03*DgnPreviewHandler*";        Manual=$false },
    @{ Num="04"; Name="DgnThumbnailProviderx64";              Pattern="04*DgnThumbnailProvider*";     Manual=$false },
    @{ Num="05"; Name="HDRPreviewExtension_x64";              Pattern="05*HDRPreviewExtension*";      Manual=$false },
    @{ Num="06"; Name="ItgDgnDbImporter_1.6_x64";             Pattern="06*Importer*1.6*";             Manual=$false },
    @{ Num="07"; Name="ItgDgnDbImporter_2.0_x64";             Pattern="07*Importer*2.0*";             Manual=$false },
    @{ Num="08"; Name="MetroStationx64";                      Pattern="08*MetroStation*";             Manual=$false },
    @{ Num="09"; Name="Pointools32Extx86";                    Pattern="09*Pointools*";                Manual=$false },
    @{ Num="11"; Name="PowerDraftDocumentationProductx64";    Pattern="11*PowerDraftDocumentation*";  Manual=$false },
    @{ Num="12"; Name="PowerDraftx64";                        Pattern="12*PowerDraftx64*";            Manual=$false },
    @{ Num="13"; Name="Setup_CONNECTIONClient 10.00.12.006";  Pattern="13*CONNECTIONClient*";         Manual=$true  },
    @{ Num="14"; Name="Setup_PowerDraft 10.11.00.036";        Pattern="14*PowerDraft*10.11*";         Manual=$true  },
    @{ Num="15"; Name="Setup_CONNECTAdvisor 10.01.00.103";    Pattern="15*CONNECTAdvisor*";           Manual=$true  },
    @{ Num="16"; Name="Vba71";                                Pattern="16*Vba71*";                    Manual=$false },
    @{ Num="17"; Name="Vba71_1033";                           Pattern="17*Vba71*1033*";               Manual=$false },
    @{ Num="18"; Name="VBA71-KB2803801-x64";                  Pattern="18*KB2803801*";                Manual=$false },
    @{ Num="19"; Name="VBA71-KB2803801-x64_1033";             Pattern="19*KB2803801*1033*";           Manual=$false },
    @{ Num="20"; Name="VBA71-KB3061498-x64";                  Pattern="20*KB3061498*";                Manual=$false },
    @{ Num="21"; Name="patch.x64";                            Pattern="21*patch*";                    Manual=$false },
    @{ Num="22"; Name="MicroStation Update 11 patch REV3";    Pattern="22*microstation*";             Manual=$false }
)
$TotalCount = $Modules.Count

# Logo (image PNG encodée en texte)
$LogoBase64 = "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"

# État du programme
$script:SourceFolder     = ""
$script:Files            = @{}      # numéro du module -> chemin du fichier trouvé
$script:Status           = @{}      # numéro du module -> Pending / Running / Manual / Ok / Failed
$script:Verified         = $false   # les 21 fichiers sont présents
$script:VerifyError      = ""
$script:Running          = $false   # installation en cours
$script:Done             = $false   # installation terminée
$script:CancelRequested  = $false
$script:RestartNeeded    = $false
foreach ($m in $Modules) { $script:Status[$m.Num] = "Pending" }

# =====================================================================
# 2. OUTILS VISUELS (couleurs, polices, boutons...)
# =====================================================================
function Rgb([int]$r, [int]$g, [int]$b) { return [System.Drawing.Color]::FromArgb($r, $g, $b) }
function Pt([int]$x, [int]$y)           { return New-Object System.Drawing.Point($x, $y) }
function Sz([int]$w, [int]$h)           { return New-Object System.Drawing.Size($w, $h) }

function New-Font([double]$Size, [bool]$Bold = $false, [string]$Name = "Segoe UI") {
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    return New-Object System.Drawing.Font($Name, [single]$Size, $style)
}

# Palette
$C = @{
    White       = (Rgb 255 255 255)
    Bg          = (Rgb 241 245 249)
    Card        = (Rgb 255 255 255)
    Border      = (Rgb 226 232 240)
    Text        = (Rgb 30 41 59)
    Muted       = (Rgb 100 116 139)
    Dim         = (Rgb 148 163 184)
    Accent      = (Rgb 37 99 235)
    AccentDark  = (Rgb 29 78 216)
    AccentLight = (Rgb 219 234 254)
    Ok          = (Rgb 22 163 74)
    OkLight     = (Rgb 220 252 231)
    Warn        = (Rgb 180 83 9)
    WarnLight   = (Rgb 254 243 199)
    Bad         = (Rgb 220 38 38)
    BadLight    = (Rgb 254 226 226)
}

# Polices
$F = @{
    Normal = (New-Font 9)
    Bold   = (New-Font 9 $true)
    Small  = (New-Font 8 $true)
    H2     = (New-Font 11 $true)
    Title  = (New-Font 15 $true)
    Mono   = (New-Font 9 $false "Consolas")
}

# Aspect de chaque statut dans la liste des modules
$StatusStyle = @{
    Pending = @{ Text = "En attente";     Fore = $C.Muted;      Back = $C.Card }
    Running = @{ Text = "En cours...";    Fore = $C.Warn;       Back = $C.WarnLight }
    Manual  = @{ Text = "Action requise"; Fore = $C.AccentDark; Back = $C.AccentLight }
    Ok      = @{ Text = "Succès";         Fore = $C.Ok;         Back = $C.OkLight }
    Failed  = @{ Text = "Échec";          Fore = $C.Bad;        Back = $C.BadLight }
}

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, $Color = $C.Text, $Font = $F.Normal)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = Pt $X $Y
    $l.ForeColor = $Color
    $l.Font = $Font
    $l.AutoSize = $true
    $l.BackColor = [System.Drawing.Color]::Transparent
    return $l
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 34, [string]$Style = "Secondary")
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = Pt $X $Y
    $b.Size = Sz $W $H
    $b.FlatStyle = "Flat"
    $b.UseVisualStyleBackColor = $false
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.FlatAppearance.BorderSize = 1
    if ($Style -eq "Primary") {
        $b.Font = $F.Bold
        $b.BackColor = $C.Accent
        $b.ForeColor = $C.White
        $b.FlatAppearance.BorderColor = $C.Accent
        $b.FlatAppearance.MouseOverBackColor = $C.AccentDark
    } else {
        $b.Font = $F.Normal
        $b.BackColor = $C.White
        $b.ForeColor = $C.Text
        $b.FlatAppearance.BorderColor = $C.Border
        $b.FlatAppearance.MouseOverBackColor = $C.Bg
    }
    return $b
}

# Carte blanche avec fine bordure grise (les contrôles se placent dans .Inner)
function New-Card([int]$X, [int]$Y, [int]$W, [int]$H) {
    $outer = New-Object System.Windows.Forms.Panel
    $outer.Location = Pt $X $Y
    $outer.Size = Sz $W $H
    $outer.BackColor = $C.Border
    $inner = New-Object System.Windows.Forms.Panel
    $inner.Location = Pt 1 1
    $inner.Size = Sz ($W - 2) ($H - 2)
    $inner.BackColor = $C.Card
    $outer.Controls.Add($inner)
    return @{ Outer = $outer; Inner = $inner }
}

# Fine bande bleue en haut des fenêtres
function New-AccentBar([int]$W) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = Pt 0 0
    $p.Size = Sz $W 4
    $p.BackColor = $C.Accent
    return $p
}

# Logo
function Get-LogoImage {
    try {
        if ($LogoBase64 -and $LogoBase64.Length -gt 100) {
            $bytes = [Convert]::FromBase64String($LogoBase64)
            $ms = New-Object System.IO.MemoryStream($bytes, 0, $bytes.Length)
            $tmp = [System.Drawing.Image]::FromStream($ms)
            $copy = New-Object System.Drawing.Bitmap($tmp)
            $tmp.Dispose(); $ms.Close()
            return $copy
        }
    } catch {}
    try {
        # Solution de secours : un fichier icon.jpg à côté du script
        $folder = if ($PSCommandPath) { Split-Path $PSCommandPath } else { Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
        $file = Join-Path $folder "icon.jpg"
        if (Test-Path -LiteralPath $file) { return [System.Drawing.Image]::FromFile($file) }
    } catch {}
    return $null
}
$LogoImage = Get-LogoImage
$AppIcon = $null
try { if ($LogoImage) { $AppIcon = [System.Drawing.Icon]::FromHandle((New-Object System.Drawing.Bitmap($LogoImage)).GetHicon()) } } catch {}

# =====================================================================
# 3. PETITES FENÊTRES : support / à propos et activation
# =====================================================================
function New-Dialog([string]$Title, [int]$W, [int]$H) {
    $d = New-Object System.Windows.Forms.Form
    $d.Text = $Title
    $d.ClientSize = Sz $W $H
    $d.StartPosition = "CenterScreen"
    $d.FormBorderStyle = "FixedDialog"
    $d.MaximizeBox = $false
    $d.MinimizeBox = $false
    $d.Font = $F.Normal
    $d.BackColor = $C.White
    if ($AppIcon) { $d.Icon = $AppIcon }
    $d.Controls.Add((New-AccentBar $W))
    return $d
}

function Show-SupportDialog {
    $d = New-Dialog "À propos et support" 460 372

    if ($LogoImage) {
        $pic = New-Object System.Windows.Forms.PictureBox
        $pic.Location = Pt 24 24
        $pic.Size = Sz 64 64
        $pic.SizeMode = "Zoom"
        $pic.Image = $LogoImage
        $d.Controls.Add($pic)
    }
    $d.Controls.Add((New-Label $App.Name 104 28 $C.Text $F.H2))
    $d.Controls.Add((New-Label ("Version " + $App.Version + "  -  Tous droits réservés") 104 56 $C.Muted))

    $desc = New-Label ("Installe $TotalCount modules Bentley l'un après l'autre : MSI / MSP / EXE en mode silencieux, et assistants manuels pour les modules 13, 14 et 15.") 24 104 $C.Text
    $desc.AutoSize = $false
    $desc.Size = Sz 412 44
    $d.Controls.Add($desc)

    $line = New-Object System.Windows.Forms.Panel
    $line.Location = Pt 24 160
    $line.Size = Sz 412 1
    $line.BackColor = $C.Border
    $d.Controls.Add($line)

    $d.Controls.Add((New-Label "DÉVELOPPÉ PAR" 24 176 $C.Muted $F.Small))
    $d.Controls.Add((New-Label $App.Author 24 194 $C.Text $F.Bold))
    $d.Controls.Add((New-Label "E-MAIL" 24 226 $C.Muted $F.Small))
    $d.Controls.Add((New-Label "WHATSAPP" 260 226 $C.Muted $F.Small))

    $lnkMail = New-Object System.Windows.Forms.LinkLabel
    $lnkMail.Text = $App.Mail
    $lnkMail.Location = Pt 24 244
    $lnkMail.AutoSize = $true
    $lnkMail.LinkColor = $C.Accent
    $d.Controls.Add($lnkMail)

    $lnkWa = New-Object System.Windows.Forms.LinkLabel
    $lnkWa.Text = $App.Phone
    $lnkWa.Location = Pt 260 244
    $lnkWa.AutoSize = $true
    $lnkWa.LinkColor = $C.Ok
    $d.Controls.Add($lnkWa)

    $lblInfo = New-Label "" 24 282 $C.Ok
    $d.Controls.Add($lblInfo)

    $btnMail  = New-Button "Copier l'e-mail"   24  316 130
    $btnPhone = New-Button "Copier le numéro"  162 316 140
    $btnClose = New-Button "Fermer"            326 316 110 34 "Primary"
    $d.Controls.AddRange(@($btnMail, $btnPhone, $btnClose))

    $lnkMail.Add_LinkClicked({ try { Start-Process ("mailto:" + $App.Mail) } catch {} })
    $lnkWa.Add_LinkClicked({ try { Start-Process $App.WhatsApp } catch {} })
    $btnMail.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($App.Mail); $lblInfo.Text = "Adresse e-mail copiée." })
    $btnPhone.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($App.Phone); $lblInfo.Text = "Numéro copié." })
    $btnClose.Add_Click({ $d.Close() })
    $d.CancelButton = $btnClose

    [void]$d.ShowDialog()
}

# Demande le code d'activation. Renvoie $true si le code est correct.
function Show-LicenseDialog {
    $result = @{ Ok = $false }
    $d = New-Dialog "Activation" 420 300

    $d.Controls.Add((New-Label "Activation requise" 24 24 $C.Text $F.Title))
    $d.Controls.Add((New-Label "Entrez votre code d'activation pour lancer l'installateur." 24 58 $C.Muted))
    $d.Controls.Add((New-Label "CODE D'ACTIVATION" 24 92 $C.Muted $F.Small))

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = Pt 24 112
    $txt.Size = Sz 372 28
    $txt.Font = New-Font 11
    $txt.UseSystemPasswordChar = $true
    $d.Controls.Add($txt)

    $lblErr = New-Label "" 24 146 $C.Bad
    $d.Controls.Add($lblErr)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = "Afficher le code"
    $chk.Location = Pt 24 170
    $chk.AutoSize = $true
    $chk.ForeColor = $C.Muted
    $d.Controls.Add($chk)

    $btnOk      = New-Button "Valider"              24  204 372 38 "Primary"
    $btnSupport = New-Button "Contacter le support" 24  254 182
    $btnQuit    = New-Button "Quitter"              214 254 182
    $d.Controls.AddRange(@($btnOk, $btnSupport, $btnQuit))

    $chk.Add_CheckedChanged({ $txt.UseSystemPasswordChar = -not $chk.Checked })
    $btnOk.Add_Click({
        if ($txt.Text.Trim() -eq $App.LicenseCode) {
            $result.Ok = $true
            $d.Close()
        } else {
            $lblErr.Text = "Code incorrect. Réessayez ou contactez le support."
            $txt.Clear()
            $txt.Focus()
        }
    })
    $btnSupport.Add_Click({ Show-SupportDialog })
    $btnQuit.Add_Click({ $d.Close() })
    $d.AcceptButton = $btnOk
    $d.CancelButton = $btnQuit
    $d.Add_Shown({ $txt.Focus() })

    [void]$d.ShowDialog()
    return $result.Ok
}

# =====================================================================
# 4. FENÊTRE PRINCIPALE  (taille fixe 980 x 730, tout est placé en x / y)
# =====================================================================
$Form = New-Object System.Windows.Forms.Form
$Form.Text = $App.Name + "  v" + $App.Version
$Form.ClientSize = Sz 980 730
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedSingle"
$Form.MaximizeBox = $false
$Form.Font = $F.Normal
$Form.BackColor = $C.Bg
if ($AppIcon) { $Form.Icon = $AppIcon }

# --- En-tête ---------------------------------------------------------
$header = New-Object System.Windows.Forms.Panel
$header.Location = Pt 0 4
$header.Size = Sz 980 64
$header.BackColor = $C.White

$picLogo = New-Object System.Windows.Forms.PictureBox
$picLogo.Location = Pt 20 12
$picLogo.Size = Sz 40 40
$picLogo.SizeMode = "Zoom"
if ($LogoImage) { $picLogo.Image = $LogoImage }

$lnkAbout = New-Object System.Windows.Forms.LinkLabel
$lnkAbout.Text = "À propos et support"
$lnkAbout.Location = Pt 760 22
$lnkAbout.Size = Sz 200 20
$lnkAbout.TextAlign = "MiddleRight"
$lnkAbout.LinkColor = $C.Muted
$lnkAbout.ActiveLinkColor = $C.Accent

$header.Controls.AddRange(@(
    $picLogo,
    (New-Label $App.Name 72 12 $C.Text $F.Title),
    (New-Label "Installation automatique de $TotalCount modules Bentley" 74 40 $C.Muted),
    $lnkAbout
))

$headerLine = New-Object System.Windows.Forms.Panel
$headerLine.Location = Pt 0 68
$headerLine.Size = Sz 980 1
$headerLine.BackColor = $C.Border

# --- Les 3 étapes ------------------------------------------------------
function New-StepCard([int]$X, [string]$Num, [string]$Caption) {
    $card = New-Card $X 84 300 72

    $badge = New-Object System.Windows.Forms.Label
    $badge.Text = $Num
    $badge.Font = $F.H2
    $badge.ForeColor = $C.White
    $badge.TextAlign = "MiddleCenter"
    $badge.Location = Pt 16 19
    $badge.Size = Sz 34 34

    $cap = New-Label $Caption 64 14 $C.Muted $F.Small
    $val = New-Label "" 64 34 $C.Text $F.Bold
    $val.AutoSize = $false
    $val.Size = Sz 224 22
    $val.AutoEllipsis = $true

    $card.Inner.Controls.AddRange(@($badge, $cap, $val))
    return @{ Outer = $card.Outer; Inner = $card.Inner; Badge = $badge; Cap = $cap; Val = $val; Num = $Num }
}
$Step1 = New-StepCard 20  "1" "DOSSIER SOURCE"
$Step2 = New-StepCard 340 "2" "VÉRIFICATION"
$Step3 = New-StepCard 660 "3" "INSTALLATION"

# --- Liste des modules ---------------------------------------------------
$gridCard = New-Card 20 170 940 270
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = "Fill"
$grid.BorderStyle = "None"
$grid.BackgroundColor = $C.Card
$grid.GridColor = $C.Border
$grid.CellBorderStyle = "SingleHorizontal"
$grid.ColumnHeadersBorderStyle = "None"
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersHeightSizeMode = "DisableResizing"
$grid.ColumnHeadersHeight = 32
$grid.RowTemplate.Height = 28
$grid.RowHeadersVisible = $false
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.ReadOnly = $true
$grid.TabStop = $false
$grid.AutoSizeColumnsMode = "Fill"
$grid.ColumnHeadersDefaultCellStyle.BackColor = $C.Bg
$grid.ColumnHeadersDefaultCellStyle.ForeColor = $C.Muted
$grid.ColumnHeadersDefaultCellStyle.Font = $F.Small
$grid.ColumnHeadersDefaultCellStyle.SelectionBackColor = $C.Bg
$grid.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
$grid.DefaultCellStyle.BackColor = $C.Card
$grid.DefaultCellStyle.ForeColor = $C.Text
$grid.DefaultCellStyle.Font = $F.Normal
$grid.DefaultCellStyle.SelectionBackColor = $C.Card
$grid.DefaultCellStyle.SelectionForeColor = $C.Text
$grid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
[void]$grid.Columns.Add("Num", "N°")
[void]$grid.Columns.Add("Module", "MODULE")
[void]$grid.Columns.Add("Fichier", "FICHIER DÉTECTÉ")
[void]$grid.Columns.Add("Mode", "MODE")
[void]$grid.Columns.Add("Statut", "STATUT")
$grid.Columns[0].FillWeight = 7
$grid.Columns[1].FillWeight = 33
$grid.Columns[2].FillWeight = 34
$grid.Columns[3].FillWeight = 9
$grid.Columns[4].FillWeight = 17

$RowIndex = @{}   # numéro du module -> numéro de ligne dans la liste
foreach ($m in $Modules) {
    $mode = if ($m.Manual) { "Manuel" } else { "Auto" }
    $RowIndex[$m.Num] = $grid.Rows.Add($m.Num, $m.Name, "-", $mode, "")
    if ($m.Manual) { $grid.Rows[$RowIndex[$m.Num]].Cells[3].Style.ForeColor = $C.Warn }
}
$grid.Add_SelectionChanged({ $grid.ClearSelection() })   # pas de surbrillance bleue
$gridCard.Inner.Controls.Add($grid)

# --- Journal -------------------------------------------------------------
$lblLog = New-Label "Journal" 22 454 $C.Text $F.H2
$btnOpenLog  = New-Button "Ouvrir le fichier" 760 449 130 28
$btnClearLog = New-Button "Effacer"           898 449 62  28

$logCard = New-Card 20 482 940 118
$logCard.Inner.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Dock = "Fill"
$txtLog.BorderStyle = "None"
$txtLog.ReadOnly = $true
$txtLog.DetectUrls = $false
$txtLog.BackColor = $C.Card
$txtLog.Font = $F.Mono
$logCard.Inner.Controls.Add($txtLog)

# --- Barre du bas : progression + boutons ---------------------------------
$actionCard = New-Card 20 612 940 84
$lblProgress = New-Label "" 18 14 $C.Muted $F.Bold
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = Pt 18 42
$progress.Size = Sz 600 18
$progress.Minimum = 0
$progress.Maximum = $TotalCount
$progress.Style = "Continuous"
$btnCancel = New-Button "Annuler" 640 22 100 40
$btnMain   = New-Button "Choisir le dossier" 752 22 172 40 "Primary"
$actionCard.Inner.Controls.AddRange(@($lblProgress, $progress, $btnCancel, $btnMain))

# --- Pied de page -----------------------------------------------------------
$lblFootL = New-Label ("Journal : " + $LogFile) 22 706 $C.Dim (New-Font 8)
$lblFootR = New-Label ("v" + $App.Version + "  -  " + $App.Author) 660 706 $C.Dim (New-Font 8)
$lblFootR.AutoSize = $false
$lblFootR.Size = Sz 300 16
$lblFootR.TextAlign = "MiddleRight"

$Form.Controls.AddRange(@(
    (New-AccentBar 980), $header, $headerLine,
    $Step1.Outer, $Step2.Outer, $Step3.Outer,
    $gridCard.Outer,
    $lblLog, $btnOpenLog, $btnClearLog, $logCard.Outer,
    $actionCard.Outer,
    $lblFootL, $lblFootR
))
$tip = New-Object System.Windows.Forms.ToolTip

# =====================================================================
# 5. LOGIQUE
# =====================================================================

# --- Affichage ----------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message
    $color = switch ($Level) {
        "OK"     { $C.Ok }
        "WARN"   { $C.Warn }
        "ERREUR" { $C.Bad }
        default  { $C.Text }
    }
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    $txtLog.SelectionColor = $color
    $txtLog.AppendText($line + "`r`n")
    $txtLog.ScrollToCaret()
    try { Add-Content -Path $LogFile -Value ("[{0}] {1}" -f $Level, $line) -Encoding UTF8 } catch {}
    [System.Windows.Forms.Application]::DoEvents()
}

# Change l'aspect d'une carte d'étape : Idle (gris) / Active (bleu) / Done (vert) / Error (rouge)
function Set-Step($Card, [string]$State, [string]$Text) {
    $color = $C.Dim
    switch ($State) {
        "Active" { $color = $C.Accent }
        "Done"   { $color = $C.Ok }
        "Error"  { $color = $C.Bad }
    }
    $Card.Outer.BackColor = if ($State -eq "Idle") { $C.Border } else { $color }
    $Card.Badge.BackColor = $color
    $Card.Badge.Text = if ($State -eq "Done") { [string][char]0x2713 } else { $Card.Num }
    $Card.Val.Text = $Text
    $Card.Val.ForeColor = if ($State -eq "Idle") { $C.Muted } else { $C.Text }
}

function Update-Progress {
    $finished = @($Modules | Where-Object { $script:Status[$_.Num] -in @("Ok", "Failed") }).Count
    $progress.Value = [Math]::Min($finished, $TotalCount)
    $pct = [Math]::Round(100 * $finished / $TotalCount)
    $lblProgress.Text = "Progression globale   $finished / $TotalCount modules   ($pct%)"
}

# Change le statut d'un module (liste + progression)
function Set-Status([string]$Num, [string]$State) {
    $script:Status[$Num] = $State
    $style = $StatusStyle[$State]
    $cell = $grid.Rows[$RowIndex[$Num]].Cells[4]
    $cell.Value = $style.Text
    $cell.Style.ForeColor = $style.Fore
    $cell.Style.BackColor = $style.Back
    $cell.Style.Font = $F.Bold
    if ($State -eq "Running") {
        try { $grid.FirstDisplayedScrollingRowIndex = [Math]::Max(0, $RowIndex[$Num] - 3) } catch {}
    }
    Update-Progress
    [System.Windows.Forms.Application]::DoEvents()
}

# Met à jour toute l'interface selon l'état du programme
function Update-UI {
    if ($script:SourceFolder) { Set-Step $Step1 "Done" $script:SourceFolder }
    else                      { Set-Step $Step1 "Active" "Cliquer pour choisir..." }
    $tip.SetToolTip($Step1.Val, $script:SourceFolder)

    if ($script:Verified)         { Set-Step $Step2 "Done" "$TotalCount / $TotalCount fichiers trouvés" }
    elseif ($script:VerifyError)  { Set-Step $Step2 "Error" $script:VerifyError }
    else                          { Set-Step $Step2 "Idle" "En attente du dossier" }

    if ($script:Done)             { Set-Step $Step3 "Done" "Installation terminée" }
    elseif ($script:Running)      { Set-Step $Step3 "Active" "En cours..." }
    elseif ($script:Verified)     { Set-Step $Step3 "Active" "Prêt à installer" }
    else                          { Set-Step $Step3 "Idle" "En attente de la vérification" }

    if     ($script:Running)  { $btnMain.Text = "Installation en cours..."; $enabled = $false }
    elseif ($script:Done)     { $btnMain.Text = "Terminer";                 $enabled = $true }
    elseif ($script:Verified) { $btnMain.Text = "Lancer l'installation";    $enabled = $true }
    else                      { $btnMain.Text = "Choisir le dossier";       $enabled = $true }
    $btnMain.Enabled = $enabled
    $btnMain.BackColor = if ($enabled) { $C.Accent } else { $C.Dim }
    $btnMain.FlatAppearance.BorderColor = $btnMain.BackColor
    $btnCancel.Enabled = $script:Running

    Update-Progress
    [System.Windows.Forms.Application]::DoEvents()
}

# --- Étapes 1 et 2 : dossier + vérification -------------------------------
function Find-ModuleFile([string]$Folder, [string]$Num, [string]$Pattern) {
    $files = Get-ChildItem -LiteralPath $Folder -File -ErrorAction SilentlyContinue
    if (-not $files) { return $null }
    # 1) motif complet   2) à défaut, simple numéro au début du nom
    $hit = $files | Where-Object { $_.Name.Trim() -like $Pattern } | Select-Object -First 1
    if (-not $hit) { $hit = $files | Where-Object { $_.Name.Trim() -like ("{0}*" -f $Num) } | Select-Object -First 1 }
    return $hit
}

function Invoke-Verification {
    $script:Verified = $false
    $script:Done = $false
    $script:VerifyError = ""
    $script:Files = @{}
    $missing = @()
    Write-Log "Vérification des $TotalCount fichiers..."

    foreach ($m in $Modules) {
        $found = Find-ModuleFile $script:SourceFolder $m.Num $m.Pattern
        $cell = $grid.Rows[$RowIndex[$m.Num]].Cells[2]
        if ($found) {
            $script:Files[$m.Num] = $found.FullName
            $cell.Value = $found.Name
            $cell.Style.ForeColor = $C.Text
        } else {
            $missing += ("{0} - {1}" -f $m.Num, $m.Name)
            $cell.Value = "Fichier introuvable"
            $cell.Style.ForeColor = $C.Bad
        }
        Set-Status $m.Num "Pending"
    }

    if ($missing.Count -gt 0) {
        $script:VerifyError = "{0} fichier(s) manquant(s)" -f $missing.Count
        Write-Log ("Fichiers manquants : " + ($missing -join ", ")) "ERREUR"
        Update-UI
        [void][System.Windows.Forms.MessageBox]::Show($Form,
            ("Fichiers manquants ({0}) :`r`n`r`n- {1}`r`n`r`nChoisissez un autre dossier." -f $missing.Count, ($missing -join "`r`n- ")),
            "Vérification échouée", "OK", "Error")
    } else {
        $script:Verified = $true
        Write-Log "Vérification réussie : $TotalCount / $TotalCount fichiers trouvés." "OK"
        Update-UI
    }
}

function Select-SourceFolder {
    if ($script:Running) { return }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Sélectionnez le dossier contenant les fichiers d'installation Bentley."
    $dlg.ShowNewFolderButton = $false
    if ($script:SourceFolder) { $dlg.SelectedPath = $script:SourceFolder }
    if ($dlg.ShowDialog($Form) -eq "OK") {
        $script:SourceFolder = $dlg.SelectedPath
        Write-Log ("Dossier source : " + $script:SourceFolder)
        Invoke-Verification
    }
}

# --- Étape 3 : installation ------------------------------------------------
# Attend la fin d'un programme sans geler la fenêtre
function Wait-ProcessResponsive($Proc) {
    while (-not $Proc.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 150
    }
}

# Installation silencieuse d'un module. Renvoie le code de sortie (0 = succès).
function Invoke-SilentInstall([string]$File, [string]$Num) {
    $name = Split-Path $File -Leaf
    $msiLog = Join-Path $env:TEMP ("Bentley_{0}_{1:yyyyMMdd_HHmmss}.log" -f $Num, (Get-Date))
    switch ([System.IO.Path]::GetExtension($File).ToLower()) {
        ".msi"  { $program = "msiexec.exe"; $argList = "/i `"$File`" /qn /norestart /l*v `"$msiLog`"" }
        ".msp"  { $program = "msiexec.exe"; $argList = "/p `"$File`" /qn /norestart /l*v `"$msiLog`"" }
        default { $program = $File;         $argList = $SilentExeArgs }
    }
    Write-Log "Installation silencieuse : $name"
    try {
        $p = Start-Process -FilePath $program -ArgumentList $argList -PassThru
        $null = $p.Handle
        Wait-ProcessResponsive $p
        return [int]$p.ExitCode
    } catch {
        Write-Log ("Impossible de lancer {0} : {1}" -f $name, $_.Exception.Message) "ERREUR"
        return 9999
    }
}

# Installation manuelle (modules 13, 14, 15). Renvoie "Ok", "Failed" ou "Cancel".
function Invoke-ManualInstall($Module, [string]$File) {
    $name = Split-Path $File -Leaf
    Set-Status $Module.Num "Manual"
    Write-Log ("Module {0} : installation manuelle requise ({1})." -f $Module.Num, $name) "WARN"

    [void][System.Windows.Forms.MessageBox]::Show($Form,
        ("Module {0} - {1}`r`n`r`n1. L'assistant d'installation va s'ouvrir.`r`n2. Faites l'installation manuellement.`r`n3. Fermez l'assistant, puis confirmez le résultat." -f $Module.Num, $Module.Name),
        "Action requise", "OK", "Information")

    try {
        $p = Start-Process -FilePath $File -PassThru
        $null = $p.Handle
        Wait-ProcessResponsive $p
    } catch {
        Write-Log ("Impossible d'ouvrir {0} : {1}" -f $name, $_.Exception.Message) "ERREUR"
    }

    $answer = [System.Windows.Forms.MessageBox]::Show($Form,
        ("Le module {0} est-il bien installé ?`r`n`r`nOui = succès`r`nNon = échec`r`nAnnuler = arrêter l'installation`r`n`r`n(Si l'assistant est encore ouvert, terminez-le avant de répondre.)" -f $Module.Num),
        "Confirmation - module $($Module.Num)", "YesNoCancel", "Question")
    if ($answer -eq "Yes") { return "Ok" }
    if ($answer -eq "No")  { return "Failed" }
    return "Cancel"
}

function Start-Installation {
    if ($script:Running -or -not $script:Verified) { return }
    $script:Running = $true
    $script:Done = $false
    $script:CancelRequested = $false
    $script:RestartNeeded = $false
    foreach ($m in $Modules) { Set-Status $m.Num "Pending" }
    Update-UI
    Write-Log "===== DÉBUT DE L'INSTALLATION ($TotalCount modules) ====="

    $ok = 0; $ko = 0
    foreach ($m in $Modules) {
        if ($script:CancelRequested) { Write-Log "Installation interrompue." "WARN"; break }

        Set-Status $m.Num "Running"
        Write-Log ("--- [{0}] {1} ---" -f $m.Num, $m.Name)
        $file = $script:Files[$m.Num]

        if ($m.Manual) {
            $answer = Invoke-ManualInstall $m $file
            if ($answer -eq "Cancel") {
                Set-Status $m.Num "Pending"
                $script:CancelRequested = $true
                Write-Log "Installation arrêtée par l'utilisateur." "WARN"
                break
            }
            $success = ($answer -eq "Ok")
        } else {
            $code = Invoke-SilentInstall $file $m.Num
            $success = ($code -in @(0, 1641, 3010))      # 1641 / 3010 = réussi, redémarrage nécessaire
            if ($success -and $code -ne 0) {
                $script:RestartNeeded = $true
                Write-Log ("Module {0} : un redémarrage de Windows sera nécessaire (code {1})." -f $m.Num, $code) "WARN"
            }
            if (-not $success) { Write-Log ("Module {0} : code d'erreur {1}." -f $m.Num, $code) "ERREUR" }
        }

        if ($success) {
            Set-Status $m.Num "Ok"; $ok++
            Write-Log ("Module {0} : succès." -f $m.Num) "OK"
        } else {
            Set-Status $m.Num "Failed"; $ko++
            Write-Log ("Module {0} : échec." -f $m.Num) "ERREUR"
        }
    }

    $script:Running = $false
    $script:Done = -not $script:CancelRequested
    Write-Log ("===== FIN : {0} succès, {1} échec(s) =====" -f $ok, $ko)
    Update-UI

    # Rapport final
    $failed = @($Modules | Where-Object { $script:Status[$_.Num] -eq "Failed" } | ForEach-Object { "{0} - {1}" -f $_.Num, $_.Name })
    $report = "Réussis : $ok     Échecs : $ko"
    if ($failed.Count -gt 0)       { $report += "`r`n`r`nModules en échec :`r`n- " + ($failed -join "`r`n- ") }
    if ($script:RestartNeeded)     { $report += "`r`n`r`nUn redémarrage de Windows est recommandé." }
    $report += "`r`n`r`nJournal : $LogFile"
    $title = if ($script:CancelRequested) { "Installation interrompue" } else { "Installation terminée" }
    $icon  = if ($ko -eq 0 -and -not $script:CancelRequested) { "Information" } else { "Warning" }
    [void][System.Windows.Forms.MessageBox]::Show($Form, $report, $title, "OK", $icon)
}

# =====================================================================
# 6. ÉVÉNEMENTS ET LANCEMENT
# =====================================================================
foreach ($c in @($Step1.Inner, $Step1.Badge, $Step1.Cap, $Step1.Val)) {
    $c.Cursor = [System.Windows.Forms.Cursors]::Hand
    $c.Add_Click({ Select-SourceFolder })
}

$btnMain.Add_Click({
    if ($script:Running)       { return }
    elseif ($script:Done)      { $Form.Close() }
    elseif ($script:Verified)  { Start-Installation }
    else                       { Select-SourceFolder }
})
$btnCancel.Add_Click({
    $script:CancelRequested = $true
    Write-Log "Arrêt demandé : l'installation s'arrêtera après le module en cours." "WARN"
})
$btnOpenLog.Add_Click({ try { Start-Process notepad.exe $LogFile } catch {} })
$btnClearLog.Add_Click({ $txtLog.Clear() })
$lnkAbout.Add_LinkClicked({ Show-SupportDialog })

$Form.Add_FormClosing({
    if ($script:Running) {
        $r = [System.Windows.Forms.MessageBox]::Show("Une installation est en cours. Quitter quand même ?", "Confirmer", "YesNo", "Warning")
        if ($r -ne "Yes") { $_.Cancel = $true }
    }
})

# Activation d'abord : sans le bon code, rien ne se lance
if (-not (Show-LicenseDialog)) { exit }

foreach ($m in $Modules) { Set-Status $m.Num "Pending" }
Write-Log "Programme prêt. Étape 1 : choisissez le dossier des installateurs."
Update-UI

# La fenêtre de choix du dossier s'ouvre toute seule au démarrage
$Form.Add_Shown({ Select-SourceFolder })
[void]$Form.ShowDialog()
