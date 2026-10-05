# ==================================================================
# src\55-License.ps1  -  Verrou de licence
#   Ecran d'activation affiche au demarrage, avant la construction de
#   l'assistant : seul le code attendu debloque la suite du chargement,
#   toute fermeture sans validation arrete l'application.
#   Outils de developpement : -AutoTest et -RenderTo ignorent le verrou ;
#   -RenderLicense capture l'ecran de licence vers le fichier de -RenderTo.
# Depend de : src\40-Theme.ps1 et src\50-Widgets.ps1 (habillage).
# ==================================================================
$script:LicenseCode      = 'LOV3'
$script:LicenseValidated = $false

function Test-LicenseCode {
    # Comparaison insensible a la casse et aux espaces de saisie.
    param([string]$Code)
    if (-not $Code) { return $false }
    return ($Code.Trim().ToUpperInvariant() -eq $script:LicenseCode)
}

function New-LicenseWindow {
    # Construit la fenetre d'activation (non affichee).
    $licenseWin = New-Object System.Windows.Forms.Form
    $licenseWin.Text = "Licence - Assistant Deploiement Bentley PowerDraft"
    $licenseWin.ClientSize = New-Object System.Drawing.Size(440, 302)
    $licenseWin.StartPosition = "CenterScreen"
    $licenseWin.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $licenseWin.BackColor = $script:C_Bg
    $licenseWin.Font = $script:FontUI
    $licenseWin.TopMost = $true
    $licenseIcon = Get-AppIcon
    if ($licenseIcon) { $licenseWin.Icon = $licenseIcon; $licenseWin.ShowIcon = $true }
    Set-DoubleBuffer $licenseWin

    # --- Barre de titre (deplacable comme celle de l'assistant) ---
    $licenseBar = New-Object System.Windows.Forms.Panel
    $licenseBar.Dock = "Top"
    $licenseBar.Height = 56
    $licenseBar.BackColor = $script:C_Title
    $licenseWin.Controls.Add($licenseBar)

    $licenseMark = New-Object System.Windows.Forms.Panel
    $licenseMark.Location = New-Object System.Drawing.Point(18, 15)
    $licenseMark.Size = New-Object System.Drawing.Size(26, 26)
    $licenseMark.BackColor = $script:C_Accent
    Set-RoundRegion $licenseMark 7
    $licenseMark.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $pts = @(
            (New-Object System.Drawing.PointF(13, 5)),
            (New-Object System.Drawing.PointF(21, 13)),
            (New-Object System.Drawing.PointF(13, 21)),
            (New-Object System.Drawing.PointF(5, 13))
        )
        $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        $g.FillPolygon($br, $pts)
        $br.Dispose()
    })
    $licenseBar.Controls.Add($licenseMark)

    $licenseBar.Controls.Add((New-TextLabel -Text "Activation du produit" -X 54 -Y 9 -W 300 -H 20 -Font $script:FontSemB -Fore ([System.Drawing.Color]::White)))
    $licenseBar.Controls.Add((New-TextLabel -Text "Assistant Deploiement Bentley PowerDraft - Sarytany" -X 55 -Y 29 -W 320 -H 16 -Font $script:FontMini -Fore $script:C_TxtIn2))

    $licenseBtnClose = New-ModernButton -Text ([string][char]0x2715) -X 396 -Y 13 -W 30 -H 30 -Fill ([System.Drawing.Color]::FromArgb(45, 54, 68)) -Hover $script:C_Red -Font (New-Object System.Drawing.Font('Segoe UI', 10))
    $licenseBar.Controls.Add($licenseBtnClose)
    $licenseBtnClose.Add_Click({ param($s, $e) $s.FindForm().Close() })

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
    $licenseCard = New-RoundedPanel -W 400 -H 210 -R 12
    $licenseCard.Location = New-Object System.Drawing.Point(20, 74)
    $licenseWin.Controls.Add($licenseCard)

    $licenseCard.Controls.Add((New-TextLabel -Text "Licence requise" -X 24 -Y 16 -W 352 -H 26 -Font (New-Object System.Drawing.Font('Segoe UI Semibold', 11, [System.Drawing.FontStyle]::Bold))))
    $licenseCard.Controls.Add((New-TextLabel -Text "Saisissez le code de licence pour debloquer l'assistant." -X 24 -Y 46 -W 352 -H 16 -Font $script:FontUI -Fore $script:C_Muted))
    $licenseCard.Controls.Add((New-TextLabel -Text "Code de licence" -X 24 -Y 76 -W 160 -H 16 -Font $script:FontUI))

    $licenseCodeBox = New-Object System.Windows.Forms.TextBox
    $licenseCodeBox.Location = New-Object System.Drawing.Point(24, 96)
    $licenseCodeBox.Size = New-Object System.Drawing.Size(352, 28)
    $licenseCodeBox.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $licenseCodeBox.CharacterCasing = [System.Windows.Forms.CharacterCasing]::Upper
    $licenseCard.Controls.Add($licenseCodeBox)

    $licenseError = New-TextLabel -Text "Code invalide" -X 24 -Y 130 -W 330 -H 16 -Font $script:FontUI -Fore $script:C_Red
    $licenseError.Visible = $false
    $licenseCard.Controls.Add($licenseError)

    $licenseBtnOk = New-ModernButton -Text "Valider / Deverrouiller" -X 24 -Y 156 -W 250 -H 36
    $licenseCard.Controls.Add($licenseBtnOk)

    $licenseBtnQuit = New-ModernButton -Text "Quitter" -X 286 -Y 156 -W 90 -H 36 -Fill ([System.Drawing.Color]::FromArgb(198, 205, 214)) -Hover ([System.Drawing.Color]::FromArgb(176, 184, 194)) -Fore ([System.Drawing.Color]::FromArgb(45, 52, 62))
    $licenseCard.Controls.Add($licenseBtnQuit)

    $licenseWin.AcceptButton = $licenseBtnOk
    $licenseWin.CancelButton = $licenseBtnQuit
    $licenseWin.ActiveControl = $licenseCodeBox

    # --- Actions ---
    # NOTE : un handler d'evenement n'atteint pas les variables locales de cette
    # fonction ; il passe par le controle emetteur ($s) et son Tag, comme le
    # reste de l'interface.
    $licenseCodeBox.Tag = $licenseError
    $licenseBtnOk.Tag.Win = $licenseWin
    $licenseBtnOk.Tag.Code = $licenseCodeBox
    $licenseBtnOk.Tag.Error = $licenseError
    $licenseBtnOk.Add_Click({
        param($s, $e)
        if (Test-LicenseCode $s.Tag.Code.Text) {
            $script:LicenseValidated = $true
            $s.Tag.Win.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $s.Tag.Win.Close()
        } else {
            $s.Tag.Code.Clear()           # declenche TextChanged : masque l'erreur precedente
            $s.Tag.Error.Visible = $true  # puis on affiche le refus
            $s.Tag.Code.Focus()
        }
    })
    $licenseCodeBox.Add_TextChanged({ param($s, $e) $s.Tag.Visible = $false })
    $licenseBtnQuit.Add_Click({ param($s, $e) $s.FindForm().Close() })

    return @{ Win = $licenseWin; Code = $licenseCodeBox; Error = $licenseError }
}

function Show-LicenseGate {
    # Affiche le verrou. Renvoie $true uniquement si le code a ete valide.
    if ($script:LicenseValidated) { return $true }
    $ui = New-LicenseWindow
    $ok = ($ui.Win.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
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
    $ui.Win.Close()
    $ui.Win.Dispose()
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
    Write-Out "Licence validee : acces autorise."
}
