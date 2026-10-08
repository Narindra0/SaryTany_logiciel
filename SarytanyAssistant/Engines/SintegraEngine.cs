using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32;

namespace SarytanyAssistant.Engines;

/// <summary>
/// Moteur integration SintegraLidar (port de src\23-Engine-SintegraLidar.ps1) :
/// creation repertoire, permissions, copie fichiers, import registre,
/// PATH systeme, separateur decimal, integration Bentley PowerDraft (mvba).
/// Inclut le cryptage AES pour les valeurs sensibles.
/// Moteur testable : aucune dependance a l'interface graphique
/// (la selection du dossier source via FolderBrowserDialog reste dans la couche UI).
/// Inspire du projet SintegraLidar (Install-SintegraLidar.ps1).
/// </summary>
public class SintegraEngine : IEngine
{
    // --- Cryptage AES pour valeurs sensibles ---
    // Cle de 32 octets (256 bits) pour AES-256-CBC.
    // Repare : la cle d'origine faisait 62 caracteres (Base64 invalide,
    // longueur non multiple de 4) et plantait au chargement du module.
    // 43 caracteres + '=' = 44 caracteres = exactement 32 octets.
    private static readonly byte[] SintegraAesKey =
        Convert.FromBase64String("JFDHKJdhf23984hjsdfkjhSDKLJsfh2384hjsdfkjhS=");

    // --- Valeurs configurees (peuvent etre surchargees par parametres) ---

    /// <summary>Nom de l'application installee.</summary>
    public const string AppName = "SintegraLidar";

    /// <summary>Version de l'application installee.</summary>
    public const string AppVersion = "1.0.0";

    /// <summary>Nom du developpeur.</summary>
    public const string DevName = "Narindra Ranjalahy";

    /// <summary>Email de contact.</summary>
    public const string ContactEmail = "ranjalahy.narindraa@gmail.com";

    /// <summary>Telephone de contact.</summary>
    public const string ContactPhone = "0328814081";

    /// <summary>Nom du fichier registre a importer.</summary>
    public const string RegFileName = "Las2Laz+IIQ+EXIF.reg";

    /// <summary>Nom du module VBA Bentley a installer.</summary>
    public const string MvbaFileName = "SintegraLidarConnect.mvba";

    /// <summary>Repertoire Bentley PowerDraft (dossier des mvba).</summary>
    public const string BentleyDir = @"C:\ProgramData\Bentley\PowerDraft";

    /// <summary>Repertoire d'installation par defaut (surchargeable via Run).</summary>
    public const string DefaultDestDir = @"C:\Program Files\SintegraLidar";

    // Compteur d'essais : etat de l'instance (le moteur est un objet durable
    // de l'application), comme $script:SintegraTrialLaunches en PowerShell.
    private int _trialLaunches;

    /// <summary>Nombre de lancements du moteur effectues par cette instance.</summary>
    public int TrialLaunches => _trialLaunches;

    /// <summary>
    /// Chiffre une chaine en AES-256-CBC/PKCS7 (entree UTF-16, sortie Base64),
    /// exactement comme Encrypt-String du module PowerShell.
    /// L'IV aleatoire par appel est le comportement par defaut de AES.Create()
    /// en PowerShell ; le format reste donc binaire-compatible avec le PS.
    /// Retourne null si la chaine est nulle ou vide.
    /// </summary>
    public static string? EncryptString(string? plainText)
    {
        if (string.IsNullOrEmpty(plainText))
        {
            return null;
        }

        using var aes = Aes.Create();
        aes.Key = SintegraAesKey;
        aes.Mode = CipherMode.CBC;
        aes.Padding = PaddingMode.PKCS7;
        byte[] bytes = Encoding.Unicode.GetBytes(plainText);
        byte[] encrypted = aes.EncryptCbc(bytes, aes.IV);
        return Convert.ToBase64String(encrypted);
    }

    /// <summary>
    /// Dechiffre une chaine AES-256-CBC/PKCS7 Base64 (sortie UTF-16),
    /// comme Decrypt-String du module PowerShell. Retourne null en cas
    /// d'echec (Base64 invalide, bourrage incorrect, etc.).
    /// </summary>
    public static string? DecryptString(string? cipherText)
    {
        if (string.IsNullOrEmpty(cipherText))
        {
            return null;
        }

        try
        {
            byte[] bytes = Convert.FromBase64String(cipherText);
            using var aes = Aes.Create();
            aes.Key = SintegraAesKey;
            aes.Mode = CipherMode.CBC;
            aes.Padding = PaddingMode.PKCS7;
            byte[] plain = aes.DecryptCbc(bytes, aes.IV);
            return Encoding.Unicode.GetString(plain);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Protections anti-analyse (conservées depuis SintegraLidar) :
    /// meme comportement que Test-AnalysisEnvironment.
    /// </summary>
    public static bool TestAnalysisEnvironment()
    {
        // Verification du debogueur
        if (Debugger.IsAttached)
        {
            return true;
        }

        // Verification des noms d'ordinateur suspects
        string computerName = (Environment.GetEnvironmentVariable("COMPUTERNAME") ?? string.Empty)
            .ToUpperInvariant();
        string[] suspiciousNames = ["DEBUG", "ANALYSIS", "PEKER", "TEST", "VMWARE", "VIRTUAL", "SANDBOX"];
        if (suspiciousNames.Contains(computerName, StringComparer.OrdinalIgnoreCase))
        {
            return true;
        }

        // Verification des variables d'environnement d'analyse
        string[] analysisEnvVars = ["DEBUG", "ANALYSIS_TOOL", "PEID", "ILDASM", "DOTPEEK"];
        foreach (string variable in analysisEnvVars)
        {
            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable(variable)))
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// Le processus courant est-il eleve (administrateur) ?
    /// Port de Test-IsAdmin (definition seulement, non utilisee dans le flux d'installation).
    /// </summary>
    private static bool TestIsAdmin()
    {
        using WindowsIdentity identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    // Broadcast WM_SETTINGCHANGE (evite un redemarrage apres modification du PATH)
    private static readonly IntPtr HWND_BROADCAST = new(0xffff);
    private const uint WM_SETTINGCHANGE = 0x001A;
    private const uint SMTO_ABORTIFHUNG = 0x0002;

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);

    /// <summary>
    /// Ajoute de facon idempotente un repertoire au PATH systeme (Machine),
    /// rafraichit le PATH du processus courant et notifie WM_SETTINGCHANGE.
    /// Port fidele de Add-ToSystemPath ; retourne toujours true (comme le PS).
    /// </summary>
    public static bool AddToSystemPath(string dirToAdd)
    {
        string machinePath = Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.Machine)
            ?? string.Empty;
        if (string.IsNullOrEmpty(machinePath))
        {
            machinePath = string.Empty;
        }

        // Exists already in the PATH (case-insensitive, trailing '\' ignored)
        string target = dirToAdd.TrimEnd('\\');
        var entries = machinePath
            .Split(';')
            .Select(entry => entry.Trim())
            .Where(entry => entry.Length != 0);
        if (entries.Any(entry => entry.TrimEnd('\\')
                .Equals(target, StringComparison.OrdinalIgnoreCase)))
        {
            return true;
        }

        string newPath = (machinePath.TrimEnd(';') + ";" + dirToAdd).TrimStart(';');
        Environment.SetEnvironmentVariable("PATH", newPath, EnvironmentVariableTarget.Machine);

        // $env:Path = $env:Path.TrimEnd(';') + ";" + $DirToAdd
        string processPath = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        Environment.SetEnvironmentVariable("PATH", processPath.TrimEnd(';') + ";" + dirToAdd);

        // Notification WM_SETTINGCHANGE pour eviter le reboot
        try
        {
            _ = SendMessageTimeout(
                HWND_BROADCAST, WM_SETTINGCHANGE, UIntPtr.Zero, "Environment",
                SMTO_ABORTIFHUNG, 5000, out _);
        }
        catch
        {
            // La notification est facultative ; l'ajout au PATH est deja fait.
        }

        return true;
    }

    /// <summary>
    /// Execute les 7 etapes d'installation SintegraLidar :
    /// 0. Compteur d'essais ; 1. dossier source ; 2. creation + securisation
    /// destination ; 3. copie fichiers ; 4. import registre ; 5. ajout au PATH ;
    /// 6. separateur decimal = point ; 7. integration Bentley PowerDraft (mvba).
    /// L'annulation est verifiee avant l'increment du compteur d'essais et avant
    /// chaque etape (ordre exact du module PowerShell corrige).
    /// </summary>
    /// <param name="sourceDir">Dossier source SintegraLidarCONNECT (choisi par la couche UI).</param>
    /// <param name="destDir">Dossier destination (defaut : C:\Program Files\SintegraLidar, decide par Sarytany le 2026-10-07).</param>
    /// <param name="trialLimit">Nombre maximum de lancements autorises.</param>
    /// <param name="progress">Callback progression (pourcentage, statut).</param>
    /// <param name="log">Callback journalisation (message, niveau INFO/OK/ERREUR/ATTENTION).</param>
    /// <param name="cancel">Jeton d'annulation cooperative.</param>
    /// <exception cref="OperationCanceledException">Annulation par l'utilisateur.</exception>
    /// <exception cref="InvalidOperationException">Limite d'essais, source absente ou non specifiee.</exception>
    public SintegraResult Run(
        string sourceDir,
        string? destDir = null,
        int trialLimit = 3,
        ProgressHandler? progress = null,
        LogHandler? log = null,
        CancellationToken cancel = default)
    {
        void Say(string message, string level = "INFO") => log?.Invoke(message, level);
        void Upd(int percent, string status) => progress?.Invoke(percent, status);
        void ThrowIfCancelled()
        {
            if (cancel.IsCancellationRequested)
            {
                throw new OperationCanceledException("Operation annulee par l'utilisateur.", cancel);
            }
        }

        if (string.IsNullOrEmpty(destDir))
        {
            destDir = DefaultDestDir;
        }

        // --- Etape 0 : trial counter ---
        ThrowIfCancelled();
        _trialLaunches++;
        if (_trialLaunches > trialLimit)
        {
            Say($"Limite d'essais atteinte ({trialLimit}). Utilisez le mode Deploy ou Configure.", "ERREUR");
            throw new InvalidOperationException($"Limite d'essais atteinte ({trialLimit}).");
        }

        // --- Etape 1 : source ---
        ThrowIfCancelled();
        Upd(5, "Selection du dossier source...");
        if (string.IsNullOrEmpty(sourceDir))
        {
            // Le dialogue graphique de selection releve de la couche UI (pas du moteur).
            throw new InvalidOperationException("Aucun dossier source specifie.");
        }

        if (!Directory.Exists(sourceDir) && !File.Exists(sourceDir))
        {
            throw new InvalidOperationException($"Dossier source introuvable : {sourceDir}");
        }

        Say($"Source : {sourceDir}", "OK");

        // --- Etape 2 : destination + securite ---
        ThrowIfCancelled();
        Upd(15, $"Creation et securisation de {destDir}...");
        if (!Directory.Exists(destDir))
        {
            Directory.CreateDirectory(destDir);
        }

        // Tout le monde = Everyone (SID S-1-1-0, independant de la langue de l'OS)
        int icaclsExit = RunProcess(
            "icacls.exe",
            $"\"{destDir}\" /grant *S-1-1-0:(OI)(CI)F /T");
        if (icaclsExit != 0)
        {
            Say($"icacls a echoue (code {icaclsExit}). Continue...", "ATTENTION");
        }
        else
        {
            Say("Permissions Tout le monde = Autoriser tout appliquees.", "OK");
        }

        // --- Etape 3 : copie fichiers ---
        ThrowIfCancelled();
        Upd(35, "Copie des fichiers source...");
        if (Directory.GetFileSystemEntries(sourceDir).Length > 0)
        {
            CopyDirectoryContents(sourceDir, destDir);
            Say($"Fichiers copies vers {destDir}", "OK");
        }
        else
        {
            Say("Le dossier source est vide.", "ATTENTION");
        }

        // --- Etape 4 : import registre ---
        ThrowIfCancelled();
        Upd(50, "Import du registre...");
        string regSource = Path.Combine(sourceDir, RegFileName);
        string regDest = Path.Combine(destDir, RegFileName);
        string? regToImport = null;
        if (File.Exists(regDest))
        {
            regToImport = regDest;
        }
        else if (File.Exists(regSource))
        {
            regToImport = regSource;
        }

        if (regToImport is null)
        {
            Say($"Fichier {RegFileName} introuvable. Etape ignoree.", "ATTENTION");
        }
        else
        {
            Say($"Import : {regToImport}", "INFO");
            int regExit = RunProcess("reg.exe", $"import \"{regToImport}\"");
            if (regExit != 0)
            {
                Say($"reg import a echoue (code {regExit}).", "ERREUR");
            }
            else
            {
                Say("Registre importe avec succes.", "OK");
                // Suppression apres import reussi
                if (File.Exists(regDest))
                {
                    File.Delete(regDest);
                    Say($"Fichier registre supprime : {regDest}", "OK");
                }
            }
        }

        // --- Etape 5 : PATH ---
        ThrowIfCancelled();
        Upd(60, "Ajout au PATH systeme...");
        bool pathAdded = AddToSystemPath(destDir);
        if (pathAdded)
        {
            Say($"Ajout au PATH systeme : {destDir}", "OK");
        }

        // --- Etape 6 : separateur decimal ---
        ThrowIfCancelled();
        Upd(75, "Configuration du separateur decimal...");
        const string InternationalKeyPath = @"Control Panel\International";
        string? currentThousand = null;
        using (RegistryKey? readable = Registry.CurrentUser.OpenSubKey(InternationalKeyPath))
        {
            if (readable is not null)
            {
                // sDecimal est lu comme en PS mais seule la valeur de sThousand est utilisee.
                _ = readable.GetValue("sDecimal");
                currentThousand = readable.GetValue("sThousand") as string;
            }
        }

        using (RegistryKey? writable = Registry.CurrentUser.CreateSubKey(InternationalKeyPath))
        {
            if (writable is null)
            {
                throw new InvalidOperationException(
                    $"Impossible d'ecrire la cle registre : HKCU\\{InternationalKeyPath}");
            }

            writable.SetValue("sDecimal", ".");
            if (currentThousand == ".")
            {
                writable.SetValue("sThousand", " ");
            }
        }

        Say("sDecimal defini a '.' (redemarrage peut etre necessaire).", "OK");

        // --- Etape 7 : integration Bentley ---
        ThrowIfCancelled();
        Upd(90, "Integration Bentley PowerDraft...");
        string mvbaSource = Path.Combine(sourceDir, MvbaFileName);
        if (!File.Exists(mvbaSource))
        {
            string altSource = Path.Combine(destDir, MvbaFileName);
            if (File.Exists(altSource))
            {
                mvbaSource = altSource;
            }
        }

        if (!File.Exists(mvbaSource))
        {
            Say($"Fichier {MvbaFileName} introuvable. Etape ignoree.", "ATTENTION");
        }
        else
        {
            if (!Directory.Exists(BentleyDir))
            {
                Directory.CreateDirectory(BentleyDir);
            }

            File.Copy(mvbaSource, Path.Combine(BentleyDir, MvbaFileName), overwrite: true);
            Say($@"Copie vers {BentleyDir}\{MvbaFileName}", "OK");
        }

        Upd(100, "Termine");
        return new SintegraResult(
            Success: true,
            DestDir: destDir,
            AppName: AppName,
            AppVersion: AppVersion,
            TrialNumber: _trialLaunches);
    }

    /// <summary>Execute un processus en attente et retourne son code de sortie (Start-Process -Wait -PassThru).</summary>
    private static int RunProcess(string fileName, string arguments)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
            },
        };
        process.Start();
        process.WaitForExit();
        return process.ExitCode;
    }

    /// <summary>
    /// Copie recursivement le contenu de <paramref name="sourceDir"/> vers
    /// <paramref name="destDir"/> en ecrasant (Copy-Item source\* -Recurse -Force).
    /// </summary>
    private static void CopyDirectoryContents(string sourceDir, string destDir)
    {
        foreach (string sourceSubDir in Directory.GetDirectories(sourceDir))
        {
            string targetSubDir = Path.Combine(destDir, Path.GetFileName(sourceSubDir));
            Directory.CreateDirectory(targetSubDir);
            CopyDirectoryContents(sourceSubDir, targetSubDir);
        }

        foreach (string sourceFile in Directory.GetFiles(sourceDir))
        {
            File.Copy(sourceFile, Path.Combine(destDir, Path.GetFileName(sourceFile)), overwrite: true);
        }
    }
}

/// <summary>
/// Resultat d'une installation SintegraLidar (miroir de l'objet retourne
/// par Invoke-SintegraLidarInstall en PowerShell).
/// </summary>
/// <param name="Success">Installation terminee jusqu'au bout.</param>
/// <param name="DestDir">Repertoire d'installation utilise.</param>
/// <param name="AppName">Nom de l'application.</param>
/// <param name="AppVersion">Version de l'application.</param>
/// <param name="TrialNumber">Numero du lancement d'essai courant.</param>
public sealed record SintegraResult(
    bool Success,
    string DestDir,
    string AppName,
    string AppVersion,
    int TrialNumber);
