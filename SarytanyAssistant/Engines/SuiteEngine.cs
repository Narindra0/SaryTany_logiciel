using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;

namespace SarytanyAssistant.Engines;

/// <summary>
/// Mode d'installation d'un module Bentley (port du champ <c>Mode</c> de
/// <c>src\22-Engine-BentleySuite.ps1</c>).
/// </summary>
public enum SuiteInstallMode
{
    /// <summary>MSI : <c>msiexec /i ...</c></summary>
    Msi,

    /// <summary>MSP : <c>msiexec /p ...</c> (patch, comme dans le source PS).</summary>
    Msp,

    /// <summary>EXE : lanceur silencieux (<c>/S</c> par defaut).</summary>
    Exe
}

/// <summary>
/// Definition d'un module Bentley (Num, Name, Pattern regex, Mode, Manual).
/// Port fidele des entrees <c>@{ Num = ..; Name = ..; Pattern = ..; Mode = ..; Manual = .. }</c>.
/// </summary>
public sealed class BentleyModule
{
    private readonly Regex _regex;

    public int Num { get; }

    public string Name { get; }

    /// <summary>Motif de detection du fichier (regex, insensitive a la casse, non ancre).</summary>
    public string Pattern { get; }

    public SuiteInstallMode Mode { get; }

    /// <summary>true = necessite une interaction manuelle (pause/resume).</summary>
    public bool Manual { get; }

    public BentleyModule(int num, string name, string pattern, SuiteInstallMode mode, bool manual)
    {
        Num = num;
        Name = name;
        Pattern = pattern;
        Mode = mode;
        Manual = manual;
        // -imatch de PowerShell = regex non ancre, insensitive a la casse.
        _regex = new Regex(pattern,
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant,
            TimeSpan.FromSeconds(1));
    }

    /// <summary>Vrai si le nom de fichier correspond au motif (equivalent a <c>$_.Name -imatch Pattern</c>).</summary>
    public bool Matches(string fileName) => _regex.IsMatch(fileName);

    public override string ToString() => $"{Num:D2} - {Name} [{Mode}{(Manual ? ", Manual" : string.Empty)}]";
}

/// <summary>
/// Callback de progression enrichi (pct, status, index module, module) :
/// reproduit les 4 arguments passes par <c>$upd</c> dans le source PS,
/// pour permettre a l'interface de surligner la ligne courante.
/// Le callback contractuel <see cref="ProgressHandler"/> (pct, status) reste invoque.
/// </summary>
public delegate void SuiteModuleProgressHandler(int percent, string status, int moduleIndex, BentleyModule? module);

/// <summary>
/// Selectionneur de secours appele quand le fichier d'un module est introuvable
/// pendant l'installation (spec "Import manuel") : l'interface ouvre une fenetre
/// de choix de fichier et renvoie le chemin complet choisi, ou null si annule.
/// </summary>
public delegate string? MissingFileResolver(BentleyModule module);

/// <summary>
/// Rapport final d'installation, miroir de l'objet renvoye par
/// <c>Invoke-BentleySuiteInstall</c>.
/// </summary>
public sealed class SuiteInstallResult
{
    /// <summary>Nombre de modules installes avec succes.</summary>
    public int Installed { get; init; }

    /// <summary>Nombre total de modules de la table.</summary>
    public int TotalModules { get; init; }

    /// <summary>Noms des modules en echec ou manquants.</summary>
    public IReadOnlyList<string> Failed { get; init; } = Array.Empty<string>();

    /// <summary>Noms des modules manuels ignores (action requise).</summary>
    public IReadOnlyList<string> Skipped { get; init; } = Array.Empty<string>();

    /// <summary>Succes global : aucun module en echec.</summary>
    public bool Success => Failed.Count == 0;

    /// <summary>
    /// Conserve pour la forme (le source PS expose $Cancelled). Ici l'annulation
    /// leve une OperationCanceledException, donc le resultat renvoye est toujours false.
    /// </summary>
    public bool Cancelled { get; init; }
}

/// <summary>
/// Moteur d'installation Bentley Suite (port C# de <c>src\22-Engine-BentleySuite.ps1</c>,
/// comportement redefini par les specifications metier).
/// Execution sequentielle stricte module par module (aucun saut), actions manuelles
/// lancees puis attendues avec reprise automatique, fichiers manquants resolvables
/// par import de secours. Regle absolue : l'etape 22 n'existe plus dans la table.
/// Aucun acces a l'interface graphique (moteur testable seul).
/// </summary>
public class SuiteEngine : IEngine
{
    /// <summary>Arguments silencieux par defaut pour les EXE.</summary>
    private const string DefaultSilentExeArgs = "/S";

    private volatile bool _cancelRequested;

    /// <summary>
    /// Etat partage, mis a true par l'appelant pour demander l'annulation
    /// (port de $script:SuiteCancelRequested). Verifie entre chaque module.
    /// </summary>
    public bool CancelRequested
    {
        get => _cancelRequested;
        set => _cancelRequested = value;
    }

    /// <summary>Journalisation (message, level in { INFO, OK, ERREUR, ATTENTION }).</summary>
    public LogHandler Log { get; set; } = EngineDefaults.NullLog;

    /// <summary>Progression contractuelle (pct 0-100, status).</summary>
    public ProgressHandler Progress { get; set; } = EngineDefaults.NullProgress;

    /// <summary>Progression enrichie avec le contexte module (equivalent a $upd en PS).</summary>
    public event SuiteModuleProgressHandler? ModuleProgressed;

    /// <summary>
    /// Import de secours : chemin complet fourni manuellement pour un module
    /// dont le fichier n'est pas detecte dans le dossier source (cle = Num du module).
    /// Alimente par le double-clic sur une ligne dans l'interface.
    /// </summary>
    public ConcurrentDictionary<int, string> FileOverrides { get; } = new();

    /// <summary>
    /// Invit d'action humaine : levee juste avant le lancement interactif d'un
    /// installateur manuel (modules 13/14/15). L'installation reprend automatiquement
    /// a la fermeture de l'installateur (spec "reprendre automatiquement son cours").
    /// </summary>
    public event Action<BentleyModule>? ManualStepStarted;

    /// <summary>
    /// Selectionneur appele par le moteur quand un fichier manque en cours d'installation
    /// (after FileOverrides). Laisse a null : le module est signale en echec.
    /// </summary>
    public MissingFileResolver? ResolveMissing { get; set; }

    /// <summary>
    /// Les 20 modules Bentley dans l'ordre d'installation (numerotes 01-21,
    /// sans 10, comme au source PS). L'entree 22 (MicroStation Update 11) est
    /// RETIREE par regle absolue : le programme ne doit jamais l'atteindre.
    /// </summary>
    public static readonly IReadOnlyList<BentleyModule> Modules = new List<BentleyModule>
    {
        new( 1, "DgnIFilterSetUpx64",      "DgnIFilterSetUpx64",            SuiteInstallMode.Msi, false),
        new( 2, "DgnIndexer",              "DgnIndexer",                    SuiteInstallMode.Msi, false),
        new( 3, "DgnPreviewHandlerx64",    "DgnPreviewHandlerx64",          SuiteInstallMode.Msi, false),
        new( 4, "DgnThumbnailProviderx64", "DgnThumbnailProviderx64",       SuiteInstallMode.Msi, false),
        new( 5, "HDRPreviewExtension_x64", "HDRPreviewExtension_x64",       SuiteInstallMode.Msi, false),
        new( 6, "ItgDgnDbImporter 1.6",    @"ItgDgnDbImporter.*1\.6.*x64",  SuiteInstallMode.Msi, false),
        new( 7, "ItgDgnDbImporter 2.0",    @"ItgDgnDbImporter.*2\.0.*x64",  SuiteInstallMode.Msi, false),
        new( 8, "MetroStationx64",         "MetroStationx64",               SuiteInstallMode.Msi, false),
        new( 9, "Pointools32Extx86",       "Pointools32Extx86",             SuiteInstallMode.Msi, false),
        new(11, "PowerDraftDocumentation", "PowerDraftDocumentation",       SuiteInstallMode.Msi, false),
        new(12, "PowerDraftx64",           "PowerDraftx64",                 SuiteInstallMode.Msi, false),
        new(13, "CONNECTION Client",       "Setup_CONNECTIONClient",        SuiteInstallMode.Exe, true),
        new(14, "PowerDraft 10.11",        "Setup_PowerDraftx64_10.11",     SuiteInstallMode.Exe, true),
        new(15, "CONNECT Advisor",         "Setup_CONNECTAdvisor",          SuiteInstallMode.Exe, true),
        new(16, "Vba71",                   "Vba71",                         SuiteInstallMode.Msi, false),
        new(17, "Vba71_1033",              "Vba71_1033",                    SuiteInstallMode.Msi, false),
        new(18, "VBA71-KB2803498-x64",     "VBA71-KB2803498-x64",           SuiteInstallMode.Msp, false),
        new(19, "VBA71-KB2803498-x64_1033","VBA71-KB2803498-x64_1033",      SuiteInstallMode.Msp, false),
        new(20, "VBA71-KB3061498-x64",     "VBA71-KB3061498-x64",           SuiteInstallMode.Msp, false),
        new(21, "patch.x64",               @"patch\.x64",                  SuiteInstallMode.Msp, false),
        // RÈGLE ABSOLUE : le module 22 (MicroStation Update 11, "microstation.*patch-REV3")
        // est volontairement EXCLU de la table. Le programme ne doit en aucun cas
        // atteindre ou exécuter l'étape 22. Ne pas réinsérer cette entrée.
    };

    /// <summary>
    /// Verifie quels fichiers de modules Bentley sont presents dans le dossier source.
    /// Port de <c>Test-BentleyModulesExist</c>. Renvoie, pour chaque module, le premier
    /// FileInfo trouve (nom de fichier, regex insensitive) ou null si absent.
    /// Contrairement au source qui renvoyait une hashtable vide quand le dossier est
    /// absent, le dictionnaire contient toujours chaque module (valeur null) afin de
    /// satisfaire le contrat "module -> FileInfo ou null".
    /// </summary>
    public Dictionary<BentleyModule, FileInfo?> TestModulesExist(string sourceDir)
    {
        var results = new Dictionary<BentleyModule, FileInfo?>();
        foreach (var mod in Modules)
            results[mod] = null;

        if (string.IsNullOrEmpty(sourceDir) || !Directory.Exists(sourceDir))
        {
            ApplyFileOverrides(results);
            return results;
        }

        List<FileInfo> files;
        try
        {
            // Get-ChildItem -File -Force : fichiers uniquement, non recursif, caches inclus.
            files = new DirectoryInfo(sourceDir).EnumerateFiles("*", SearchOption.TopDirectoryOnly).ToList();
        }
        catch
        {
            // -ErrorAction SilentlyContinue : on renvoie les valeurs null deja posees.
            ApplyFileOverrides(results);
            return results;
        }

        foreach (var mod in Modules)
        {
            FileInfo? hit = null;
            foreach (var file in files)
            {
                if (mod.Matches(file.Name))
                {
                    hit = file; // Select-Object -First 1
                    break;
                }
            }
            results[mod] = hit;
        }

        ApplyFileOverrides(results);
        return results;
    }

    /// <summary>
    /// Remplace les modules non detectes par les fichiers importes manuellement
    /// (FileOverrides), si le chemin existe toujours.
    /// </summary>
    private void ApplyFileOverrides(Dictionary<BentleyModule, FileInfo?> results)
    {
        if (FileOverrides.IsEmpty) return;
        foreach (var mod in Modules)
        {
            if (results[mod] is not null) continue;
            if (FileOverrides.TryGetValue(mod.Num, out var path) && !string.IsNullOrWhiteSpace(path) && File.Exists(path))
                results[mod] = new FileInfo(path);
        }
    }

    /// <summary>
    /// Installe les modules Bentley de facon sequentielle.
    /// Port de <c>Invoke-BentleySuiteInstall</c>.
    /// </summary>
    /// <param name="sourceDir">Dossier source contenant les fichiers des modules.</param>
    /// <param name="resumeFrom">Numero de module pour reprendre apres une pause manuelle (0 = debut).</param>
    /// <param name="cancellationToken">Annulation cooperative supplementaire (optionnelle).</param>
    /// <exception cref="InvalidOperationException">Aucun dossier source specifie.</exception>
    /// <exception cref="DirectoryNotFoundException">Dossier source introuvable.</exception>
    /// <exception cref="OperationCanceledException">Annulation demandee entre deux modules.</exception>
    public SuiteInstallResult InstallSuite(
        string sourceDir,
        int resumeFrom = 0,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(sourceDir))
            throw new InvalidOperationException("Aucun dossier source specifie pour l'installation Bentley Suite.");

        if (!Directory.Exists(sourceDir))
            throw new DirectoryNotFoundException($"Dossier source introuvable : {sourceDir}");

        int total = Modules.Count;
        var foundFiles = TestModulesExist(sourceDir);

        var missing = new List<int>();
        foreach (var mod in Modules)
        {
            if (foundFiles[mod] is null)
                missing.Add(mod.Num);
        }
        if (missing.Count > 0)
            Say("Modules manquants : " + string.Join(", ", missing), "ATTENTION");

        var failed = new List<string>();
        // Skipped reste expose pour la forme : avec la reprise automatique des
        // modules manuels, plus aucun module n'est ignore (liste toujours vide).
        var skipped = new List<string>();
        int success = 0;

        Update(0, "Demarrage de l'installation Bentley Suite...", -1, null);

        int i = 0;
        foreach (var mod in Modules)
        {
            if (_cancelRequested || cancellationToken.IsCancellationRequested)
            {
                Say("Installation annulee par l'utilisateur.", "ATTENTION");
                // Le source PS faisait un break puis renvoyait Cancelled = $true.
                // Conformement au contrat C#, l'annulation leve une exception.
                throw new OperationCanceledException("Installation annulee par l'utilisateur.", cancellationToken);
            }

            if (resumeFrom > 0 && mod.Num < resumeFrom)
                continue;

            i++;
            int idx = i - 1;
            // [int]((i / total) * 100) en PowerShell = division reelle puis arrondi
            // (mi-paire). On reproduit ce comportement pour coller aux pourcentages PS.
            int pct = (int)Math.Round((double)i / total * 100.0, MidpointRounding.ToEven);

            FileInfo? f = foundFiles[mod];
            if (f is null)
                f = TryResolveMissing(mod, cancellationToken);
            if (f is null)
            {
                Say($"Module {mod.Num:D2} - {mod.Name} : MANQUANT (ignore)", "ERREUR");
                failed.Add(mod.Name);
                Update(pct, $"Module {mod.Num:D2} manquant", idx, mod);
                continue;
            }

            Update(pct, $"Installation module {mod.Num:D2} - {mod.Name}", idx, mod);
            Say($"Installation module {mod.Num:D2} - {mod.Name} : {f.Name}", "INFO");

            try
            {
                switch (mod.Mode)
                {
                    case SuiteInstallMode.Msi:
                    case SuiteInstallMode.Msp:
                    {
                        // MSI : msiexec /i <file> ; MSP : msiexec /p <file> (comme le source PS).
                        string primarySwitch = mod.Mode == SuiteInstallMode.Msi ? "/i" : "/p";
                        int exitCode = RunMsiLike(primarySwitch, f, mod);
                        // Codes 0 (succes), 1641 (succes + redemarrage), 3010 (succes + redemarrage requis).
                        if (exitCode is 0 or 1641 or 3010)
                        {
                            Say($"Module {mod.Num:D2} - {mod.Name} : SUCCES (code {exitCode})", "OK");
                            success++;
                        }
                        else
                        {
                            Say($"Module {mod.Num:D2} - {mod.Name} : ECHEC (code {exitCode})", "ERREUR");
                            failed.Add(mod.Name);
                        }
                        break;
                    }

                    case SuiteInstallMode.Exe:
                    {
                        if (mod.Manual)
                        {
                            // Spec "interventions manuelles" : on invite l'utilisateur,
                            // on lance l'installateur en mode interactif, on attend la
                            // fin de l'action, puis on REPREND automatiquement le module
                            // suivant. Plus de pause ni de bouton "Reprendre".
                            Say($"Module {mod.Num:D2} - {mod.Name} : ACTION REQUISE - l'installateur s'ouvre, terminez l'installation manuelle. Le programme reprendra automatiquement ensuite.", "ATTENTION");
                            Update(pct, $"Module {mod.Num:D2} - {mod.Name} : action manuelle en cours", idx, mod);
                            ManualStepStarted?.Invoke(mod);

                            int manualExit = RunInteractiveExe(f, cancellationToken);
                            if (manualExit is 0 or 1641 or 3010)
                            {
                                Say($"Module {mod.Num:D2} - {mod.Name} : SUCCES apres action manuelle (code {manualExit})", "OK");
                                success++;
                            }
                            else
                            {
                                // L'action humaine est consideree effectuee des que
                                // l'installateur se ferme ; code inhabituel = a verifier.
                                Say($"Module {mod.Num:D2} - {mod.Name} : installeur ferme (code {manualExit}) - reprise automatique, verifiez ce module", "ATTENTION");
                                success++;
                            }
                            break;
                        }

                        int exitCode = RunSilentExe(f);
                        // Le source PS n'accepte que 0 et 3010 pour les EXE.
                        if (exitCode is 0 or 3010)
                        {
                            Say($"Module {mod.Num:D2} - {mod.Name} : SUCCES (code {exitCode})", "OK");
                            success++;
                        }
                        else
                        {
                            Say($"Module {mod.Num:D2} - {mod.Name} : ECHEC (code {exitCode})", "ERREUR");
                            failed.Add(mod.Name);
                        }
                        break;
                    }
                }
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                Say($"Module {mod.Num:D2} - {mod.Name} : ERREUR EXCEPTION - {ex.Message}", "ERREUR");
                failed.Add(mod.Name);
            }
        }

        Update(100, "Termine", -1, null);

        return new SuiteInstallResult
        {
            Installed = success,
            TotalModules = total,
            Failed = failed,
            Skipped = skipped,
            Cancelled = false
        };
    }

    /// <summary>
    /// Lance msiexec pour un MSI (/i) ou un MSP (/p) en mode silencieux avec log,
    /// attente de la fin et recuperation du code de sortie.
    /// </summary>
    private static int RunMsiLike(string primarySwitch, FileInfo file, BentleyModule mod)
    {
        string logName = $"Bentley_{mod.Num:D2}_{Regex.Replace(mod.Name, @"\s", "_")}.log";
        string logPath = Path.Combine(Path.GetTempPath(), logName);

        // Meme chaine d'arguments que le source PS (espace final inclus).
        string arguments = $"{primarySwitch} \"{file.FullName}\" /qn /norestart /log \"{logPath}\" ";

        var psi = new ProcessStartInfo
        {
            FileName = "msiexec.exe",
            Arguments = arguments,
            UseShellExecute = false,
            CreateNoWindow = true
            // PAS de redirection de sortie : personne ne lit les tuyaux ici, et un
            // buffer plein bloquerait WaitForExit indefiniment (deadlock classique).
            // msiexec /qn ne dialogue pas sur la console ; tout passe par /log.
        };

        using var proc = Process.Start(psi)!;
        proc.WaitForExit();
        return proc.ExitCode;
    }

    /// <summary>
    /// Lance un EXE silencieux en elevation (UseShellExecute + verb runas),
    /// attente de la fin et recuperation du code de sortie.
    /// </summary>
    private static int RunSilentExe(FileInfo file)
    {
        var psi = new ProcessStartInfo
        {
            FileName = file.FullName,
            Arguments = DefaultSilentExeArgs,
            UseShellExecute = true,
            Verb = "runas"
        };

        using var proc = Process.Start(psi)!;
        proc.WaitForExit();
        return proc.ExitCode;
    }

    /// <summary>
    /// Lance un installateur manuel en mode INTERACTIF (fenetre visible, elevation
    /// via runas, aucun argument silencieux) puis attend sa fermeture en verifiant
    /// l'annulation toutes les 500 ms. Des que l'utilisateur termine l'action,
    /// le moteur reprend automatiquement le module suivant (spec reprise automatique).
    /// </summary>
    private int RunInteractiveExe(FileInfo file, CancellationToken cancellationToken)
    {
        var psi = new ProcessStartInfo
        {
            FileName = file.FullName,
            UseShellExecute = true,
            Verb = "runas"
        };

        using var proc = Process.Start(psi)
            ?? throw new InvalidOperationException($"Impossible de lancer l'installateur : {file.Name}");

        while (!proc.WaitForExit(500))
        {
            if (_cancelRequested || cancellationToken.IsCancellationRequested)
            {
                Say("Annulation demandee pendant l'action manuelle : fermeture de l'installateur...", "ATTENTION");
                try { proc.Kill(entireProcessTree: true); }
                catch { }
                throw new OperationCanceledException("Installation annulee pendant une action manuelle.", cancellationToken);
            }
        }
        return proc.ExitCode;
    }

    /// <summary>
    /// Import de secours pour un module dont le fichier est introuvable au moment
    /// de son etape : consulte d'abord FileOverrides (import par double-clic avant
    /// le demarrage), puis invoke le selectionneur ResolveMissing fourni par
    /// l'interface (fenetre de choix de fichier bloquante). Renvoie le FileInfo
    /// utilise ou null si l'utilisateur ne fournit rien.
    /// </summary>
    private FileInfo? TryResolveMissing(BentleyModule mod, CancellationToken cancellationToken)
    {
        if (FileOverrides.TryGetValue(mod.Num, out var overridePath)
            && !string.IsNullOrWhiteSpace(overridePath) && File.Exists(overridePath))
        {
            Say($"Module {mod.Num:D2} - {mod.Name} : fichier importe manuellement : {Path.GetFileName(overridePath)}", "OK");
            return new FileInfo(overridePath);
        }

        var resolver = ResolveMissing;
        if (resolver is null) return null;
        if (_cancelRequested || cancellationToken.IsCancellationRequested) return null;

        Say($"Module {mod.Num:D2} - {mod.Name} : introuvable dans le dossier source. Selectionnez le fichier de secours (ou annulez pour passer).", "ATTENTION");
        string? chosen = null;
        try { chosen = resolver(mod); }
        catch (Exception ex) { Say($"Selecteur de fichier : {ex.Message}", "ERREUR"); }

        if (!string.IsNullOrWhiteSpace(chosen) && File.Exists(chosen))
        {
            FileOverrides[mod.Num] = chosen;
            Say($"Module {mod.Num:D2} - {mod.Name} : secours accepte : {Path.GetFileName(chosen)}", "OK");
            return new FileInfo(chosen);
        }
        return null;
    }

    /// <summary>Invoque le callback de journalisation (level par defaut INFO).</summary>
    private void Say(string message, string level = "INFO") => Log(message, level);

    /// <summary>Invoque la progression contractuelle et l'evenement module-enrichi.</summary>
    private void Update(int percent, string status, int moduleIndex, BentleyModule? module)
    {
        Progress(percent, status);
        ModuleProgressed?.Invoke(percent, status, moduleIndex, module);
    }
}
