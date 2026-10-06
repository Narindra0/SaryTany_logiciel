# ==================================================================
# src\55-License.ps1  -  Verrou de licence (code unique)
#   Ecran d'activation affiche au demarrage, avant la construction de
#   l'assistant : un seul code debloque l'acces : ICECREAM
#   (licence Bentley CONNECT). La saisie est MASQUEE (points) et
#   aucun code n'est affiche a l'ecran.
#   Toute fermeture sans validation arrete l'application.
#   Outils de developpement : -AutoTest / -RenderTo ignorent le verrou ;
#   -RenderLicense capture l'ecran de licence vers le fichier de -RenderTo.
# Design : Neo-Carbon (barre de titre sombre, carte blanche, badge code).
# Depend de : src\40-Theme.ps1 et src\50-Widgets.ps1 (habillage).
# ==================================================================

$script:LicenseCodes = @{
    'ICECREAM' = @{ Label = 'Bentley CONNECT' ; Level = 'bentley' }
}

$script:LicenseValidated   = $false
$script:LicenseLevel       = 'none'
$script:LicenseValidatedAt = $null

# Nombre de lancements en mode essai (incremente par 72-View-SintegraLidar).
$script:TrialLaunchesUsed = 0

function Test-LicenseCode {
    <#
        Analyse le code saisi : seul ICECREAM est accepte
        (comparaison insensible a la casse et aux espaces).
        Renvoie (true/false) et valorise $script:LicenseLevel.
    #>
    param([string]$Code)
    if (-not $Code) { return $false }
    $trimmed = $Code.Trim().ToUpperInvariant()

    if ($trimmed -eq 'ICECREAM') {
        $script:LicenseLevel = 'bentley'; return $true
    }
    return $false
}

function New-LicenseWindow {
    # Construit la fenetre d'activation (non affichee).
    $licenseWin = New-Object System.Windows.Forms.Form
    $licenseWin.Text = "Licence - Assistant Sarytany Neo-Carbon"
    $licenseWin.ClientSize = New-Object System.Drawing.Size(460, 310)
    $licenseWin.StartPosition = "CenterScreen"
    $licenseWin.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $licenseWin.BackColor = $script:C_Bg
    $licenseWin.Font = $script:FontUI
    $licenseWin.TopMost = $true
    $licenseIcon = Get-AppIcon
    if ($licenseIcon) { $licenseWin.Icon = $licenseIcon; $licenseWin.ShowIcon = $true }
    Set-DoubleBuffer $licenseWin

    # --- Barre de titre (deplacable, sombre) ---
    $titleH = 58
    $licenseBar = New-Object System.Windows.Forms.Panel
    $licenseBar.Dock = "Top"
    $licenseBar.Height = $titleH
    $licenseBar.BackColor = $script:C_Title
    $licenseWin.Controls.Add($licenseBar)

    # Badge marque (losange)
    $licenseMark = New-Object System.Windows.Forms.Panel
    $licenseMark.Location = New-Object System.Drawing.Point(18, 15)
    $licenseMark.Size = New-Object System.Drawing.Size(28, 28)
    $licenseMark.BackColor = $script:C_Accent
    Set-RoundRegion $licenseMark 8
    $licenseMark.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        Set-SmoothingMode $g 'AntiAlias'
        $pts = @(
            (New-Object System.Drawing.PointF(14, 6)),
            (New-Object System.Drawing.PointF(22, 14)),
            (New-Object System.Drawing.PointF(14, 22)),
            (New-Object System.Drawing.PointF(6, 14))
        )
        $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        $g.FillPolygon($br, $pts)
        $br.Dispose()
    })
    $licenseBar.Controls.Add($licenseMark)

    $licenseBar.Controls.Add((New-TextLabel -Text "Activation du produit" -X 54 -Y 9 -W 300 -H 20 -Font $script:FontSemB -Fore ([System.Drawing.Color]::White)))
    $licenseBar.Controls.Add((New-TextLabel -Text "Sarytany - Assistant deploiement Neo-Carbon" -X 55 -Y 29 -W 320 -H 16 -Font $script:FontMini -Fore $script:C_TxtIn2))

    # Bouton fermeture
    $btnClose = New-ModernButton -Text ([string][char]0x2715) -X 416 -Y 14 -W 30 -H 30 `
        -Fill ([System.Drawing.Color]::FromArgb(45, 54, 68)) -Hover $script:C_Red `
        -Font (New-Object System.Drawing.Font('Segoe UI', 10))
    $licenseBar.Controls.Add($btnClose)

    # Drag de la fenetre par la barre de titre
    $script:LicenseDragOffset = $null
    $licenseBar.Add_MouseDown({ param($s, $e) $script:LicenseDragOffset = New-Object System.Drawing.Point($e.X, $e.Y) })
    $licenseBar.Add_MouseMove({
        param($s, $e)
        $f = $s.FindForm()
        if ($script:LicenseDragOffset -and $f) {
            $screen = $s.PointToScreen($e.Location)
            $f.Location = New-Object System.Drawing.Point(($screen.X - $script:LicenseDragOffset.X), ($screen.Y - $script:LicenseDragOffset.Y))
        }
    })
    $licenseBar.Add_MouseUp({ param($s, $e) $script:LicenseDragOffset = $null })

    # --- Carte d'activation ---
    $licenseCard = New-RoundedPanel -W 410 -H 212 -R 12
    $licenseCard.Location = New-Object System.Drawing.Point(24, ($titleH + 6))
    $licenseWin.Controls.Add($licenseCard)

    $licenseCard.Controls.Add((New-TextLabel -Text "Licence requise" -X 24 -Y 16 -W 360 -H 24 -Font (New-Object System.Drawing.Font('Segoe UI Semibold', 12, [System.Drawing.FontStyle]::Bold))))
    $licenseCard.Controls.Add((New-TextLabel -Text "Saisissez le code de licence pour debloquer l'assistant." -X 24 -Y 44 -W 360 -H 16 -Font $script:FontUI -Fore $script:C_Muted))
    $licenseCard.Controls.Add((New-TextLabel -Text "Code confidentiel - demandez-le a votre administrateur." -X 24 -Y 64 -W 360 -H 16 -Font $script:FontMini -Fore $script:C_Muted))
    $licenseCard.Controls.Add((New-TextLabel -Text "Code de licence" -X 24 -Y 86 -W 120 -H 16 -Font $script:FontUI))

    $licenseCodeBox = New-Object System.Windows.Forms.TextBox
    $licenseCodeBox.Location = New-Object System.Drawing.Point(24, 106)
    $licenseCodeBox.Size = New-Object System.Drawing.Size(360, 28)
    $licenseCodeBox.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $licenseCodeBox.CharacterCasing = [System.Windows.Forms.CharacterCasing]::Upper
    $licenseCodeBox.UseSystemPasswordChar = $true   # saisie masquee (points)
    $licenseCard.Controls.Add($licenseCodeBox)

    $licenseError = New-TextLabel -Text "Code invalide." -X 24 -Y 138 -W 330 -H 16 -Font $script:FontUI -Fore $script:C_Red
    $licenseError.Visible = $false
    $licenseCard.Controls.Add($licenseError)

    # Badge niveau de licence
    $script:LicenseBadgeLevel = New-RoundedPanel -W 96 -H 26 -R 13 -Fill ([System.Drawing.Color]::FromArgb(26, 206, 212, 220))
    $script:LicenseBadgeLevel.Location = New-Object System.Drawing.Point(300, 14)
    $script:LicenseBadgeLevel.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        Set-SmoothingMode $g 'AntiAlias'
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        $tb = New-Object System.Drawing.SolidBrush $script:C_Muted
        $g.DrawString("AUCUNE", $script:FontMini, $tb, (New-Object System.Drawing.RectangleF(0, 0, $s.Width, $s.Height)), $sf)
        $tb.Dispose(); $sf.Dispose()
    })
    $licenseCard.Controls.Add($script:LicenseBadgeLevel)

    $btnOk = New-ModernButton -Text "Valider / Deverrouiller" -X 24 -Y 166 -W 250 -H 36
    $licenseCard.Controls.Add($btnOk)

    $btnQuit = New-ModernButton -Text "Quitter" -X 282 -Y 166 -W 90 -H 36 `
        -Fill ([System.Drawing.Color]::FromArgb(198, 205, 214)) -Hover ([System.Drawing.Color]::FromArgb(176, 184, 194)) `
        -Fore ([System.Drawing.Color]::FromArgb(45, 52, 62))
    $licenseCard.Controls.Add($btnQuit)

    $licenseWin.AcceptButton = $btnOk
    $licenseWin.CancelButton = $btnQuit
    $licenseWin.ActiveControl = $licenseCodeBox

    # --- Actions ---
    $licenseCodeBox.Tag = $licenseError
    $licenseCodeBox.Add_TextChanged({ param($s, $e) $s.Tag.Visible = $false })

    $btnOk.Tag.Win   = $licenseWin
    $btnOk.Tag.Code  = $licenseCodeBox
    $btnOk.Tag.Error = $licenseError
    $btnOk.Tag.Badge = $script:LicenseBadgeLevel
    $btnOk.Add_Click({
        param($s, $e)
        if (Test-LicenseCode $s.Tag.Code.Text) {
            # Met a jour le badge visuel du niveau de licence
            $lvl = $script:LicenseLevel
            $s.Tag.Badge.Tag.Level = $lvl
            $s.Tag.Badge.Invalidate()
            $script:LicenseValidated = $true
            $script:LicenseValidatedAt = (Get-Date).ToString('g')
            $s.Tag.Win.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $s.Tag.Win.Close()
        } else {
            $s.Tag.Error.Visible = $true
            $s.Tag.Code.Clear()
            $s.Tag.Code.Focus()
        }
    })
    $btnQuit.Add_Click({ param($s, $e) $s.FindForm().Close() })

    return @{ Win = $licenseWin; Code = $licenseCodeBox; Error = $licenseError }
}

function Show-LicenseGate {
    # Affiche le verrou. Renvoie $true uniquement si le code a ete valide.
    if ($script:LicenseValidated) { return $true }
    $ui = New-LicenseWindow
    $ok = ($ui.Win.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
    if (-not $ok) { $script:LicenseValidated = $false }
    $ui.Win.Dispose()
    return $ok
}

function Show-LicenseRender {
    # Outil de developpement : capture l'ecran de licence vers $RenderTo (PNG).
    $ui = New-LicenseWindow
    $ui.Win.StartPosition = 'Manual'
    $ui.Win.Location = New-Object System.Drawing.Point(-4000, -4000)
    $ui.Win.Show()
    $ui.Win.Update()
    Start-Sleep -Milliseconds 400
    $bmp = New-Object System.Drawing.Bitmap $ui.Win.ClientSize.Width, $ui.Win.ClientSize.Height
    $ui.Win.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)))
    $bmp.Save($RenderTo, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $ui.Win.Close(); $ui.Win.Dispose()
}

# ================= EXECUTION DU VERROU =================
# Le mode GUI reel exige le code ; les outils de recette (-AutoTest,
# -RenderTo, -RenderLicense) travaillent sans verrou.
if ($RenderLicense -and $RenderTo) {
    Show-LicenseRender
    Write-Out "RENDER OK : $RenderTo"
    Stop-App 0
}
elseif (($Mode -eq 'GUI') -and (-not $AutoTest) -and (-not $RenderTo) -and (-not $RenderLicense)) {
    if (-not (Show-LicenseGate)) {
        Write-Out "Licence non validee : acces refuse." -ForegroundColor Red
        Stop-App 2
    }
    Write-Out "Licence validee ($($script:LicenseLevel)) - acces autorise."
}
