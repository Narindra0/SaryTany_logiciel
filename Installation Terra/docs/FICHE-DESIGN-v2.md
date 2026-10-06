# Fiche design — « Maquette v2 » (PowerDraft / Terra Setup)

Fiche de spécification de l'interface pour reproduction fidèle. Implémentation de
référence : `src/05-UI.ps1` (fenêtre principale, modales, Réglages, Journal),
`src/02-Helpers.ps1` (peinture du journal, toast), palette dans `src/01-Config.ps1`.

---

## 1. Palette (définitive)

| Rôle | Hex |
|---|---|
| accent (bandes, titres de groupe, bouton principal) | `#005078` |
| accentSoft (sous-titres sur accent) | `#BED7E8` |
| win (fond fenêtres) | `#F8F9FA` |
| line (bordures boutons) | `#DEE2E6` |
| ink (titres) / muted (descriptions) | `#212529` / `#6C757D` |
| pendBg / pendInk (carte en attente) | `#F1F3F5` / `#495057` |
| runBg / runInk (carte en cours) | `#FFF3CD` / `#856404` |
| okBg / okInk (carte terminée) | `#D1E7DD` / `#0F5132` |
| errBg / errInk (carte en échec) | `#F8D7DA` / `#842029` |
| go (valider / activer) | `#00723F` |
| grey (neutralité) | `#5A5F66` |
| tbBg / tbInk (barre de titre) | `#E8EBEE` / `#3A4046` |
| tbCloseHover (✕ survolé) | `#D13438` |
| logBg / logInk (fond fenêtre Journal) | `#1E2024` / `#D4D8DC` |
| logTm (horodatage du journal) | `#7C838B` |
| logBar (barre basse du Journal) | `#15171A` |
| logBtn / logBtnHover (boutons sombres) | `#1B1D21` / `#24272C` |
| log niveaux — info / ok / warn / err | `#9DB7CC` / `#6FD39B` / `#F1C75B` / `#F0868F` |
| statusBar (fond barre de statut) | `#EEF1F3` |
| track (piste de progression) | `#D5DADF` |
| hover bouton « line » | `#EEF1F3` |

## 2. Typographie

| Usage | Police | Taille |
|---|---|---|
| Base fenêtres | Segoe UI | 9 |
| Titre barre de titre | Segoe UI Semibold | 10 |
| ✕ (fermer) | Segoe UI | 10 |
| Titre bande principale | Segoe UI Semibold | 15 |
| Sous-titre bande / badge droits | Segoe UI | 9 |
| Titre de carte | Segoe UI Semibold | 9 |
| Description / détail de carte | Segoe UI | 8 |
| Badge de statut carte | Segoe UI Semibold | 8 |
| Boutons | Segoe UI Semibold | 9 |
| Computer ID | Consolas | 9 |
| Journal | Consolas | 9 |
| Messages d'erreur modale | Segoe UI | 8 |

## 3. Fenêtre principale — 720 × 690, sans bordure (`FormBorderStyle = None`)

Empilement (docks) : `list` (Fill) → `info` (Bottom, 36) → `tools` (Bottom, 56)
→ `st` (Bottom, 40) → `band` (Top, 76) → `tb` (Top, 32).

### 3.1 Barre de titre `tb` (32 px, Dock Top)
- Fond `tbBg`, logo accent 14×14 arrondi/plein à (10,9) ; titre à (30,6).
- Bouton ✕ 44×32 Dock Right : transparent au repos, `#D13438` + texte blanc au
  survol. Ferme la fenêtre.
- Glisser-déposer de la fenêtre sur toute la barre (handlers MouseDown/Move/Up).

### 3.2 Bande d'en-tête `band` (76 px, accent)
- Titre « Bentley PowerDraft – Modules Terra », Segoe UI Semibold 15, blanc, à (18,14).
- Sous-titre « Assistant d'installation et de configuration », accentSoft, à (18,41).
- Badge droits 150×26 ancré Top+Right : « Administrateur » / « Droits insuffisants »,
  texte blanc centré, fond accent.

### 3.3 Liste des 6 cartes `list` (Dock Fill)
- Flot top-down, `WrapContents=$false`, `AutoScroll`, padding (18,14,18,6) —
  largeur utile `contentWidth = 720 − 36 = 684`.
- Carte : 684 × 56, fond = couleur de l'état, margin bas 8.
  - **Icône ronde** 28×28 à (14,14) : peinte via `Paint` — cercle blanc rempli,
    contour 1,6 px couleur `étatInk`, glyphe centré : attente → numéro de la carte
    (Segoe UI Bold 9), en cours → `●` (U+25CF), terminé → `✓` (U+2713),
    échec → `✕` (U+2717).
  - **Titre** à (52,10) ink ; **description** 8 pt à (52,29) muted ; **détail**
    (message d'état) 8 pt à (52,43) pendInk.
  - **Badge** Segoe UI Semibold 8 à (`contentWidth − 86`, 21) : « En attente /
    En cours / Terminé / Échec » teinté `étatInk`.

### 3.4 Zone info `info` (36 px, masquée par défaut)
- Computer ID en Consolas 9 à (18,10) + bouton « Copier » 70×26 ancré à droite
  (clipboard + toast « Computer ID copié »).

### 3.5 Boutons `tools` (56 px)
Boutons 36 de haut, Segoe UI Semibold 9, à `y = 10` : Lancer l'installation
(190, `go`, blanc), Arrêter (90, `grey`, masqué par défaut), Réglages… (100,
`line`), Journal… (100, `line`), Réinitialiser (120, `line`, à droite).
- Bouton « line » : fond `win`, bordure 1 px `#CED4DA`, survol `#EEF1F3`.

### 3.6 Barre de statut `st` (40 px, `#EEF1F3`)
- Texte « Prêt à démarrer » Segoe UI 8 à (18,12).
- Jauge : piste 240×6 `#D5DADF` à (`contentWidth − 240`, 17) ; remplissage `go`
  largeur = `% étapes terminées × 240`.

## 4. Fenêtres flottantes (non modales, bordure None)

Position en cascade depuis la principale : Réglages `+40,+40` ; Journal `+60,+80`.
Chaque fenêtre a sa propre barre de titre (mêmes règles que 3.1).

### 4.1 Réglages — 560 × 640
- Corps `AutoScroll`, champs à `x=18`, largeur 420, TextBox 420×26, bouton
  « Parcourir… » 96×26 à `x+428` (dossier → FolderBrowserDialog, fichier →
  OpenFileDialog).
- Groupes : « Fichiers Terra » (dossier Terra, setup.exe, PTC_LAS.ptc),
  « Installation » (PowerDraft.exe, version, dossier TerraScan, case
  silencieuse), « Système » (Computer ID, bouton « Ouvrir Windows Security »).
- Titres de groupe en accent Segoe UI Semibold 9.
- Pied : « Annuler » 110 `line`, « Enregistrer » 120 `go` (enregistre + toast +
  ferme). Enregistré dans `%LOCALAPPDATA%\PowerDraftSetup\settings.json`.

### 4.2 Journal — 600 × 430, thème sombre
- RichTextBox `logBg`, Consolas 9, `logInk`, sans bordure, non éditable.
- Peinture incrémentale par ligne : `horodatage HH:mm:ss` en `logTm` + `[NIVEAU]`
  coloré (INFO `info`, OK `ok`, WARN `warn`, ERR `err`) + message en `logInk`,
  puis `ScrollToCaret`. (Pas de `DoEvents` à la fin : il figeait la fenêtre.)
- Barre basse 44 px `#15171A` : « Exporter… » 110×28 (SaveFileDialog .log/.txt,
  toast) et « Effacer » 90×28 (vide le tampon + le contrôle), fond `#1B1D21`,
  survol `#24272C`, bordure `#3A3E44`.
- Le handle du RichTextBox doit exister avant toute écriture : `CreateControl()`
  avant `Paint-Log` (sinon blocage).

## 5. Modales

### 5.1 Activation requise — 460 × 240
- Bande 54 accent (« Activation requise », Segoe UI Semibold 13, blanc).
- Champ mot de passe 420×26 à (20,94) ; espace message d'erreur à (20,126).
- Pied 56 : « Quitter » 110 `grey` à (214,12) ; « Activer » 110 `go` à (330,12).
- Entrée valide → `f.Tag='ok'` + fermeture ; invalide → message
  « Code d'activation incorrect… », le champ est re-sélectionné. statut de
  retour : `$f.Tag -eq 'ok'` (jamais de variable script écrite par un handler).
- Entrée → Activer ; Échap → Quitter.

### 5.2 Dossier Terra — 540 × 250
- Champ texte 390×26 à (20,94) pré-rempli `Cfg.TerraRoot` + « Parcourir… » 104×26.
- Validation : dossier vide → message ; introuvable → message ; sinon sauvegarde.
- Pied : « Plus tard » 110 `line` (retour False), « Continuer » 110 `go` (True).

## 6. Toast
- Auto-dimensionnée (`label.PreferredSize + 12`), fond `coal` texte blanc,
  centrée au-dessus du bas de la fenêtre principale (ou écran), fermeture
  automatique après **2 600 ms**.

## 7. États & icônes d'étape

| État | Fond carte | Icone | Glyphe | Badge |
|---|---|---|---|---|
| wait | `#F1F3F5` | contour `pendInk` | n° de la carte | En attente |
| run | `#FFF3CD` | contour `runInk` | `●` | En cours |
| ok | `#D1E7DD` | contour `okInk` | `✓` | Terminé |
| err | `#F8D7DA` | contour `errInk` | `✕` | Échec |

## 8. Règles de comportement / live coding
- **Closures** : les handlers qui touchent des variables `$script:` restent
  **sans** `GetNewClosure()` (accès live) ; pour des variables locales, la
  closure est conservée mais tout changement d'état script passe par une
  fonction (ex. `Save-Settings`, `Clear-LogBuffer`) ou par mutation d'objet
  partagé (ex. `$f.Tag`).
- `New-Object Type (a,b)` : toujours la forme `New-Object Type(a,b)` (l'espace
  avec 2 arguments ne lie pas `-ArgumentList`).
- Barre de titre : `Add-TitleBarDrag` + `Controls.Add($tb)` (titre ajouté en
  dernier pour être dockée en tête).