using System.Windows;
using System.Windows.Controls;
using SarytanyAssistant.Engines;

namespace SarytanyAssistant.Views;

/// <summary>
/// Vue "Installation Terra" (port fidele de src\73-View-Terra.ps1) :
/// 6 etapes via le gabarit run, modale "Reglages Terra" persistee dans
/// %LOCALAPPDATA%\PowerDraftSetup\settings.json, desactivation best-effort
/// des protections avant installation.
/// </summary>
public partial class TerraView : UserControl
{
    private readonly TerraEngine _engine = new();
    private TerraOptions _cfg;
    private CancellationTokenSource _cts = new();

    public TerraView()
    {
        InitializeComponent();
        _cfg = _engine.LoadSettings();

        Run.Configure("Ouvrez 'Reglages Terra' pour indiquer le dossier source, puis lancez.",
            new (string, string)[]
            {
                ("Securite & antivirus", "Windows Defender + quarantaine"),
                ("Dossier Terra", "Recherche eng + setup.exe"),
                ("Initialisation PowerDraft", "Premier lancement, dossier 10.0.0"),
                ("Installation", "setup.exe - ne jamais cliquer Abort"),
                ("Collecte systeme", "Nom du poste + Computer ID"),
                ("Configuration finale", "PTC_LAS.ptc -> C:\\terra64\\tscan"),
            },
            goText: "Demarrer l'installation Terra",
            extraText: "Reglages Terra",
            showResume: false);

        Run.GoClicked += StartTerra;
        Run.ExtraClicked += ShowSettings;
        Run.CancelClicked += () =>
        {
            _cts.Cancel();
            Run.Log("Annulation demandee...", "ATTENTION");
            Run.SetUiStatus(true, "Annulation en cours", "Interruption...", -1, "ATTENTION", "amber", "amber");
        };

        // --- Initialisation (port de la fin de 73-View-Terra.ps1) ---
        var root = ValidTerraRoot;
        if (root.Length > 0)
        {
            Run.Log($"Vue Installation Terra prete. Dossier : {root}");
            Run.SetUiStatus(false, "Pret", $"Dossier Terra : {root}", 0, "PRET", "green");
        }
        else
        {
            Run.Log("Vue Installation Terra prete. Ouvrez 'Reglages Terra' pour indiquer le dossier source.");
            Run.SetUiStatus(false, "Pret", "Dossier Terra non renseigne.", 0);
        }
    }

    private MainWindow? Main => Window.GetWindow(this) as MainWindow;

    /// <summary>Get-TerraRootInfo : racine renseignee ET existante, sinon ''.</summary>
    private string ValidTerraRoot =>
        !string.IsNullOrWhiteSpace(_cfg.TerraRoot) && System.IO.Directory.Exists(_cfg.TerraRoot)
            ? _cfg.TerraRoot.Trim() : "";

    /// <summary>Set-TerraRows : lignes 0..active-1 = OK, active = EN COURS.</summary>
    private static int ActiveRow(int pct) => Math.Clamp((int)Math.Round(pct / 100.0 * 6), 0, 5);

    private void SetRows(int active)
    {
        for (var i = 0; i < 6; i++)
            Run.SetRow(i, i < active ? "OK" : i == active ? "EN COURS" : "EN ATTENTE");
    }

    // ================= MODALE : REGLAGES TERRA =================
    private void ShowSettings()
    {
        Run.ClearLog();
        Run.Log("Ouverture des reglages Terra...");
        var dlg = new TerraSettingsWindow(_cfg) { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() == true && dlg.Result is not null)
        {
            _cfg = dlg.Result;
            if (!_engine.SaveSettings(_cfg))
                Run.Log("Echec de sauvegarde des reglages (acces refuse).", "ATTENTION");
            else
                Run.Log($"Reglages enregistres : {TerraEngine.SettingsFile}", "OK");

            var root = ValidTerraRoot;
            if (root.Length > 0)
                Run.SetUiStatus(false, "Pret", $"Dossier Terra : {root}", 0, "PRET", "green");
            else
                Run.SetUiStatus(false, "Pret", "Dossier Terra non renseigne.", 0, "EN ATTENTE");
        }
    }

    // ================= ACTION : DEMARRAGE INSTALLATION TERRA =================
    private async void StartTerra()
    {
        Run.ClearLog();
        Run.ResetRows();
        _cts = new CancellationTokenSource();

        // --- Dossier Terra requis (sinon on ouvre les reglages) ---
        var root = ValidTerraRoot;
        if (root.Length == 0)
        {
            Run.Log("Dossier Terra non renseigne : ouverture des reglages.");
            ShowSettings();
            root = ValidTerraRoot;
        }
        if (root.Length == 0)
        {
            Run.Log("Aucun dossier Terra valide : operation arretee.", "ATTENTION");
            Run.SetUiStatus(false, "Dossier manquant",
                "Renseignez le dossier principal Terra dans les reglages.", -1, "ATTENTION", "amber", "amber");
            Ui.Dialog("Aucun dossier Terra valide n'a ete fourni. Ouvrez 'Reglages Terra' et indiquez le dossier contenant eng\\setup.exe.",
                "Source manquante", "warning");
            return;
        }

        Run.SetUiStatus(true, "En cours", "Initialisation...", 0, "EN COURS", "accent");
        Run.Log("===============================================");
        Run.Log($"Demarrage de l'installation Terra (6 etapes) - version : {_cfg.SetupVersion}");
        Run.Log("===============================================");
        SetRows(0);

        var log = new LogHandler((m, l) => { Run.Log(m, l); Ui.Status(m); });
        var progress = new ProgressHandler((pct, status) =>
        {
            SetRows(ActiveRow(pct));
            Run.SetUiStatus(true, status, $"Progression : {pct} %", pct, "EN COURS", "accent");
        });

        // Protections : desactivation automatique avant installation (best effort).
        // Jamais bloquante : une erreur ici ne doit ni fermer l'app ni arreter le flux.
        try { await Task.Run(() => new PcConfigEngine().DisableInstallProtections(false, log)); }
        catch (Exception ex) { Run.Log($"Protections : desactivation ignoree ({ex.Message}).", "ATTENTION"); }

        var cfg = _cfg;
        try
        {
            var result = await Task.Run(() => _engine.Run(cfg, progress, log, _cts.Token));

            if (result.Completed)
            {
                for (var i = 0; i < 6; i++) Run.SetRow(i, "OK");
                Run.Log("===============================================");
                Run.Log($"Installation Terra terminee - Computer ID : {result.ComputerId}", "OK");
                Run.SetUiStatus(false, "Terminee", "PowerDraft + modules Terra installes.", 100, "SUCCES", "green", "green");
                Ui.Dialog($"L'installation Terra (PowerDraft + modules) s'est deroulee correctement.\nComputer ID : {result.ComputerId}",
                    "Installation Terra");
            }
            else if (result.Aborted)
            {
                Run.MarkRunningRowsAsError(6, "ARRET");
                Run.SetUiStatus(false, "Interrompue", "Annulation demandee.", -1, "ARRET", "amber", "amber");
            }
            else
            {
                var idx = result.Failed - 1;
                if (idx >= 0 && idx < 6) Run.SetRow(idx, "ERREUR");
                var msg = idx >= 0 && idx < TerraEngine.TerraSteps.Length
                    ? TerraEngine.TerraSteps[idx].Er : "Echec de l'installation Terra.";
                Run.Log($"Echec a l'etape {result.Failed}/6.", "ERREUR");
                Run.SetUiStatus(false, $"Echec - etape {result.Failed}/6", msg, -1, "ERREUR", "red", "red");
                Ui.Dialog(msg, "Installation Terra", "error");
            }
        }
        catch (OperationCanceledException)
        {
            Run.MarkRunningRowsAsError(6, "ARRET");
            Run.Log("Erreur : Operation annulee par l'utilisateur.", "ERREUR");
            Run.SetUiStatus(false, "Interrompue", "Operation annulee par l'utilisateur.", -1, "ARRET", "amber", "amber");
        }
        catch (Exception ex)
        {
            Run.MarkRunningRowsAsError(6);
            Run.Log($"Erreur : {ex.Message}", "ERREUR");
            Run.SetUiStatus(false, "Erreur durant l'installation", ex.Message, -1, "ERREUR", "red", "red");
            Ui.Dialog(ex.Message, "Erreur Installation Terra", "error");
        }
    }
}
