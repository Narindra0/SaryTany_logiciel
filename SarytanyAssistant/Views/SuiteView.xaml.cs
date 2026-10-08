using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using SarytanyAssistant.Engines;

namespace SarytanyAssistant.Views;

/// <summary>
/// Vue "Installation Bentley Suite" (port de src\71-View-BentleySuite.ps1,
/// comportement redefini par les specifications metier) :
///  - sequentialite stricte module par module (01 -> 21, aucun saut) ;
///    la regle absolue exclut l'etape 22 du moteur ;
///  - module manquant : import de secours par double-clic sur la ligne ;
///  - module manuel : installateur lance en interactif puis REPRISE AUTOMATIQUE
///    a sa fermeture (plus de pause ni de bouton "Reprendre") ;
///  - bouton "Demarrer" active uniquement quand le dossier source est choisi
///    et que tous les fichiers des modules sont detectes ou importes.
/// </summary>
public partial class SuiteView : UserControl
{
    private readonly SuiteEngine _engine = new();
    private CancellationTokenSource _cts = new();
    private string? _sourceDir;
    private bool _running;

    public SuiteView()
    {
        InitializeComponent();
        var steps = SuiteEngine.Modules
            .Select(m => (
                Label: $"Module {m.Num:D2}  {m.Name}",
                Description: (m.Mode == SuiteInstallMode.Exe ? "EXE" : m.Mode.ToString().ToUpperInvariant())
                             + " - " + (m.Manual ? "manuel (reprise auto)" : "automatique")))
            .ToList();
        Run.Configure("Selectionnez le dossier source pour verifier les prerequis.",
            steps,
            goText: "Demarrer l'installation de la Suite",
            showResume: false);

        // Spec 4 : "Demarrer" seulement quand tout est configure et complet.
        Run.GoEnabledPredicate = () => !_running && _sourceDir is not null && AllModulesFound();

        Run.GoClicked += Start;
        Run.RowDoubleClicked += ImportForRow;
        Run.CancelClicked += () =>
        {
            _engine.CancelRequested = true;
            _cts.Cancel();
            Run.Log("Annulation demandee...", "ATTENTION");
            Run.SetUiStatus(true, "Annulation en cours", "Interruption...", -1, "ATTENTION", "amber", "amber");
        };

        // Spec "import manuel" : si un fichier manque pendant l'installation,
        // le moteur ouvre le selectionneur de secours via l'interface.
        _engine.ResolveMissing = mod => Dispatcher.Invoke(
            () => PickModuleFile(mod, $"Choisir le fichier du module {mod.Num:D2} - {mod.Name} (manquant)"));

        // Spec "interventions manuelles" : invitation avant l'installateur interactif.
        _engine.ManualStepStarted += mod => Dispatcher.BeginInvoke(() =>
            Ui.Dialog(
                $"Le module {mod.Num:D2} - {mod.Name} necessite une action humaine.\n\n"
              + "L'installateur vient de s'ouvrir : terminez l'installation dans sa fenetre.\n"
              + "Le programme reprendra AUTOMATIQUEMENT son cours a la fermeture de l'installateur.",
                $"Action manuelle - module {mod.Num:D2}", "warning"));

        _engine.ModuleProgressed += OnModuleProgressed;

        Run.Log($"Vue Bentley Suite prete ({SuiteEngine.Modules.Count} modules, installation lineaire 01 -> 21 ; etape 22 exclue par regle absolue).");
        Run.SetUiStatus(false, "En attente de configuration",
            "Aucun dossier source selectionne : le bouton Demarrer reste inactif.", -1,
            "ATTENTION", "amber", "amber");
        RefreshReadiness();
    }

    private MainWindow? Main => Window.GetWindow(this) as MainWindow;

    // ================= CARTE PREREQUIS =================

    private void PickSource_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFolderDialog { Title = "Selectionnez le dossier source de la Bentley Suite" };
        if (dlg.ShowDialog(Window.GetWindow(this)) != true) return;
        _sourceDir = dlg.FolderName;
        LblSource.Text = _sourceDir;
        LblSource.Foreground = (Brush)FindResource("Text");
        Run.Log($"Dossier source : {_sourceDir}", "INFO");
        RefreshReadiness();
    }

    /// <summary>
    /// Recalcule la detection des modules : met a jour les lignes (DETECTE /
    /// MANQUANT), le message de readiness et l'etat du bouton Demarrer.
    /// </summary>
    private void RefreshReadiness()
    {
        if (string.IsNullOrEmpty(_sourceDir) || !Directory.Exists(_sourceDir))
        {
            LblReadiness.Text = "Selectionnez le dossier source : la detection des modules et le bouton Demarrer s'activeront une fois tous les fichiers presents.";
            LblReadiness.Foreground = (Brush)FindResource("Muted");
            Run.RefreshGoEnabled();
            return;
        }

        var found = _engine.TestModulesExist(_sourceDir);
        var missing = new List<string>();
        for (var i = 0; i < SuiteEngine.Modules.Count; i++)
        {
            var mod = SuiteEngine.Modules[i];
            var file = found[mod];
            if (file is null)
            {
                missing.Add(mod.Name);
                Run.SetRow(i, "MANQUANT");
                Run.UpdateRowDescription(i, "MANQUANT - double-cliquez pour importer le fichier");
            }
            else
            {
                bool imported = _engine.FileOverrides.TryGetValue(mod.Num, out var ov) && ov == file.FullName;
                Run.SetRow(i, imported ? "IMPORTE" : "PRET");
                Run.UpdateRowDescription(i, $"{(imported ? "IMPORTE" : "DETECTE")} : {file.Name}");
            }
        }

        int total = SuiteEngine.Modules.Count;
        if (missing.Count == 0)
        {
            LblReadiness.Text = $"{total}/{total} modules detectes. Tous les prerequis sont complets : vous pouvez demarrer l'installation.";
            LblReadiness.Foreground = (Brush)FindResource("Green");
        }
        else
        {
            LblReadiness.Text = $"{total - missing.Count}/{total} modules detectes. Manquants : {string.Join(", ", missing)}. "
                              + "Double-cliquez leurs lignes pour importer les fichiers ; le bouton Demarrer s'activera une fois la liste complete.";
            LblReadiness.Foreground = (Brush)FindResource("Amber");
        }
        Run.RefreshGoEnabled();
    }

    private bool AllModulesFound() =>
        !string.IsNullOrEmpty(_sourceDir)
        && _engine.TestModulesExist(_sourceDir).Values.All(v => v is not null);

    // ================= IMPORT DE SECOURS (DOUBLE-CLIC) =================

    /// <summary>
    /// Double-clic sur une ligne : ouverture d'un OpenFileDialog filtre selon le
    /// mode du module (MSI/MSP/EXE), puis enregistrement dans FileOverrides du
    /// moteur. Le module sera installe depuis ce chemin meme s'il est absent du
    /// dossier source (import de secours).
    /// </summary>
    private void ImportForRow(int index)
    {
        if (_running)
        {
            Run.Log("Import indisponible pendant l'installation (le moteur gere deja les secours en cours de route).", "ATTENTION");
            return;
        }
        if (index < 0 || index >= SuiteEngine.Modules.Count) return;

        var mod = SuiteEngine.Modules[index];
        var path = PickModuleFile(mod, $"Importer le fichier du module {mod.Num:D2} - {mod.Name}");
        if (path is null) return;

        _engine.FileOverrides[mod.Num] = path;
        Run.UpdateRowDescription(index, $"IMPORTE : {Path.GetFileName(path)}");
        Run.SetRow(index, "IMPORTE");
        Run.Log($"Module {mod.Num:D2} - {mod.Name} : import de secours enregistre ({path}).", "OK");
        RefreshReadiness();
    }

    private string? PickModuleFile(BentleyModule mod, string title)
    {
        var dlg = new OpenFileDialog
        {
            Title = title,
            CheckFileExists = true,
            Filter = mod.Mode switch
            {
                SuiteInstallMode.Msi => "Paquet MSI (*.msi)|*.msi",
                SuiteInstallMode.Msp => "Patch MSP (*.msp)|*.msp",
                _ => "Installateur EXE (*.exe)|*.exe",
            },
        };
        if (_sourceDir is not null && Directory.Exists(_sourceDir)) dlg.InitialDirectory = _sourceDir;
        return dlg.ShowDialog(Window.GetWindow(this)) == true ? dlg.FileName : null;
    }

    // ================= EXECUTION =================

    private async void Start()
    {
        var source = _sourceDir;
        if (string.IsNullOrEmpty(source) || !Directory.Exists(source) || !AllModulesFound())
        {
            Ui.Dialog("Le dossier source ou certains fichiers de modules manquent encore.\n"
                    + "Completez tous les prerequis (detection ou import) avant de demarrer.",
                      "Prerequis incomplets", "warning");
            return;
        }

        Run.ClearLog();
        Run.ResetRows();
        _cts = new CancellationTokenSource();
        _running = true;

        var log = new LogHandler((m, l) => { Run.Log(m, l); Ui.Status(m); });
        var progress = new ProgressHandler((pct, status) =>
            Run.SetUiStatus(true, status, $"Progression : {pct} %", pct, "EN COURS", "accent"));
        _engine.Log = log;
        _engine.Progress = progress;
        _engine.CancelRequested = false;

        Run.SetUiStatus(true, "En cours", "Initialisation...", 0, "EN COURS", "accent");
        try
        {
            // Installation lineaire stricte : chaque module est traite a son tour,
            // les modules manuels attendent la fin de l'action puis reprennent seuls.
            var result = await Task.Run(() => _engine.InstallSuite(source, 0, _cts.Token));

            for (var i = 0; i < SuiteEngine.Modules.Count; i++)
                Run.SetRow(i, result.Failed.Contains(SuiteEngine.Modules[i].Name) ? "ERREUR" : "OK");

            Run.SetUiStatus(false, $"Terminee - {result.Installed}/{result.TotalModules}",
                result.Failed.Count > 0 ? "Echecs : " + string.Join(", ", result.Failed) : "Tous les modules sont installes (01 -> 21, etape 22 exclue).",
                100, result.Failed.Count > 0 ? "ATTENTION" : "SUCCES",
                result.Failed.Count > 0 ? "amber" : "green",
                result.Failed.Count > 0 ? "amber" : "green");
            if (result.Failed.Count > 0)
                Ui.Dialog($"Installation terminee, mais des modules sont en echec :\n{string.Join(", ", result.Failed)}",
                          "Echecs partiels", "warning");
        }
        catch (OperationCanceledException)
        {
            Run.MarkRunningRowsAsError(Run.StepCount);
            Run.Log("Installation annulee par l'utilisateur.", "ATTENTION");
            Run.SetUiStatus(false, "Annulee", "Interrompee par l'utilisateur.", -1, "ATTENTION", "amber", "amber");
        }
        catch (Exception ex)
        {
            Run.Log($"Erreur : {ex.Message}", "ERREUR");
            Run.SetUiStatus(false, "Erreur", ex.Message, -1, "ERREUR", "red", "red");
            Ui.Dialog(ex.Message, "Erreur Bentley Suite", "error");
        }
        finally
        {
            _running = false;
            RefreshReadiness();
        }
    }

    private void OnModuleProgressed(int percent, string status, int moduleIndex, BentleyModule? module)
    {
        // Lignes precedentes = OK (y compris les manuels termines), ligne courante = EN COURS.
        for (var i = 0; i < moduleIndex && i < SuiteEngine.Modules.Count; i++)
            Run.SetRow(i, "OK");
        if (moduleIndex >= 0 && moduleIndex < SuiteEngine.Modules.Count)
            Run.SetRow(moduleIndex, "EN COURS");
    }
}
