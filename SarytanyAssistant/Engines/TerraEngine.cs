// ==================================================================
// Engines\TerraEngine.cs  -  Moteur "Installation Terra"
//   Portage C# de src\24-Engine-Terra.ps1 :
//   Portage du projet "Installation Terra" (PowerDraft + modules
//   TerraMatch / TerraModeler / TerraScan) dans l'assistant :
//   6 etapes enchainees, arret a la premiere echec, annulation
//   possible, persistance des reglages dans le MEME fichier que
//   PowerDraft-Setup.exe (%LOCALAPPDATA%\PowerDraftSetup\settings.json)
//   pour garder la continuite des valeurs saisies.
// Contrats : Run(options, progress, log, cancel) - niveaux {INFO, OK, ERREUR, ATTENTION}
//           $script:TerraCancelRequested -> CancellationToken (annulation cooperative)
//           LoadSettings / SaveSettings / TerraOptions (ex $script:TerraCfg)
// Niveaux de log : INFO | OK | ATTENTION | ERREUR
// Le moteur ne touche JAMAIS a l'interface : le dossier source est
// passe via TerraOptions.TerraRoot (alias SourceDir), pas de dialogue.
// ==================================================================

using System.Diagnostics;
using System.Management;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SarytanyAssistant.Engines;

/// <summary>
/// Reglages persistants du moteur Terra (port de $script:TerraCfg).
/// Noms de proprietes JSON identiques a PowerShell pour l'interop
/// avec PowerDraft-Setup.exe (%LOCALAPPDATA%\PowerDraftSetup\settings.json).
/// Valeurs par défaut identiques au source PS.
/// </summary>
public sealed class TerraOptions
{
    /// <summary>Dossier principal Terra (contient eng\). Port de TerraRoot ;
    /// equivalent du "SourceDir" choisi par la vue.</summary>
    [JsonPropertyName("TerraRoot")]
    [JsonPropertyOrder(0)]
    public string TerraRoot { get; set; } = "";

    /// <summary>Alias API du dossier source (non serialise : le JSON garde la cle "TerraRoot").</summary>
    [JsonIgnore]
    public string SourceDir
    {
        get => TerraRoot;
        set => TerraRoot = value;
    }

    /// <summary>eng\setup.exe (determine par l'etape 2).</summary>
    [JsonPropertyName("SetupExe")]
    [JsonPropertyOrder(1)]
    public string SetupExe { get; set; } = "";

    /// <summary>Version a installer (voir TerraEngine.TerraVersionChoices).</summary>
    [JsonPropertyName("SetupVersion")]
    [JsonPropertyOrder(2)]
    public string SetupVersion { get; set; } = "PowerDraft CE";

    /// <summary>eng\PTC_LAS.ptc.</summary>
    [JsonPropertyName("PtcSource")]
    [JsonPropertyOrder(3)]
    public string PtcSource { get; set; } = "";

    /// <summary>Dossier cible TerraScan.</summary>
    [JsonPropertyName("TscanDir")]
    [JsonPropertyOrder(4)]
    public string TscanDir { get; set; } = @"C:\terra64\tscan";

    /// <summary>Chemin de PowerDraft.exe.</summary>
    [JsonPropertyName("PowerDraftExe")]
    [JsonPropertyOrder(5)]
    public string PowerDraftExe { get; set; } = @"C:\Program Files\Bentley\PowerDraft\PowerDraft.exe";

    /// <summary>Installation silencieuse (/quiet) ; la selection de version est alors ignoree.</summary>
    [JsonPropertyName("Silent")]
    [JsonPropertyOrder(6)]
    public bool Silent { get; set; } = false;

    /// <summary>Computer ID (Tools > About > Copy for email).</summary>
    [JsonPropertyName("ComputerId")]
    [JsonPropertyOrder(7)]
    public string ComputerId { get; set; } = "";
}

/// <summary>Resultat de l'enchaiement des 6 etapes (port du hashtable de Invoke-TerraInstall).</summary>
public sealed class TerraResult
{
    /// <summary>Toutes les etapes sont passees.</summary>
    public bool Completed { get; set; }

    /// <summary>Numero d'etape en echec (1..6), 0 si aucun echec.</summary>
    public int Failed { get; set; }

    /// <summary>Annulation demandee par l'utilisateur.</summary>
    public bool Aborted { get; set; }

    /// <summary>Computer ID repris des reglages en cas de succes.</summary>
    public string ComputerId { get; set; } = "";
}

/// <summary>Libelle d'une etape (port de $script:TerraSteps).</summary>
public sealed record TerraStepInfo(string Title, string Ok, string Er);

/// <summary>
/// Moteur "Installation Terra" : 6 etapes enchainees,
/// arret a la premiere echec, annulation cooperative.
/// </summary>
public class TerraEngine : IEngine
{
    // --- Versions proposees ($script:TerraVersionChoices) ---
    public static readonly string[] TerraVersionChoices = ["PowerDraft CE", "MicroStation CE"];

    // --- Libelles des 6 etapes (statut + journal) ---
    public static readonly TerraStepInfo[] TerraSteps =
    [
        new("Securite & antivirus",
            "Protection verifiee",
            "Windows Security indisponible."),
        new("Dossier Terra",
            "setup.exe localise",
            "setup.exe introuvable. Verifiez le dossier dans les reglages."),
        new("Initialisation PowerDraft",
            "Dossier 10.0.0 cree",
            "PowerDraft ne demarre pas. Verifiez son chemin dans les reglages."),
        new("Installation",
            "Installation terminee",
            "L'installeur s'est arrete trop tot. Fermez-le puis relancez (ne jamais cliquer Abort)."),
        new("Collecte systeme",
            "Informations recuperees",
            "Computer ID illegible ou vide. Ouvrez Terra (Tools > About) puis renseignez-le."),
        new("Configuration finale",
            "Configuration validee",
            "Dossier cible protege en ecriture. Relancez en administrateur."),
    ];

    // --- Reglages persistants (interop PowerDraft-Setup.exe) ---
    // $script:TerraAppDataDir / $script:TerraSettingsFile
    private static string AppDataDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PowerDraftSetup");

    public static string SettingsFile => Path.Combine(AppDataDir, "settings.json");

    private static readonly JsonSerializerOptions SaveJsonOptions = new()
    {
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    // ==================== PERSISTANCE ====================

    /// <summary>
    /// Charge les reglages depuis %LOCALAPPDATA%\PowerDraftSetup\settings.json
    /// (port de Load-TerraSettings). Les cles inconnues sont ignorees, les
    /// valeurs nulles deviennent des chaines vides ; en cas de fichier
    /// illisible les valeurs par defaut sont conservees.
    /// </summary>
    public TerraOptions LoadSettings()
    {
        var cfg = new TerraOptions();
        if (!File.Exists(SettingsFile)) return cfg;
        try
        {
            var json = File.ReadAllText(SettingsFile, Encoding.UTF8);
            if (string.IsNullOrWhiteSpace(json)) return cfg;
            var data = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (data is null) return cfg;
            foreach (var kvp in data)
            {
                switch (kvp.Key.ToLowerInvariant())
                {
                    case "terraroot":     cfg.TerraRoot     = JsonAsText(kvp.Value); break;
                    case "setupexe":      cfg.SetupExe      = JsonAsText(kvp.Value); break;
                    case "setupversion":  cfg.SetupVersion  = JsonAsText(kvp.Value); break;
                    case "ptcsource":     cfg.PtcSource     = JsonAsText(kvp.Value); break;
                    case "tscandir":      cfg.TscanDir      = JsonAsText(kvp.Value); break;
                    case "powerdraftexe": cfg.PowerDraftExe = JsonAsText(kvp.Value); break;
                    case "silent":        cfg.Silent        = JsonAsBool(kvp.Value); break;
                    case "computerid":    cfg.ComputerId    = JsonAsText(kvp.Value); break;
                    // Les autres cles sont ignorees (comme le Contains() du source PS).
                }
            }
        }
        catch
        {
            // Reglages Terra illisibles : SettingsFile (Write-Verbose dans le source PS).
        }
        return cfg;
    }

    /// <summary>Ecrit les reglages au meme format/endroit que PowerShell (port de Save-TerraSettings).</summary>
    public bool SaveSettings(TerraOptions cfg)
    {
        try
        {
            Directory.CreateDirectory(AppDataDir);
            File.WriteAllText(SettingsFile, JsonSerializer.Serialize(cfg, SaveJsonOptions), Encoding.UTF8);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string JsonAsText(JsonElement e) => e.ValueKind switch
    {
        JsonValueKind.Null => "",
        JsonValueKind.Undefined => "",
        JsonValueKind.String => e.GetString() ?? "",
        _ => e.GetRawText(),
    };

    private static bool JsonAsBool(JsonElement e) => e.ValueKind switch
    {
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        JsonValueKind.Number => e.GetRawText() != "0",
        JsonValueKind.String => bool.TryParse(e.GetString(), out var b) ? b : false,
        _ => false,
    };

    // ==================== ETAPES ====================
    // Chaque fonction journalise via say (msg, niveau) et retourne true / false.

    /// <summary>Etape 1 : Securite & antivirus (MSFT_MpComputerStatus via WMI, port de Get-MpComputerStatus).</summary>
    private bool Step1(TerraOptions cfg, Action<string, string> say, CancellationToken cancel)
    {
        try
        {
            bool rtEnabled = false;
            // ManagementScope n'est pas IDisposable (System.Management 9.x).
            var scope = new ManagementScope(@"\\.\root\Microsoft\Windows\Defender");
            {
                scope.Connect();
                using var searcher = new ManagementObjectSearcher(scope,
                    new ObjectQuery("SELECT * FROM MSFT_MpComputerStatus"));
                using var results = searcher.Get();
                foreach (ManagementBaseObject mo in results)
                {
                    object? v = mo["RealTimeProtectionEnabled"];
                    rtEnabled = v is not null && Convert.ToBoolean(v);
                    break;
                }
            }
            string rt = rtEnabled ? "activee" : "desactivee";
            say($"Protection temps reel : {rt}", "INFO");
            if (rtEnabled)
            {
                say("Protection active : ajoutez une exclusion sous Windows Security plutot que de la desactiver.", "ATTENTION");
            }

            var q = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                @"Microsoft\Windows Defender\Quarantine");
            if (Directory.Exists(q))
            {
                int count = 0;
                try
                {
                    foreach (var _ in Directory.EnumerateFileSystemEntries(q)) count++;
                }
                catch
                {
                    // Get-ChildItem -ErrorAction SilentlyContinue : acces refuse = elements ignores.
                }
                say($"Elements en quarantaine : {count}", "INFO");
                if (count > 0) say("Restaurer les fichiers via Windows Security > historique.", "ATTENTION");
            }
            return true;
        }
        catch (Exception ex)
        {
            say($"Etat Defender indisponible : {ex.Message}", "ATTENTION");
            return true;
        }
    }

    /// <summary>Etape 2 : Dossier Terra - resolution de eng\ puis setup.exe et PTC_LAS.ptc.</summary>
    private bool Step2(TerraOptions cfg, Action<string, string> say, CancellationToken cancel)
    {
        var root = cfg.TerraRoot.Trim();
        if (root.Length == 0 || !PathExists(root))
        {
            say($"Dossier Terra introuvable : '{root}'", "ERREUR");
            return false;
        }
        say($"Dossier principal : {root}", "INFO");

        var eng = Path.Combine(root, "eng");
        if (!PathExists(eng))
        {
            say("Sous-dossier eng absent a la racine - recherche recursive...", "INFO");
            var found = FindFirstDirectory(root, "eng", 4);
            if (found is not null) eng = found;
        }
        if (!PathExists(eng))
        {
            say("Aucun dossier eng trouve.", "ERREUR");
            return false;
        }

        var setup = Path.Combine(eng, "setup.exe");
        if (!PathExists(setup))
        {
            var hit = FindFirstFile(eng, "setup.exe", 3);
            if (hit is not null) setup = hit;
        }
        if (!PathExists(setup))
        {
            say($"setup.exe introuvable dans eng ({eng}).", "ERREUR");
            return false;
        }
        say($"Dossier eng : {eng}", "INFO");
        say($"setup.exe : {setup}", "OK");

        var ptc = Path.Combine(eng, "PTC_LAS.ptc");
        if (PathExists(ptc))
        {
            say($"PTC_LAS.ptc : {ptc}", "OK");
        }
        else
        {
            say("PTC_LAS.ptc absent du dossier eng (l'etape 6 echouera).", "ATTENTION");
        }

        cfg.SetupExe = setup;
        cfg.PtcSource = ptc;
        SaveSettings(cfg);
        return true;
    }

    /// <summary>Etape 3 : Initialisation PowerDraft - premier lancement puis attentes du dossier 10.0.0.</summary>
    private bool Step3(TerraOptions cfg, Action<string, string> say, CancellationToken cancel)
    {
        var exe = cfg.PowerDraftExe.Trim();
        if (exe.Length == 0 || !PathExists(exe))
        {
            say($"PowerDraft.exe introuvable : {exe}", "ERREUR");
            return false;
        }
        try
        {
            say("Lancement de PowerDraft pour initialiser les dossiers...", "INFO");
            using var p = StartProcess(exe, null);
            say($"Processus lance (PID {p.Id})", "INFO");
            Thread.Sleep(8000);
            if (!p.HasExited)
            {
                p.CloseMainWindow();
                Thread.Sleep(2000);
                if (!p.HasExited) p.Kill();
            }
            say("Fermeture de PowerDraft.", "INFO");

            var target = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                @"Bentley\PowerDraft\10.0.0");
            for (var i = 0; i < 12; i++)
            {
                if (cancel.IsCancellationRequested) return false;
                if (Directory.Exists(target))
                {
                    say($"Arborescence generee : {target}", "OK");
                    return true;
                }
                Thread.Sleep(5000);
            }
            say("Dossier 10.0.0 non detecte apres initialisation.", "ERREUR");
            return false;
        }
        catch (Exception ex)
        {
            say($"Echec du lancement : {ex.Message}", "ERREUR");
            return false;
        }
    }

    /// <summary>Etape 4 : Installation - setup.exe ; ne jamais cliquer Abort.</summary>
    private bool Step4(TerraOptions cfg, Action<string, string> say, CancellationToken cancel)
    {
        var setup = cfg.SetupExe.Trim();
        if (setup.Length == 0 || !PathExists(setup))
        {
            say($"setup.exe introuvable : '{setup}' (lancez d'abord l'etape 2 via le dossier Terra).", "ERREUR");
            return false;
        }
        say("REGLE CRITIQUE : ne jamais cliquer sur Abort.", "ATTENTION");
        say($"Attendre le bouton Terminer ({cfg.SetupVersion}).", "ATTENTION");
        try
        {
            var argsList = (string?)null;
            if (cfg.Silent)
            {
                argsList = "/quiet";
                say("Mode silencieux : la selection de version est ignoree.", "ATTENTION");
            }

            say($"Ouverture de l'installeur : {setup}", "INFO");
            using var p = StartProcess(setup, argsList);
            say($"Installeur demarre (PID {p.Id})", "INFO");

            if (cfg.Silent)
            {
                p.WaitForExit();
            }
            else
            {
                var deadline = DateTime.Now.AddMinutes(60);
                while (!p.HasExited)
                {
                    if (cancel.IsCancellationRequested)
                    {
                        say("Abandon demande par l'utilisateur (installeur laisse ouvert).", "ATTENTION");
                        return false;
                    }
                    if (DateTime.Now > deadline)
                    {
                        say("Delai de 60 min depasse - installeur toujours ouvert.", "ERREUR");
                        return false;
                    }
                    Thread.Sleep(250);
                }
            }
            p.Refresh();
            int exitCode = p.ExitCode;
            say($"Code de retour : {exitCode}", "INFO");
            if (exitCode == 0 || exitCode == 3010)
            {
                if (exitCode == 3010) say("Redemarrage requis.", "ATTENTION");
                return true;
            }
            if (exitCode == 1602) say("Code 1602 : annulation (Abort) detectee.", "ERREUR");
            return false;
        }
        catch (Exception ex)
        {
            say($"Echec de l'installation : {ex.Message}", "ERREUR");
            return false;
        }
    }

    /// <summary>Etape 5 : Collecte systeme - nom du poste + Computer ID, relance de verification.</summary>
    private bool Step5(TerraOptions cfg, Action<string, string> say, CancellationToken cancel)
    {
        var cname = Environment.MachineName;
        say($"Nom de l'ordinateur : {cname}", "INFO");
        var cid = cfg.ComputerId.Trim();
        if (cid.Length == 0)
        {
            say("Computer ID non renseigne (Tools > About > Copy for email, puis Reglages Terra).", "ERREUR");
            return false;
        }
        say($"Computer ID : {cid}", "OK");
        var exe = cfg.PowerDraftExe.Trim();
        if (exe.Length > 0 && PathExists(exe))
        {
            try
            {
                StartProcess(exe, null).Dispose();
                say("PowerDraft relance pour verification.", "INFO");
            }
            catch (Exception ex)
            {
                say($"Relance impossible : {ex.Message}", "ATTENTION");
            }
        }
        SaveSettings(cfg);
        return true;
    }

    /// <summary>Etape 6 : Configuration finale - PTC_LAS.ptc vers le dossier tscan.</summary>
    private bool Step6(TerraOptions cfg, Action<string, string> say, CancellationToken cancel)
    {
        var src = cfg.PtcSource.Trim();
        var tscan = cfg.TscanDir.Trim();
        var dst = Path.Combine(tscan, "PTC_LAS.ptc");
        if (src.Length == 0 || !PathExists(src))
        {
            say($"PTC_LAS.ptc introuvable : '{src}'", "ERREUR");
            return false;
        }
        try
        {
            if (!PathExists(tscan))
            {
                Directory.CreateDirectory(tscan);
                say($"Dossier cree : {tscan}", "INFO");
            }
            File.Copy(src, dst, true);
            say($"Fichier copie : {dst}", "OK");
            if (File.Exists(dst))
            {
                long sz = new FileInfo(dst).Length;
                say($"Taille : {sz:N0} octets", "INFO");
            }
            var exe = cfg.PowerDraftExe.Trim();
            if (exe.Length > 0 && PathExists(exe))
            {
                say("Lancement de PowerDraft pour le premier chargement du PTC.", "INFO");
                StartProcess(exe, null).Dispose();
            }
            SaveSettings(cfg);
            return true;
        }
        catch (Exception ex)
        {
            say($"Echec de la configuration : {ex.Message}", "ERREUR");
            return false;
        }
    }

    // ==================== OUTILS PRIVES ====================

    /// <summary>Port de Test-Path -LiteralPath (fichier ou dossier).</summary>
    private static bool PathExists(string path) => File.Exists(path) || Directory.Exists(path);

    /// <summary>
    /// Premier dossier dont le nom correspond (insensible a la casse), parcours
    /// recursif en profondeur maximale, ordre DFS avant comme Get-ChildItem -Recurse.
    /// Retourne null si rien n'est trouve ou acces refuse (SilentlyContinue).
    /// </summary>
    private static string? FindFirstDirectory(string root, string name, int maxDepth)
    {
        return Walk(root, 0);

        string? Walk(string dir, int depth)
        {
            if (depth >= maxDepth) return null;
            string[] children;
            try { children = Directory.GetDirectories(dir); }
            catch { return null; }
            foreach (var child in children)
            {
                if (string.Equals(Path.GetFileName(child), name, StringComparison.OrdinalIgnoreCase))
                    return child;
                var hit = Walk(child, depth + 1);
                if (hit is not null) return hit;
            }
            return null;
        }
    }

    /// <summary>
    /// Premier fichier dont le nom correspond (insensible a la casse), parcours
    /// recursif en profondeur maximale (Get-ChildItem -Recurse -Depth n -Filter).
    /// </summary>
    private static string? FindFirstFile(string root, string fileName, int maxDepth)
    {
        return Walk(root, 0);

        string? Walk(string dir, int depth)
        {
            if (depth >= maxDepth) return null;
            string[] entries;
            try { entries = Directory.GetFileSystemEntries(dir); }
            catch { return null; }
            foreach (var entry in entries)
            {
                try
                {
                    if (File.Exists(entry))
                    {
                        if (Path.GetFileName(entry).Equals(fileName, StringComparison.OrdinalIgnoreCase))
                            return entry;
                    }
                    else if (Directory.Exists(entry))
                    {
                        var hit = Walk(entry, depth + 1);
                        if (hit is not null) return hit;
                    }
                }
                catch
                {
                    // Element inaccessible : ignore (SilentlyContinue), on continue les freres.
                }
            }
            return null;
        }
    }

    /// <summary>
    /// Start-Process -FilePath $exe [-ArgumentList $args] -PassThru :
    /// UseShellExecute = true comme le comportement shell de PowerShell.
    /// </summary>
    private static Process StartProcess(string path, string? arguments)
    {
        var psi = new ProcessStartInfo(path) { UseShellExecute = true };
        if (!string.IsNullOrEmpty(arguments)) psi.Arguments = arguments;
        return Process.Start(psi)
            ?? throw new InvalidOperationException($"Impossible de demarrer le processus : {path}");
    }

    /// <summary>Progression : [int](($i / 6) * 100) arrondi comme le cast [int] de PowerShell.</summary>
    private static int Pct(int n) => (int)Math.Round(n / 6.0 * 100.0);

    // ==================== ORCHESTRATION ====================

    /// <summary>
    /// Enchaine les 6 etapes Terra. S'arrete au premier echec ou a
    /// l'annulation. Retourne Completed / Failed / Aborted / ComputerId.
    /// progress(pct, status) est appele au debut et a la fin de chaque etape
    /// (l'index de ligne 0-based du source PS correspond a l'etape courante,
    /// la vue le recalcule a partir du pourcentage et des libelles TerraSteps).
    /// </summary>
    public TerraResult Run(TerraOptions o, ProgressHandler? progress, LogHandler? log, CancellationToken cancel)
    {
        void Say(string m, string l) => log?.Invoke(m, l);
        void Upd(int p, string s) => progress?.Invoke(p, s);

        var runners = new Func<TerraOptions, Action<string, string>, CancellationToken, bool>[]
        {
            Step1, Step2, Step3, Step4, Step5, Step6
        };

        var result = new TerraResult();

        for (int i = 0; i < 6; i++)
        {
            if (cancel.IsCancellationRequested)
            {
                result.Aborted = true;
                Say("Operation annulee avant l'etape.", "ATTENTION");
                return result;
            }
            var step = TerraSteps[i];
            Upd(Pct(i), $"Etape {i + 1}/6 : {step.Title}");

            var ok = false;
            try
            {
                ok = runners[i](o, Say, cancel);
            }
            catch (Exception ex)
            {
                Say($"Exception etape {i + 1} : {ex.Message}", "ERREUR");
                ok = false;
            }

            if (cancel.IsCancellationRequested)
            {
                result.Aborted = true;
                Say("Operation interrompue par l'utilisateur.", "ATTENTION");
                return result;
            }
            if (!ok)
            {
                result.Failed = i + 1;
                Say(step.Er, "ERREUR");
                return result;
            }

            Say($"[{i + 1}/6] {step.Ok}", "OK");
            Upd(Pct(i + 1), $"Etape {i + 1}/6 terminee");
        }

        result.Completed = true;
        result.ComputerId = o.ComputerId.Trim();
        return result;
    }
}
