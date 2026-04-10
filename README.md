# Vintage Story Server Docker

Image Docker générique pour exécuter un serveur Vintage Story sur Linux `amd64`, avec téléchargement de l’archive officielle au runtime, bootstrap automatique du `serverconfig.json` et publication possible sur GitHub Container Registry.

## Choix techniques

- Base Linux: `mcr.microsoft.com/dotnet/runtime:8.0-bookworm-slim`, alignée avec l’exigence officielle `.NET Runtime 8.0`.
- Cible `amd64` uniquement: l’archive officielle stable vérifiée est `vs_server_linux-x64_1.21.6.tar.gz`. Le support ARM64 reste documenté comme expérimental côté officiel.
- Aucun binaire du jeu n’est embarqué dans l’image publiée: l’image ne transporte que le lanceur, puis télécharge l’archive serveur officielle au premier démarrage. Cette approche garde le dépôt et l’image partageables sans republier les fichiers du jeu.
- Le conteneur exécute le serveur au premier plan. Le script `server.sh` fourni par le jeu repose sur `screen`, `pgrep` et un usage machine classique, pas sur un modèle conteneur natif.
- Le processus serveur ne tourne pas en root. L’entrypoint démarre en root uniquement pour aligner `PUID` et `PGID`, préparer les permissions, puis relance immédiatement le serveur sous l’utilisateur `vintagestory`.
- Aucune mise à jour automatique du binaire serveur n’est effectuée. Une installation existante reste figée tant que `VS_FORCE_REINSTALL=true` n’est pas demandé explicitement.
- La base runtime est paramétrable via `DOTNET_RUNTIME_TAG`. Valeur actuelle: `8.0-bookworm-slim`, adaptée à `1.21.6`.

## Sources officielles utilisées

- Guide serveur dédié Linux: <https://wiki.vintagestory.at/Guide:Dedicated_Server#Dedicated_server_on_Linux>
- Configuration serveur: <https://wiki.vintagestory.at/index.php/Server_Config/en>
- Conditions d’utilisation du service: <https://www.vintagestory.at/tos.html>

## Arborescence

```text
storage/
├── data/
│   ├── Logs/
│   ├── Mods/
│   ├── Saves/
│   └── serverconfig.json
└── server/
```

- `storage/server`: fichiers serveur extraits depuis l’archive officielle.
- `storage/data`: monde, logs, mods, sauvegardes et configuration persistants.

## Démarrage rapide

1. Ajuster les variables du projet si nécessaire, en priorité `VS_DOWNLOAD_URL` ou `VS_VERSION`.
2. Construire et lancer:

```bash
docker compose up -d --build
```

3. Suivre les logs:

```bash
docker compose logs -f
```

4. Ouvrir la console serveur:

```bash
docker attach vintagestory-server
```

5. Détacher la console sans arrêter le conteneur:

```text
Ctrl-p puis Ctrl-q
```

## Variables principales

- `VS_DOWNLOAD_URL`: URL officielle copiée depuis la page de téléchargement de votre compte Vintage Story. Option recommandée.
- `VS_VERSION`: version stable à utiliser si vous préférez reconstruire l’URL CDN automatiquement. Si vide, le projet utilise la version épinglée dans `.vintagestory-version`.
- `DOTNET_RUNTIME_TAG`: tag de l’image .NET utilisée pour construire le conteneur. Valeur actuelle `8.0-bookworm-slim`. Pour une future image de validation `1.22`, la cible prévue est `10.0-bookworm-slim`.
- `VS_SERVER_NAME`: nom affiché par le serveur.
- `VS_SERVER_DESCRIPTION`: description publique.
- `VS_SERVER_LANGUAGE`: langue des messages serveur.
- `VS_PORT`: port d’écoute interne et publié par Compose.
- `VS_MAX_CLIENTS`: nombre maximal de joueurs.
- `VS_ADVERTISE_SERVER`: publication dans la liste publique.
- `VS_VERIFY_PLAYER_AUTH`: vérification des comptes Vintage Story.
- `VS_PASSWORD`: mot de passe d’accès.
- `VS_WORLD_NAME`: nom du monde si un nouveau monde est créé.
- `VS_SAVE_FILE`: chemin absolu vers un fichier `.vcdbs` si vous voulez forcer une sauvegarde spécifique.
- `VS_FORCE_REINSTALL`: garde-fou de mise à jour. Par défaut `false`. Tant qu’il reste à `false`, un serveur déjà installé n’est jamais remplacé, même si `VS_VERSION` ou `VS_DOWNLOAD_URL` changent.

## Bootstrap et configuration

Au premier lancement, le conteneur:

1. télécharge l’archive officielle si nécessaire ;
2. extrait le serveur dans `storage/server` ;
3. démarre une première fois pour générer `storage/data/serverconfig.json` ;
4. injecte les paramètres d’environnement courants ;
5. force `ModPaths` à inclure `Mods` et `storage/data/Mods` ;
6. redémarre ensuite le serveur au premier plan.

Sur un environnement déjà initialisé, le conteneur réutilise strictement les fichiers présents dans `storage/server`. Un changement de version demandé dans l’environnement n’écrase rien tant que `VS_FORCE_REINSTALL=true` n’est pas positionné.

## Politique de version

- Installation initiale: prend `VS_DOWNLOAD_URL` si renseigné, sinon `VS_VERSION`, sinon la version stable épinglée dans `.vintagestory-version`.
- Environnement existant: ne change jamais de binaire automatiquement.
- Changement volontaire: passe par un autre volume `storage/` ou par `VS_FORCE_REINSTALL=true`.

## Préparation 1.22

État officiel constaté au 9 avril 2026:

- La dernière stable reste `1.21.6`, publiée le 13 décembre 2025.
- La dernière instable connue est `1.22.0-rc.7`, publiée le 3 avril 2026.
- La page officielle `v1.22` annonce qu’à partir de `1.22`, Vintage Story requiert `.NET 10`.
- Vérification directe de l’archive officielle `vs_server_linux-x64_1.22.0-pre.5.tar.gz`: le serveur Linux cible `tfm: net10.0` et `Microsoft.NETCore.App 10.0.0`.
- Le packaging serveur Linux reste globalement le même entre `1.21.6` et `1.22.0-pre.5`: exécutable ELF `x86_64`, structure d’archive quasi identique, pas de rupture visible dans les bibliothèques natives embarquées.

Conséquences pour ce dépôt:

- L’image par défaut reste volontairement sur `.NET 8` tant que `VS_VERSION=1.21.6`.
- Une future image de validation `1.22` devra utiliser `DOTNET_RUNTIME_TAG=10.0-bookworm-slim`.
- Le texte officiel parle de "Desktop Runtime", mais l’archive serveur Linux inspectée référence `Microsoft.NETCore.App`. Pour l’image serveur Docker, la cible prévue reste donc l’image `mcr.microsoft.com/dotnet/runtime`, pas une image desktop spécifique.
- Les préversions `1.22` sont explicitement déconseillées sur des sauvegardes importantes. La stratégie correcte reste donc celle déjà retenue ici: environnement séparé, volume de données séparé, validation manuelle, puis bascule contrôlée.

Points serveurs vus dans les notes 1.22 officielles:

- `1.22.0-pre.4`: réduction du coût CPU sur décompactage de chunks, création de paquets et autres traitements, annoncé comme bénéfique surtout aux serveurs multijoueur.
- `1.22.0-pre.4`: corrections de pics de lag lors du craft et du handbook.
- `1.22.0-pre.5`: correction d’un bug où l’annonce publique du serveur pouvait envoyer plusieurs requêtes dupliquées au masterserver.
- `1.22.0-rc.7`: journalisation supplémentaire quand le serveur n’arrive pas à sauvegarder, et nouvel intervalle de retry d’autosave à 2000 ms au lieu de 500 ms.

Profil de migration recommandé pour plus tard:

```bash
DOTNET_RUNTIME_TAG=10.0-bookworm-slim \
VS_VERSION=1.22.0 \
VS_FORCE_REINSTALL=true \
docker compose up -d --build
```

Pour une validation sans risque, utiliser un autre répertoire de persistance ou une autre copie de `storage/`.

## Mise à jour du serveur

Redémarrage normal sans changement de version:

```bash
docker compose up -d
```

Commande de réinstallation explicite:

```bash
VS_FORCE_REINSTALL=true docker compose up -d
```

Commande de bascule explicite vers une autre version:

```bash
VS_VERSION=1.21.6 VS_FORCE_REINSTALL=true docker compose up -d
```

Commande de bascule explicite vers une URL officielle spécifique:

```bash
VS_DOWNLOAD_URL="https://cdn.vintagestory.at/gamefiles/stable/vs_server_linux-x64_1.21.6.tar.gz" VS_FORCE_REINSTALL=true docker compose up -d
```

## Réseau

Le guide officiel ouvre `42420/tcp` et `42420/udp`. Le `compose.yaml` publie les deux protocoles et suit automatiquement `VS_PORT`.

## GitHub

Le workflow `.github/workflows/docker-publish.yml` construit l’image en `linux/amd64` et la publie sur `ghcr.io/<owner>/<repo>` sur chaque push vers `main` et sur les tags `v*`.

Cette image GitHub ne contient pas les binaires Vintage Story. Le téléchargement reste effectué au runtime, côté utilisateur.
