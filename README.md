# Tiroflan

App Mac de la barre des menus pour suivre les heures freelance (SwiftUI, macOS 14+, puce Apple).

Un chrono par client. Chaque séance terminée devient un événement « noté avec Tiroflan » dans l'agenda Google du client, avec un titre et un résumé rédigés par Claude Code d'après les conversations du créneau. Le décompte de la semaine se compare à un objectif d'heures.

## Installer sur un nouveau Mac

Cette section est écrite pour être suivie pas à pas, par une personne ou par son Claude Code. Les étapes marquées **(à la main)** demandent un mot de passe ou un clic dans une fenêtre système : Claude Code les explique, la personne les fait.

> **Le seul bon dépôt est `theodvd/tiroflan` (privé).** Le dépôt public `YMorice/tiroflan`, et le cask Homebrew « tiroflan » qui en vient, sont une autre app (un minuteur pomodoro en pixel art, `com.yann.tiroflan`) sans rapport avec celle-ci : ne jamais les installer. Si `git clone` répond « Repository not found », c'est que l'invitation GitHub n'est pas encore acceptée : s'arrêter et demander l'accès à Théo, ne pas chercher un autre dépôt.

### 0. Retirer l'app de Yann si elle est installée

```bash
ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" /Applications/Tiroflan.app/Contents/Info.plist 2>/dev/null)
echo "${ID:-aucune app Tiroflan}"   # com.yann.tiroflan = l'app de Yann ; com.theodavid.tiroflan = la bonne
if [ "$ID" = "com.yann.tiroflan" ]; then
  osascript -e 'quit app id "com.yann.tiroflan"' 2>/dev/null
  if brew list --cask 2>/dev/null | grep -qx tiroflan; then
    brew uninstall --cask tiroflan     # sans --zap
  else
    rm -rf /Applications/Tiroflan.app
  fi
fi
```

Ne jamais lancer `brew uninstall --zap tiroflan` : il efface tout `~/Library/Application Support/Tiroflan`, où vivent aussi les données de cette app-ci.

### 1. Prérequis

```bash
sw_vers -productVersion   # 14.0 ou plus
uname -m                  # doit répondre arm64 (Mac à puce Apple)
xcode-select -p           # sinon : xcode-select --install (outils de ligne de commande, pas Xcode complet)
claude --version          # Claude Code installé et connecté, pour les résumés de séance
```

### 2. Brancher son agenda Google sur le Mac (à la main)

Tiroflan ne se connecte pas à Google lui-même : il lit et écrit dans les agendas que le Calendrier de macOS connaît.

1. Réglages Système > Comptes internet > Ajouter un compte > Google.
2. Se connecter avec **sa propre adresse du client** (ex. `prenom@tamtam.ai`), cocher **Calendriers**.
3. Vérifier dans l'app Calendrier que l'agenda `prenom@tamtam.ai` apparaît.

Un compte Google perso peut être ajouté de la même façon : il recevra les séances du client « Perso ».

### 3. Récupérer le code et compiler

Le dépôt est privé : accepter d'abord l'invitation sur https://github.com/theodvd/tiroflan/invitations (si `git clone` demande une authentification : `gh auth login`).

```bash
cd ~/DEV                  # ou tout autre dossier de travail
git clone https://github.com/theodvd/tiroflan.git
cd tiroflan
./build.sh                # compile, installe dans /Applications et lance l'app
```

Un flan apparaît dans la barre des menus. L'app se lance seule à l'ouverture de session (réglable dans ses Réglages).

Contrôle : `/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" /Applications/Tiroflan.app/Contents/Info.plist` doit répondre `com.theodavid.tiroflan`. Le panneau montre un grand chrono, les totaux Auj. / Semaine / Mois et une grille d'activité ; s'il montre une flamme en pixel art, c'est l'app de Yann (retour à l'étape 0).

### 4. Autorisations (à la main)

- Au premier lancement, macOS demande l'**accès complet à l'agenda** : accepter. En cas de refus : Réglages Système > Confidentialité et sécurité > Calendriers > Tiroflan.
- Au premier clic sur ↻ (resynchro), macOS demande que Tiroflan puisse **contrôler Calendrier** : accepter.

### 5. Vérifier le réglage

Clic sur le flan > icône Réglages (curseurs) > client **Tamtam** :

- **Agenda** doit afficher `Auto · prenom@tamtam.ai`, avec **sa propre adresse**. Si ce n'est pas le cas (agenda d'un collègue, ou « aucun »), choisir le bon dans la liste.
- **Heures par semaine** : régler son objectif (boutons − et +).
- Le domaine `tamtam.ai` sert à reconnaître les rendez-vous du client : le laisser tel quel.

Test rapide : lancer le chrono sur Tamtam une minute, l'arrêter, valider la séance. Un événement « noté avec Tiroflan » doit apparaître dans son agenda `@tamtam.ai` (Google Agenda peut mettre quelques minutes à l'afficher).

### Sans compiler (zip de l'app)

Si la compilation échoue, une app déjà compilée peut être installée depuis un zip :

```bash
ditto -x -k ~/Downloads/Tiroflan-AAAA-MM-JJ.zip /Applications
xattr -dr com.apple.quarantine /Applications/Tiroflan.app   # app signée localement, pas par Apple
open /Applications/Tiroflan.app
```

Puis reprendre aux étapes 4 et 5. Un zip ne se met pas à jour : préférer la compilation dès que possible.

### Mettre à jour

Chrono arrêté (l'app est quittée puis relancée) :

```bash
cd ~/DEV/tiroflan && git pull && ./build.sh
```

macOS peut redemander l'accès à l'agenda après une compilation : c'est normal (voir Signature ci-dessous).

### Règles pour les autres Mac

- **Ne jamais pousser sur ce dépôt** (`git push`) : il appartient à Théo. Un bug ou une idée : le lui dire. Pour bricoler, travailler sur une branche locale.
- Les données restent sur le Mac (`~/Library/Application Support/Tiroflan/data.json`). Rien ne sort ailleurs que dans son propre agenda Google, et vers Claude Code (son abonnement) pour les résumés.

## Utiliser

- **Chrono** : choisir le client, lancer, arrêter. En fin de séance, Claude Code propose un titre et un résumé, à valider ou corriger.
- **Absences** : après 15 min sans activité, Tiroflan propose de retirer ce temps (la séance est coupée en deux blocs). Sans réponse, le temps reste compté.
- **Créneaux planifiés** : un événement de l'agenda du client dont le titre commence par le nom du client (ex. « tamtam »), sans invités, compte comme temps prévu dans le décompte de la semaine. La séance réelle le remplace.
- **L'agenda fait foi** : un bloc déplacé, raccourci ou supprimé dans Google Agenda met la séance à jour dans Tiroflan.

## Compiler

```bash
./build.sh               # compile, installe dans /Applications et relance
./build.sh --no-install  # compile seulement (build/Tiroflan.app)
```

## À savoir avant de modifier

- `build.sh` appelle `swiftc` directement : ne pas passer par `swift build` (le SwiftPM des Command Line Tools du Mac perso est cassé).
- Signature : certificat « Tiroflan Local Signing » s'il existe dans le trousseau, sinon ad hoc. En ad hoc, macOS redemande l'accès à l'agenda après chaque compilation. Pour l'éviter : Trousseaux d'accès > Assistant de certification > Créer un certificat, nom « Tiroflan Local Signing », type « Signature de code » (à la main).
- Ne pas relancer `build.sh` pendant un chrono en cours : l'app est quittée puis relancée.
- Données : `~/Library/Application Support/Tiroflan/data.json` (sauvegarde `data.backup.json` à chaque lancement).
- Choix de l'agenda d'un client : celui imposé dans les Réglages, sinon un agenda qui porte le nom du client, sinon l'agenda principal du compte de son domaine (`prenom@tamtam.ai`), sinon l'agenda par défaut (voir `Store.calendarID(for:)`).
- Synchro entre Mac : uniquement via les événements « noté avec Tiroflan » des agendas clients (voir `Store.syncFromCalendar`).
- Créneaux planifiés : un événement de l'agenda du client dont le titre commence par le nom du client (« tamtam »), sans invités et sans repère Tiroflan. En fin de chrono, ou à l'ajout d'une séance à la main, la séance réelle les remplace (voir `Store.replacePlannedSlots`).
- Objectif hebdo : « Heures par semaine » dans les réglages du client. Si une séance est plus courte que le créneau qu'elle remplace, Tiroflan propose d'allonger le prochain créneau de la semaine qui ne chevauche aucun événement (tous agendas visibles). Le manque est plafonné par ce qui reste à caser dans la semaine.
- Séance ajoutée à la main sans note : le résumé Claude est rédigé en arrière-plan d'après les conversations Claude Code du créneau.
- Résumés : le prompt nomme la personne par le prénom de la session macOS (`Summarizer.userFirstName`).
