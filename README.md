# Tiroflan

App Mac de la barre des menus pour suivre les heures freelance (SwiftUI, macOS 14+, puce Apple).

## Compiler et installer

```bash
./build.sh               # compile, installe dans /Applications et relance
./build.sh --no-install  # compile seulement (build/Tiroflan.app)
```

## À savoir avant de modifier

- `build.sh` appelle `swiftc` directement : ne pas passer par `swift build` (le SwiftPM des Command Line Tools du Mac perso est cassé).
- Signature : certificat « Tiroflan Local Signing » s'il existe dans le trousseau, sinon ad hoc. En ad hoc, macOS redemande l'accès à l'agenda après chaque compilation.
- Ne pas relancer `build.sh` pendant un chrono en cours : l'app est quittée puis relancée.
- Données : `~/Library/Application Support/Tiroflan/data.json` (sauvegarde `data.backup.json` à chaque lancement).
- Synchro entre Mac : uniquement via les événements « noté avec Tiroflan » des agendas clients (voir `Store.syncFromCalendar`).
