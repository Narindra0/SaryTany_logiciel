using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using SarytanyAssistant.Engines;

namespace SarytanyAssistant.Views;

/// <summary>
/// Vue "SintegraLidar" (port fidele de src\72-View-SintegraLidar.ps1) :
/// 7 etapes, protection anti-analyse, compteur d'essais unique du moteur,
/// desactivation automatique des protections avant integration.
/// </summary>
public partial class SintegraView : UserControl
{
    private static readonly int[] StepMap = { 5, 15, 35, 50, 60, 75, 90 };
    private const int TrialMaxLaunches = 3;

    private readonly SintegraEngine _engine = new();
    private CancellationTokenSource _cts = new();

    public SintegraView()
    {
        InitializeComponent();
        Run.Configure("Selectionnez le dossier source puis lancez l'integration.",
            new (string, string)[]
            {
                ("Selection source", "Dossier source SintegraLidar"),
                ("Securite destination", "Creation + permissions icacls"),
                ("Copie des fichiers", "Source -> destination"),
                ("Import registre", "Fichier .reg"),
                ("Ajout au PATH", "Variable systeme PATH"),
                ("Separateur decimal", "Decimal = point"),
                ("Integration Bentley", "Fichier mvba PowerDraft"),
            },
            goText: "Demarrer l'integration",
            showResume: false);

        Run.GoClicked += StartIntegration;
        Run.CancelClicked += () =>
        {
            _cts.Cancel();
            Run.Log("Annulation demandee...", "ATTENTION");
            Run.SetUiStatus(true, "Annulation en cours", "Interruption...", -1, "ATTENTION", "amber", "amber");
        };

        Run.Log("Vue SintegraLidar prete. Cliquez sur 'Demarrer' pour lancer l'integration (7 etapes).");
        Run.SetUiStatus(false, "Pret", "Selectionnez le dossier source puis lancez l'integration.", 0);
    }

    private MainWindow? Main => Window.GetWindow(this) as MainWindow;

    private static int ActiveStep(int pct)
    {
        var active = 0;
        for (var i = 0; i < StepMap.Length; i++)
            if (pct >= StepMap[i]) active = i;
        return active;
    }

    private static string? PickSourceFolder()
    {
        var dlg = new OpenFolderDialog { Title = "Selectionnez le dossier source SintegraLidarCONNECT" };
        return dlg.ShowDialog() == true ? dlg.FolderName : null;
    }

    private async void StartIntegration()
    {
        Run.ClearLog();
        Run.ResetRows();
        _cts = new CancellationTokenSource();

        // --- Protection anti-analyse ---
        if (SintegraEngine.TestAnalysisEnvironment())
        {
            const string msg = "Environnement d'analyse detecte (debogueur, nom d'ordinateur ou variable d'environnement suspecte). L'integration est refusee pour des raisons de securite.";
            Run.Log(msg, "ERREUR");
            Run.SetUiStatus(false, "Analyse detectee", msg, -1, "ERREUR", "red", "red");
            Ui.Dialog(msg, "Protection anti-analyse", "error");
            return;
        }
        Run.Log("Verifications d'environnement : aucune menace detectee.", "OK");

        // --- Dossier source ---
        var source = PickSourceFolder();
        if (string.IsNullOrEmpty(source))
        {
            Run.Log("Aucun dossier source valide n'a ete fourni.", "ATTENTION");
            Run.SetUiStatus(false, "Source manquante", "Selectionnez un dossier source.", -1, "ATTENTION", "amber", "amber");
            return;
        }
        Run.Log($"Source SintegraLidar : {source}", "OK");

        // --- Compteur d'essais : source unique = compteur du moteur ---
        var nextTrial = _engine.TrialLaunches + 1;
        Run.Log($"Lancement d'essai n° {nextTrial} / {TrialMaxLaunches}");
        if (nextTrial > TrialMaxLaunches)
        {
            Run.Log($"Limite d'essais atteinte ({TrialMaxLaunches}). Contactez votre administrateur.", "ERREUR");
            Run.SetUiStatus(false, "Limite d'essais atteinte",
                $"Tentative {_engine.TrialLaunches}/{TrialMaxLaunches}", -1, "ERREUR", "red", "red");
            Ui.Dialog($"Limite d'essais atteinte ({TrialMaxLaunches}). Le compteur a ete consigne.", "Essai limite", "warning");
            return;
        }

        Run.SetUiStatus(true, "En cours", "Initialisation...", 0, "EN COURS", "accent");
        Run.Log("===============================================");
        Run.Log("Demarrage de l'integration SintegraLidar (7 etapes)...");
        Run.Log("===============================================");
        Run.SetRow(0, "EN COURS");

        var log = new LogHandler((m, l) => { Run.Log(m, l); Ui.Status(m); });
        var progress = new ProgressHandler((pct, status) =>
        {
            var active = ActiveStep(pct);
            for (var i = 0; i < active; i++) Run.SetRow(i, "OK");
            Run.SetRow(active, "EN COURS");
            Run.SetUiStatus(true, status, $"Progression : {pct} %", pct, "EN COURS", "accent");
        });

        // Protections : desactivation automatique avant installation (best effort).
        // Jamais bloquante : une erreur ici ne doit ni fermer l'app ni arreter le flux.
        try { await Task.Run(() => new PcConfigEngine().DisableInstallProtections(false, log)); }
        catch (Exception ex) { Run.Log($"Protections : desactivation ignoree ({ex.Message}).", "ATTENTION"); }

        try
        {
            var result = await Task.Run(() => _engine.Run(source, null, TrialMaxLaunches, progress, log, _cts.Token));

            for (var i = 0; i < 7; i++) Run.SetRow(i, "OK");
            Run.Log($"Integration terminee : dest = {result.DestDir}, essai = {result.TrialNumber}/{TrialMaxLaunches}", "OK");
            Run.Log($"Application : {result.AppName} v{result.AppVersion} - {SintegraEngine.DevName} ({SintegraEngine.ContactEmail})");
            Run.Log("===============================================");
            Run.SetUiStatus(false, $"Terminee - {result.AppName} v{result.AppVersion}",
                $"Destination : {result.DestDir} | Essai : {result.TrialNumber}/{TrialMaxLaunches}", 100, "SUCCES", "green", "green");
        }
        catch (OperationCanceledException)
        {
            Run.MarkRunningRowsAsError(7);
            Run.Log("Integration annulee par l'utilisateur.", "ATTENTION");
            Run.SetUiStatus(false, "Annulee", "Interrompee par l'utilisateur.", -1, "ATTENTION", "amber", "amber");
        }
        catch (Exception ex)
        {
            Run.MarkRunningRowsAsError(7);
            Run.Log($"Erreur : {ex.Message}", "ERREUR");
            Run.SetUiStatus(false, "Erreur durant l'integration", ex.Message, -1, "ERREUR", "red", "red");
            Ui.Dialog(ex.Message, "Erreur SintegraLidar", "error");
        }
    }
}
