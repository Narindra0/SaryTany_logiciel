using System.Windows;
using Microsoft.Win32;
using SarytanyAssistant.Engines;

namespace SarytanyAssistant.Views;

/// <summary>
/// Modale "Reglages Terra" (port de Show-TerraSettingsDialog, src\73-View-Terra.ps1) :
/// dossier Terra, version, dossier TerraScan, PowerDraft.exe, Computer ID,
/// mode silencieux. Persistee via TerraEngine.SaveSettings (settings.json commun
/// avec PowerDraft-Setup.exe).
/// </summary>
public partial class TerraSettingsWindow : Window
{
    private readonly TerraOptions _cfg;

    public TerraOptions? Result { get; private set; }

    public TerraSettingsWindow(TerraOptions cfg)
    {
        InitializeComponent();
        _cfg = cfg;
        CmbVersion.ItemsSource = TerraEngine.TerraVersionChoices;
        CmbVersion.SelectedItem = TerraEngine.TerraVersionChoices.Contains(cfg.SetupVersion)
            ? cfg.SetupVersion : TerraEngine.TerraVersionChoices[0];
        TxtTerraRoot.Text    = cfg.TerraRoot;
        TxtTscanDir.Text     = cfg.TscanDir;
        TxtPowerDraft.Text   = cfg.PowerDraftExe;
        TxtComputerId.Text   = cfg.ComputerId;
        ChkSilent.IsChecked  = cfg.Silent;
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var fb = new OpenFolderDialog { Title = "Choisir le dossier principal Terra" };
        var cur = TxtTerraRoot.Text.Trim();
        if (cur.Length > 0 && System.IO.Directory.Exists(cur)) fb.InitialDirectory = cur;
        if (fb.ShowDialog(this) == true) TxtTerraRoot.Text = fb.FolderName;
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        _cfg.TerraRoot     = TxtTerraRoot.Text.Trim();
        _cfg.SetupVersion  = (string)CmbVersion.SelectedItem;
        _cfg.TscanDir      = TxtTscanDir.Text.Trim();
        _cfg.PowerDraftExe = TxtPowerDraft.Text.Trim();
        _cfg.ComputerId    = TxtComputerId.Text.Trim();
        _cfg.Silent        = ChkSilent.IsChecked == true;
        Result = _cfg;
        DialogResult = true;
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
