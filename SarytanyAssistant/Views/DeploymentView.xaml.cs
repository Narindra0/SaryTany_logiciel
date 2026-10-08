using System.Windows;
using System.Windows.Controls;
using SarytanyAssistant.Engines;

namespace SarytanyAssistant.Views;

/// <summary>
/// Vue "Deploiement Bentley" (port fidele de src\70-View-Deployment.ps1) :
/// 3 etapes, actions 'Lancer le deploiement' et 'Deploiement automatique',
/// desactivation best-effort des protections avant deploiement.
/// </summary>
public partial class DeploymentView : UserControl
{
    private readonly DeploymentEngine _engine = new();
    private CancellationTokenSource _cts = new();

    public DeploymentView()
    {
        InitializeComponent();
        Run.Configure("Choisissez une action pour commencer.",
            new (string, string)[]
            {
                ("Source de reference", "it_st  ->  C:\\IT_Config"),
                ("Profil par defaut", "C:\\Users\\Default"),
                ("Profils utilisateurs", "Tous les comptes du poste"),
            },
            goText: "Lancer le deploiement",
            extraText: "Deploiement automatique a l'ouverture de session",
            showResume: false);

        Run.GoClicked += StartDeployment;
        Run.ExtraClicked += InstallAutoDeploy;
        Run.CancelClicked += () =>
        {
            _cts.Cancel();
            Run.Log("Annulation demandee, fin de l'operation en cours...", "ATTENTION");
            Run.SetUiStatus(true, "Annulation en cours", "Interruption en cours...", -1, "ATTENTION", "amber", "amber");
        };

        Run.Log("Vue Deploiement prete. Cliquez sur une action pour commencer.");
        Run.SetUiStatus(false, "Pret", "Choisissez une action pour commencer.", 0);
    }

    private MainWindow? Main => Window.GetWindow(this) as MainWindow;

    private static int ActiveRow(int pct) => pct < 34 ? 0 : pct < 50 ? 1 : 2;

    private async void StartDeployment()
    {
        Run.ClearLog();
        Run.ResetRows();
        _cts = new CancellationTokenSource();
        var token = _cts.Token;
        Run.SetUiStatus(true, "En cours", "Etape 1 - preparation de la source de reference...", 0, "EN COURS", "accent");
        Run.Log("===============================================");
        Run.Log("Demarrage de la procedure de deploiement...");
        Run.Log("===============================================");

        var options = new DeploymentOptions();
        var log = new LogHandler((m, l) => { Run.Log(m, l); Ui.Status(m); });

        // Protections : desactivation automatique avant installation (best effort).
        // Jamais bloquante : une erreur ici ne doit ni fermer l'app ni arreter le flux.
        try { await Task.Run(() => new PcConfigEngine().DisableInstallProtections(false, log)); }
        catch (Exception ex) { Run.Log($"Protections : desactivation ignoree ({ex.Message}).", "ATTENTION"); }

        try
        {
            var result = await Task.Run(() => _engine.Run(options,
                (pct, status) =>
                {
                    Run.SetRow(ActiveRow(pct), "EN COURS");
                    for (var i = 0; i < ActiveRow(pct); i++) Run.SetRow(i, "OK");
                    Run.SetUiStatus(true, status, $"Progression : {pct} %", pct, "EN COURS", "accent");
                }, log, token));

            Run.Log("===============================================");
            if (result.Success)
            {
                for (var i = 0; i < 3; i++) Run.SetRow(i, "OK");
                Run.Log($"Deploiement termine avec succes : {result.Updated}/{result.Targets} profil(s), {result.Files} fichiers de reference.", "OK");
                Run.Log("Redemarrage de PowerDraft recommande.");
                Run.Log("===============================================");
                Run.SetUiStatus(false, $"Termine - {result.Updated} profil(s) mis a jour",
                    $"Sur {result.Targets} profils analyses - Redemarrez PowerDraft pour appliquer.", 100, "SUCCES", "green", "green");
                Ui.Dialog($"Le deploiement de Bentley PowerDraft s'est deroule correctement.\n\n{result.Updated} profil(s) mis a jour sur {result.Targets}.\nRedemarrez PowerDraft pour appliquer.", "Succes");
            }
            else
            {
                Run.MarkRunningRowsAsError(3);
                Run.Log($"Termine avec {result.Failed.Count} echec(s) : {string.Join(", ", result.Failed)}", "ERREUR");
                Run.Log("===============================================");
                Run.SetUiStatus(false, $"Termine - {result.Failed.Count} echec(s)",
                    "Profils en echec : " + string.Join(", ", result.Failed), 100, "ATTENTION", "amber", "amber");
                Ui.Dialog($"Le deploiement est termine mais {result.Failed.Count} profil(s) ont echoue :\n{string.Join(", ", result.Failed)}\n\nConsultez le journal pour le detail.",
                    "Termine avec avertissement", "warning");
            }
        }
        catch (OperationCanceledException)
        {
            Run.MarkRunningRowsAsError(3);
            Run.Log("Erreur : Operation annulee par l'utilisateur.", "ERREUR");
            Run.SetUiStatus(false, "Annule", "Operation annulee par l'utilisateur.", -1, "ATTENTION", "amber", "amber");
        }
        catch (Exception ex)
        {
            Run.MarkRunningRowsAsError(3);
            Run.Log($"Erreur : {ex.Message}", "ERREUR");
            Run.SetUiStatus(false, "Erreur durant le deploiement", ex.Message, -1, "ERREUR", "red", "red");
            Ui.Dialog(ex.Message, "Erreur", "error");
        }
    }

    private async void InstallAutoDeploy()
    {
        Run.SetUiStatus(true, "Installation du deploiement automatique",
            "Preparation de la strategie d'ouverture de session...", 10, "EN COURS", "accent");
        var log = new LogHandler((m, l) => { Run.Log(m, l); Ui.Status(m); });
        Run.Log("===============================================");
        Run.Log("Installation du deploiement automatique a l'ouverture de session...");
        Run.Log("===============================================");
        try
        {
            var g = await Task.Run(() => _engine.InstallAutoDeploy(new DeploymentOptions(), log));
            Run.SetUiStatus(false, "Installe",
                "Le deploiement se lancera a chaque ouverture de session - " + g.ScriptPath, 100, "SUCCES", "green", "green");
            Ui.Dialog($"Le deploiement automatique est installe.\n\nScript : {g.ScriptPath}\nWrapper : {g.CmdPath}\nEntree : {g.RunOnceKey}\n\nLa configuration sera copiee automatiquement dans le profil de tout utilisateur qui ouvrira une session sur ce poste, sans jamais ecraser une configuration deja presente.",
                "Deploiement installe");
        }
        catch (Exception ex)
        {
            Run.Log($"Erreur : {ex.Message}", "ERREUR");
            Run.SetUiStatus(false, "Echec de l'installation", ex.Message, -1, "ERREUR", "red", "red");
            Ui.Dialog(ex.Message, "Erreur", "error");
        }
    }
}
