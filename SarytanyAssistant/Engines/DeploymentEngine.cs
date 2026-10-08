// ==================================================================
// Engines\DeploymentEngine.cs - Moteur de deploiement Bentley
//   Port fidele de complet\src\20-Engine-Deployment.ps1 :
//   Copie du profil PowerDraft vers C:\IT_Config, le profil par defaut
//   et chaque profil utilisateur, puis deploiement automatique a chaque
//   ouverture de session (entree RunOnce machine auto-reparatrice).
//   Moteur testable : aucune dependance a l'interface graphique.
// ==================================================================
using System.Diagnostics;
using System.Text;
using Microsoft.Win32;

namespace SarytanyAssistant.Engines;

/// <summary>
/// Parametres du moteur de deploiement (valeurs par defait identiques
/// aux parametres du script PowerShell d'origine).
/// </summary>
public sealed class DeploymentOptions
{
    /// <summary>Source de reference deployee : C:\IT_Config\Bentley ($SourceConfig).</summary>
    public string SourceConfig { get; set; } = @"C:\IT_Config\Bentley";

    /// <summary>Profil de reference it_st ($ItStSource).</summary>
    public string ItStSource { get; set; } = @"C:\Users\it_st\AppData\Local\Bentley\PowerDraft";

    /// <summary>Profil par defaut ($DefaultPath).</summary>
    public string DefaultPath { get; set; } = @"C:\Users\Default\AppData\Local\Bentley\PowerDraft";

    /// <summary>Racine des profils ($UsersRoot).</summary>
    public string UsersRoot { get; set; } = @"C:\Users";

    /// <summary>Repertoire d'installation du script de logon (Install-AutoDeploy : $LogonDir).</summary>
    public string LogonDir { get; set; } = @"C:\IT_Config";

    /// <summary>Chemin PS de l'entree RunOnce (Install-AutoDeploy : $RunOnceKey).</summary>
    public string RunOnceKey { get; set; } = @"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce";

    /// <summary>Nom de la valeur RunOnce (Install-AutoDeploy : $ValueName).</summary>
    public string RunOnceValueName { get; set; } = "BentleyPowerDraftConfig";

    /// <summary>
    /// Source utilisee par le script de logon (Install-AutoDeploy : $SourcePath).
    /// Null = SourceConfig, comme le defaut du script PowerShell.
    /// </summary>
    public string? SourcePath { get; set; }
}

/// <summary>Profil utilisateur cible (sortie de Get-DeployTargets).</summary>
public sealed class DeployTarget
{
    public DeployTarget(string name, string path)
    {
        Name = name;
        Path = path;
    }

    /// <summary>Nom du dossier de profil.</summary>
    public string Name { get; }

    /// <summary>Chemin complet AppData\Local\Bentley\PowerDraft du profil.</summary>
    public string Path { get; }
}

/// <summary>Resultat de Invoke-BentleyDeployment.</summary>
public sealed class DeploymentResult
{
    /// <summary>Nombre de profils mis a jour avec succes ($done).</summary>
    public int Updated { get; init; }

    /// <summary>Nombre total de profils cibles detectes.</summary>
    public int Targets { get; init; }

    /// <summary>Noms des profils en echec.</summary>
    public List<string> Failed { get; init; } = new();

    /// <summary>Nombre de fichiers de la source de reference.</summary>
    public int Files { get; init; }

    /// <summary>Vrai si aucun profil n'a echoue.</summary>
    public bool Success { get; init; }
}

/// <summary>Resultat de Install-AutoDeploy.</summary>
public sealed class AutoDeployResult
{
    public bool Success { get; init; }

    /// <summary>Chemin du script PowerShell de logon genere.</summary>
    public string ScriptPath { get; init; } = "";

    /// <summary>Chemin du wrapper .cmd auto-reparateur.</summary>
    public string CmdPath { get; init; } = "";

    /// <summary>Chemin complet de l'entree RunOnce ecrite (clef\valeur).</summary>
    public string RunOnceKey { get; init; } = "";
}

/// <summary>
/// Moteur de deploiement Bentley (port de 20-Engine-Deployment.ps1) :
/// robocopy vers la source de reference, le profil Default et chaque
/// profil utilisateur, + installation RunOnce auto-reparatrice.
/// Aucune dependance a l'interface graphique.
/// </summary>
public class DeploymentEngine : IEngine
{
    /// <summary>Interrupteurs robocopy de Copy-Tree (identiques au PS).</summary>
    public static readonly string[] RoboSwitches =
        { "/E", "/IS", "/IT", "/R:1", "/W:1", "/NFL", "/NDL", "/NJH", "/NJS", "/NP", "/XJ" };

    /// <summary>Exclusions de profils de Get-DeployTargets (identiques au PS).</summary>
    public static readonly string[] ProfileExclusions =
        { "Public", "Default", "All Users", "Default User", "Desktop.ini" };

    /// <summary>
    /// Script de logon genere (port EXACT de $script:LogonScriptTemplate ;
    /// placeholder __SOURCE__ remplace par la source).
    /// </summary>
    public const string LogonScriptTemplate = @"# Deploiement automatique du profil Bentley PowerDraft - genere par l'assistant Sarytany.
# Execute a chaque ouverture de session, dans le contexte de l'utilisateur connecte.
$Source      = '__SOURCE__'
$Destination = Join-Path $env:LOCALAPPDATA 'Bentley\PowerDraft'
if (Test-Path -LiteralPath $Source) {
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        & robocopy.exe $Source $Destination /E /IS /IT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XJ | Out-Null
        if ($LASTEXITCODE -lt 8) { Write-Out ""Configuration PowerDraft deployee pour $env:USERNAME."" }
    } else {
        Write-Out ""Configuration Bentley deja presente pour $env:USERNAME.""
    }
}";

    /// <summary>
    /// Wrapper cmd auto-reparateur (port EXACT de $script:LogonCmdTemplate ;
    /// placeholders __VALUENAME__, __CMD__, __PS1__ remplaces dans cet ordre).
    /// </summary>
    public const string LogonCmdTemplate = @"@echo off
reg add ""HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"" /v __VALUENAME__ /t REG_SZ /d ""__CMD__"" /f >nul 2>&1
""%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""__PS1__""
exit /b 0";

    // UTF-8 avec BOM : identique a Set-Content -Encoding UTF8 sous Windows PowerShell 5.1.
    private static readonly UTF8Encoding Utf8WithBom = new(encoderShouldEmitUTF8Identifier: true);

    /// <summary>
    /// Port de Invoke-BentleyDeployment : deploiement en 3 etapes
    /// (source de reference it_st -> C:\IT_Config, profil Default, chaque profil).
    /// L'annulation cooperative remplace $script:CancelRequested (verifiee entre
    /// les etapes et a chaque iteration de profil, exactement comme le PS).
    /// </summary>
    public DeploymentResult Run(DeploymentOptions o, ProgressHandler? progress = null,
                                LogHandler? log = null, CancellationToken cancel = default)
    {
        ProgressHandler upd = progress ?? EngineDefaults.NullProgress;
        LogHandler say = log ?? EngineDefaults.NullLog;

        // --- Etape 1 : source de reference ---
        upd(5, "Preparation de la source de reference...");
        if (Directory.Exists(o.ItStSource))
        {
            say($"Profil 'it_st' detecte : {o.ItStSource}", "OK");
            CopyTree(o.ItStSource, o.SourceConfig);
            say($"Reference synchronisee dans : {o.SourceConfig}", "OK");
        }
        else if (Directory.Exists(o.SourceConfig))
        {
            say($"Reference existante utilisee : {o.SourceConfig}", "INFO");
        }
        else
        {
            say("Aucun profil PowerDraft de reference trouve (ni it_st ni IT_Config).", "ERREUR");
            throw new InvalidOperationException("Source de reference introuvable.");
        }
        int fileCount = CountFiles(o.SourceConfig);
        say($"Source de reference validee ({fileCount} fichiers).", "OK");

        // --- Etape 2 : profil par defaut ---
        if (cancel.IsCancellationRequested)
            throw new OperationCanceledException("Operation annulee par l'utilisateur.");
        upd(35, "Mise a jour du profil par defaut...");
        CopyTree(o.SourceConfig, o.DefaultPath);
        say($"Profil par defaut (Default) mis a jour : {o.DefaultPath}", "OK");

        // --- Etape 3 : profils utilisateurs existants ---
        upd(50, "Propagation aux profils utilisateurs existants...");
        List<DeployTarget> targets = GetDeployTargets(o.UsersRoot);
        if (targets.Count == 0)
            say($"Aucun profil utilisateur detecte dans {o.UsersRoot} (etape 3 sans objet).", "ATTENTION");
        int done = 0;
        var failed = new List<string>();
        for (int i = 0; i < targets.Count; i++)
        {
            if (cancel.IsCancellationRequested)
                throw new OperationCanceledException("Operation annulee par l'utilisateur.");
            int index = i + 1;
            DeployTarget t = targets[i];
            // Convert.ToInt32 = arrondi du cast [int] de PowerShell (pas de troncature).
            upd(50 + Convert.ToInt32(40.0 * index / Math.Max(1, targets.Count)), $"Profil : {t.Name}");
            try
            {
                CopyTree(o.SourceConfig, t.Path);
                done++;
                int n = CountFiles(t.Path);
                say($"Profil mis a jour : {t.Name} ({n} fichiers)", "OK");
            }
            catch (Exception ex)
            {
                failed.Add(t.Name);
                say($"ECHEC sur le profil {t.Name} : {ex.Message}", "ERREUR");
            }
        }

        upd(100, "Termine");
        return new DeploymentResult
        {
            Success = failed.Count == 0,
            Updated = done,
            Failed = failed,
            Targets = targets.Count,
            Files = fileCount,
        };
    }

    /// <summary>
    /// Port de Copy-Tree : robocopy /E /IS /IT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XJ,
    /// code de sortie &gt;= 8 = echec. Retourne le code de sortie robocopy.
    /// </summary>
    public static int CopyTree(string from, string to)
    {
        if (!Directory.Exists(from))
            throw new InvalidOperationException($"Source introuvable : {from}");
        if (!Directory.Exists(to))
            Directory.CreateDirectory(to);

        var psi = new ProcessStartInfo("robocopy.exe")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        // ArgumentList : pas de découpage par l'invite, espaces dans les chemins compris.
        psi.ArgumentList.Add(from);
        psi.ArgumentList.Add(to);
        foreach (string sw in RoboSwitches)
            psi.ArgumentList.Add(sw);

        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException($"Demarrage impossible : robocopy.exe {from} -> {to}");
        // Lecture asynchrone de stderr pour eviter tout blocage de tuyau (2>&1 en PS).
        var stderrBuilder = new StringBuilder();
        process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is not null)
                stderrBuilder.AppendLine(e.Data);
        };
        process.BeginErrorReadLine();
        string stdout = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        int code = process.ExitCode;

        if (code >= 8)
        {
            string joined = JoinOutputLines(stdout, stderrBuilder.ToString());
            throw new InvalidOperationException(
                $"Robocopy a echoue (code {code}) pour {from} -> {to} :: {joined}");
        }
        return code;
    }

    /// <summary>
    /// Port de Get-DeployTargets : dossiers de $Root sans les exclusions
    /// Public/Default/All Users/Default User/Desktop.ini, points de reanalyse ignores,
    /// cible = AppData\Local\Bentley\PowerDraft.
    /// </summary>
    public static List<DeployTarget> GetDeployTargets(string root)
    {
        var targets = new List<DeployTarget>();
        if (!Directory.Exists(root))
            return targets;

        DirectoryInfo[] dirs;
        try
        {
            // GetDirectories inclut cache/systeme, comme -Force en PS ; erreurs = SilentlyContinue.
            dirs = new DirectoryInfo(root).GetDirectories();
        }
        catch (Exception)
        {
            return targets;
        }

        foreach (DirectoryInfo d in dirs)
        {
            if (ProfileExclusions.Contains(d.Name, StringComparer.OrdinalIgnoreCase))
                continue;
            try
            {
                if ((d.Attributes & FileAttributes.ReparsePoint) != 0)
                    continue;
            }
            catch (Exception)
            {
                continue;
            }
            targets.Add(new DeployTarget(
                d.Name,
                Path.Combine(d.FullName, "AppData", "Local", "Bentley", "PowerDraft")));
        }
        return targets;
    }

    /// <summary>
    /// Port de Install-AutoDeploy : ecrit Deploy-Bentley.ps1 + Deploy-Bentley.cmd
    /// dans $LogonDir, puis l'entree RunOnce machine (HKLM) auto-reparatrice,
    /// et verifie la valeur relue.
    /// </summary>
    public AutoDeployResult InstallAutoDeploy(DeploymentOptions o, LogHandler? log = null)
    {
        LogHandler say = log ?? EngineDefaults.NullLog;
        string logonDir = o.LogonDir;
        string runOnceKey = o.RunOnceKey;
        string valueName = o.RunOnceValueName;
        string sourcePath = o.SourcePath ?? o.SourceConfig;

        if (!Directory.Exists(logonDir))
            Directory.CreateDirectory(logonDir);
        string ps1Path = Path.Combine(logonDir, "Deploy-Bentley.ps1");

        // Set-Content -Encoding UTF8 (PS 5.1) : UTF-8 avec BOM + saut de ligne final.
        string ps1Body = NormalizeNewlines(LogonScriptTemplate.Replace("__SOURCE__", sourcePath));
        File.WriteAllText(ps1Path, ps1Body + Environment.NewLine, Utf8WithBom);
        if (!File.Exists(ps1Path))
            throw new InvalidOperationException($"Ecriture impossible : {ps1Path}");
        say($"Script de logon ecrit : {ps1Path}", "OK");

        string cmdPath = Path.Combine(logonDir, "Deploy-Bentley.cmd");
        // Ordre des remplacements identique au PS : __VALUENAME__ puis __CMD__ puis __PS1__.
        string cmdBody = NormalizeNewlines(
            LogonCmdTemplate
                .Replace("__VALUENAME__", valueName)
                .Replace("__CMD__", cmdPath)
                .Replace("__PS1__", ps1Path));
        File.WriteAllText(cmdPath, cmdBody + Environment.NewLine, Encoding.ASCII);
        if (!File.Exists(cmdPath))
            throw new InvalidOperationException($"Ecriture impossible : {cmdPath}");
        say($"Wrapper ecrit : {cmdPath}", "OK");

        // Test-Path / New-Item -Force puis New-ItemProperty -Force : CreateSubKey + SetValue.
        (RegistryHive hive, string subKey) = SplitRegistryPath(runOnceKey);
        using RegistryKey baseKey = RegistryKey.OpenBaseKey(hive, RegistryView.Default);
        using RegistryKey key = baseKey.CreateSubKey(subKey)
            ?? throw new InvalidOperationException($"Creation impossible : {runOnceKey}");
        key.SetValue(valueName, "\"" + cmdPath + "\"", RegistryValueKind.String);
        say($@"Entree RunOnce ecrite : {runOnceKey}\{valueName}", "OK");

        // Port de Get-RegValue : erreur si la valeur est absente (Get-ItemProperty -ErrorAction Stop).
        object? readBack = key.GetValue(valueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
        if (readBack is null)
            throw new InvalidOperationException($"La valeur '{valueName}' est absente de {runOnceKey}");
        string readBackText = Convert.ToString(readBack) ?? "";
        // "-notlike ""*$cmdPath*""" en PS = contient, insensible a la casse.
        if (!readBackText.Contains(cmdPath, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"RunOnce ne pointe pas vers le bon wrapper : {readBackText}");
        if (!File.Exists(cmdPath))
            throw new InvalidOperationException($"Wrapper enregistre introuvable : {cmdPath}");
        say($"Verification OK - RunOnce pointe vers : {readBackText}", "OK");

        return new AutoDeployResult
        {
            Success = true,
            ScriptPath = ps1Path,
            CmdPath = cmdPath,
            RunOnceKey = runOnceKey + "\\" + valueName,
        };
    }

    /// <summary>
    /// Decompose un chemin de registre style PowerShell ("HKLM:\SOFTWARE\..." ou
    /// "HKEY_LOCAL_MACHINE\SOFTWARE\...") en ruche + sous-clef.
    /// </summary>
    private static (RegistryHive Hive, string SubKey) SplitRegistryPath(string path)
    {
        string p = path.Trim();
        const int drivePrefixLen = 5; // "HKLM:" / "HKCU:" (le backslash-suivant est trimme)
        if (p.StartsWith(@"HKLM:\", StringComparison.OrdinalIgnoreCase))
            return (RegistryHive.LocalMachine, p[drivePrefixLen..].TrimStart('\\'));
        if (p.StartsWith(@"HKCU:\", StringComparison.OrdinalIgnoreCase))
            return (RegistryHive.CurrentUser, p[drivePrefixLen..].TrimStart('\\'));
        if (p.StartsWith(@"HKEY_LOCAL_MACHINE\", StringComparison.OrdinalIgnoreCase))
            return (RegistryHive.LocalMachine, p[18..].TrimStart('\\'));
        if (p.StartsWith(@"HKEY_CURRENT_USER\", StringComparison.OrdinalIgnoreCase))
            return (RegistryHive.CurrentUser, p[17..].TrimStart('\\'));
        throw new ArgumentException($"Chemin de registre non pris en charge : {path}", nameof(path));
    }

    /// <summary>
    /// Port de (Get-ChildItem -Recurse -File -Force -ErrorAction SilentlyContinue).Count.
    /// Les erreurs d'acces sont ignorees et les points de reanalyse ne sont pas
    /// suivis (anti-boucle /XJ, coherent avec robocopy).
    /// </summary>
    private static int CountFiles(string root)
    {
        int count = 0;
        if (!Directory.Exists(root))
            return count;
        var stack = new Stack<string>();
        stack.Push(root);
        while (stack.Count > 0)
        {
            string dir = stack.Pop();
            try
            {
                count += Directory.GetFiles(dir).Length;
                foreach (string sub in Directory.GetDirectories(dir))
                {
                    try
                    {
                        if ((new DirectoryInfo(sub).Attributes & FileAttributes.ReparsePoint) != 0)
                            continue;
                    }
                    catch (Exception)
                    {
                        continue;
                    }
                    stack.Push(sub);
                }
            }
            catch (Exception)
            {
                // -ErrorAction SilentlyContinue
            }
        }
        return count;
    }

    /// <summary>Normalise les fins de ligne en CRLF (comportement Set-Content sous Windows).</summary>
    private static string NormalizeNewlines(string text)
        => text.Replace("\r\n", "\n").Replace("\n", "\r\n");

    /// <summary>Joint sortie+erreur robocopy comme $($out -join ' | ') pour les messages d'erreur.</summary>
    private static string JoinOutputLines(string stdout, string stderr)
    {
        string[] lines = (stdout + Environment.NewLine + stderr)
            .Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.RemoveEmptyEntries)
            .Select(l => l.Trim())
            .Where(l => l.Length > 0)
            .ToArray();
        return string.Join(" | ", lines);
    }
}
