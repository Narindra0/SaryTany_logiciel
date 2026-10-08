namespace SarytanyAssistant.Engines;

/// <summary>
/// Contrat commun des moteurs (port des src\2x-Engine-*.ps1) :
/// log(message, level) avec level in { INFO, OK, ERREUR, ATTENTION },
/// progress(percent 0-100, status), etprise annulation cooperative.
/// Les moteurs ne touchent JAMAIS a l'interface : memes regles que les
/// moteurs PowerShell d'origine (testables seuls).
/// </summary>
public interface IEngine
{
}

/// <summary>Delegue de journalisation partage par tous les moteurs.</summary>
public delegate void LogHandler(string message, string level);

/// <summary>Delegue de progression partage par tous les moteurs.</summary>
public delegate void ProgressHandler(int percent, string status);

/// <summary>Petits helpers partages par les moteurs.</summary>
public static class EngineDefaults
{
    public static readonly LogHandler NullLog = (_, _) => { };
    public static readonly ProgressHandler NullProgress = (_, _) => { };
}
