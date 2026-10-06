# PowerDraft / Terra — Assistant d'installation et de configuration

Interface graphique Windows (design « Maquette v2 ») pour l'installation,
l'initialisation et la configuration de Bentley PowerDraft avec les modules
TerraMatch, TerraModeler et TerraScan. Livré en un seul `.exe` autonome.

---

## Structure

```
azafady/
├─ src/
│  ├─ main.ps1              point d'entrée (mode développement : .\main.ps1)
│  ├─ 01-Config.ps1         palette, étapes, chemins, persistance, activation SHA256
│  ├─ 02-Helpers.ps1        Test-Admin, Add-Log, Paint-Log, toast, Set-Step/Progress
│  ├─ 03-Steps.ps1          les 6 fonctions d'étape (booléennes)
│  ├─ 04-Orchestration.ps1  enchaînement, progression, réinitialisation, Start-Application
│  └─ 05-UI.ps1             fenêtre principale, modales, Réglages, Journal (design v2)
├─ build/
│  └─ build.ps1             concatène les modules puis compile en .exe (ps2exe)
├─ dist/
│  └─ PowerDraft-Setup.exe  exécutable autonome (le livrable)
└─ _archive/                anciennes versions (keygen / import licences) — inutilisées
```

Le code est découpé par responsabilité. L'ordre des fichiers est significatif :
`01` définit la configuration et les collections, `02` les fonctions utilitaires
qui les utilisent, `03` les étapes, `04` l'orchestration, `05` l'interface.

---

## Design — « Maquette v2 »

- **Barre de titre personnalisée** (claire) avec logo accent, icône ✕ et
  déplacement de la fenêtre par glisser-déposer.
- **Bande d'en-tête accent** (`#005078`) : titre « Bentley PowerDraft – Modules
  Terra », sous-titre et badge du niveau de droits (Administrateur / Droits insuffisants).
- **6 cartes d'étape** avec icônes rondes à état (attente → chiffre, ok → ✓,
  err → ✕, run → ●) et badge de statut coloré (en attente / Terminé / Échec / En cours).
- **Barre de statut** en bas avec jauge de progression (largeur = % des étapes faites).
- **Fenêtres flottantes** (Réglages, Journal) avec leur propre barre de titre,
  positionnées en cascade à côté de la fenêtre principale.
- **Journal coloré** : horodatage + niveaux `[INFO]` `[OK]` `[WARN]` `[ERR]` en
  couleurs, boutons *Exporter…* et *Effacer*.
- **Notifications toast** (ex. « Réglages enregistrés », « Journal exporté »).
- **Accent** : `#005078`. États : ok `#D1E7DD`, err `#F8D7DA`, run `#FFF3CD`, attente `#F8F9FA`.

---

## Les 6 étapes

| # | Étape | Contenu |
|---|---|---|
| 1 | Sécurité & antivirus | État Defender, comptage des éléments en quarantaine, ouverture de Windows Security pour ajouter une **exclusion** |
| 2 | Localisation du dossier Terra | Recherche du sous-dossier `eng` puis de `setup.exe` à partir du dossier principal (demandé si non renseigné, ou via **Réglages**) |
| 3 | Initialisation PowerDraft | Lancement, fermeture propre, attente de `%LocalAppData%\Bentley\PowerDraft\10.0.0` |
| 4 | Installation (setup.exe) | Lancement de l'installeur, sélection de la version *PowerDraft CE*, attente de **Terminer** |
| 5 | Collecte système | Computer Name et Computer ID (*Tools > About > Copy for email*) |
| 6 | Configuration finale | Copie de `PTC_LAS.ptc` vers `C:\terra64\tscan`, relance pour le premier chargement |

Règle critique de l'étape 4 : **ne jamais cliquer sur Abort**. L'interface
affiche cet avertissement dans le journal et la boucle d'attente ne se termine
que lorsque l'utilisateur clique réellement sur **Terminer** (ou après 60 min,
auquel cas l'exécution s'arrête). En mode `/quiet`, la sélection de version est
ignorée (avertissement dans le journal) et l'installeur se termine seul.

L'exécution s'arrête à la première étape en échec. Chaque étape peut aussi être
lancée seule en cliquant sa carte.

> **Sans keygen, sans licence** : le programme n'automatise que l'installation
> et la configuration. Il n'y a pas d'activation de licence par keygen ni
> d'import de fichiers `.lic` (les anciennes versions sont dans `_archive/`).

---

## Activation au lancement

À l'ouverture, une fenêtre **Activation requise** demande un code d'activation
avant de démarrer.

- Code d'activation : `NARINDRA2006`
- Le code n'est **jamais stocké en clair** dans l'exécutable : seule son
  empreinte SHA256 est comparée.
- **Surcharge en environnement** : la variable `POWERDRAFT_ACTIVATION` définit
  un code alternatif sans recompilation.
- **Changement permanent** : créez
  `%LOCALAPPDATA%\PowerDraftSetup\activation.dat` contenant l'empreinte SHA256
  (hexadécimale, minuscules) du nouveau code. Calcul d'une empreinte :

  ```powershell
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $h = ([System.BitConverter]::ToString($sha.ComputeHash(
       [System.Text.Encoding]::UTF8.GetBytes('VOTRE-CODE')))).Replace('-','').ToLowerInvariant()
  $h
  ```

Le code est vérifié comme :
`Test-ActivationCode` = `Get-ActivationHash($code)` = empreinte
`44947097d64e9c8bdf46b5397bb3aeef18bc72afd449037357ed1d060d2bc02f`.

---

## Utilisation

### Développement

```powershell
cd src
.\main.ps1
```

Au démarrage : fenêtre d'activation, puis la fenêtre principale. Le dossier
Terra est demandé par l'étape 2 s'il n'est pas renseigné (modifiable dans
**Réglages**). Les choix sont mémorisés dans
`%LocalAppData%\PowerDraftSetup\settings.json`.

### Production — un seul .exe

```powershell
cd build
.\build.ps1 -Version 2.0.2
```

`build.ps1` installe `ps2exe` s'il est absent, concatène les cinq modules de
`src/` en un script unique temporaire, vérifie sa syntaxe, puis compile avec
`-noConsole -STA` vers `dist\PowerDraft-Setup.exe`. L'exécutable ne dépend
d'aucun fichier externe.

Options :

| Option | Effet |
|---|---|
| `-Version 2.0.2` | Incorpore la version dans les métadonnées du `.exe` |
| `-KeepIntermediate` | Conserve `build/PowerDraft-Setup.combined.ps1` pour débogage |

> **Encodage** : les sources `src/*.ps1` doivent rester en UTF-8 **avec BOM**
> (PowerShell 5.1 lit sinon en ANSI et corrompt les accents). `build.ps1` écrit
> le script combiné avec BOM — ne pas modifier ce comportement.

### Exécution

Clic droit sur l'exécutable > *Exécuter en tant qu'administrateur*. Les droits
administrateur sont nécessaires pour l'étape 4.

---

## Chemins configurables

Tous les chemins sont modifiables dans **Réglages** avant lancement :

| Champ | Défaut |
|---|---|
| Dossier principal Terra | demandé par l'étape 2, mémorisé |
| `setup.exe` | déterminé par l'étape 2 |
| Version du setup | `PowerDraft CE` (ou `MicroStation CE`) |
| `PTC_LAS.ptc` | déterminé par l'étape 2 (recherche dans `eng`) |
| Dossier cible | `C:\terra64\tscan` |
| `PowerDraft.exe` | `C:\Program Files\Bentley\PowerDraft\PowerDraft.exe` |
| Computer ID | vide (à remplir après la collecte de l'étape 5) |

---

## Notes d'exploitation

- **Installation silencieuse** : laissez la case décochée. En mode `/quiet`,
  la sélection de version est ignorée — l'interface émet un avertissement.
- **Antivirus** : le programme n'altère pas la protection Windows. Ajoutez une
  exclusion pour le répertoire d'installation via *Windows Security > Virus &
  threat protection > Manage settings > Exclusions*.
- **Code de retour 3010** : traité comme « installation réussie, redémarrage
  requis ». Le code 1602 correspond à une annulation (Abort) et est signalé.
- **Journal** : exportable en `.log` ou `.txt` depuis le bouton *Exporter…*,
  horodaté et préfixé par niveau `[INFO]`, `[OK]`, `[WARN]`, `[ERR]`.

---

## Prérequis

- Windows 10 / 11
- PowerShell 5.1 ou supérieur (nécessaire à la compilation ; l'exe est autonome)
- Dossier Terra disponible (réseau `I:\...` ou local), contenant `eng\setup.exe`
  et `eng\PTC_LAS.ptc`