# Vintage Story Server Docker

Generic Docker image for running a Vintage Story dedicated server on Linux `amd64`, with official server archive download at runtime, automatic `serverconfig.json` bootstrapping, and publishing support for both GitHub Container Registry and Docker Hub.

## Design choices

- Base image: `debian:12-slim` with both `.NET Runtime 8.0` and `.NET Runtime 10.0` installed. The server binary selects the correct runtime at launch, so switching Vintage Story versions does not require a user-facing .NET setting.
- Target architecture: `amd64` only. The verified current stable Linux server archive is `vs_server_linux-x64_1.22.0.tar.gz`. ARM64 remains officially documented as experimental.
- No game binaries are embedded in the published image. The image only contains the launcher logic and downloads the official Vintage Story server archive on first start.
- The container runs the server in the foreground. The bundled upstream `server.sh` script is designed for a traditional host setup with `screen` and `pgrep`, not for a container-native runtime.
- The server process does not run as root. The entrypoint starts as root only long enough to align `PUID` and `PGID`, prepare persistent directories, install or switch the server binaries under `storage/server`, fix permissions, and re-exec as the dedicated `vintagestory` user.
- No background auto-update exists. The installed server changes only when `VS_VERSION` or `VS_DOWNLOAD_URL` changes. This replaces `storage/server` but leaves `storage/data` untouched.

## Official sources

- Dedicated server guide for Linux: <https://wiki.vintagestory.at/Guide:Dedicated_Server#Dedicated_server_on_Linux>
- Server configuration reference: <https://wiki.vintagestory.at/index.php/Server_Config/en>
- Terms of service: <https://www.vintagestory.at/tos.html>

## Persistent layout

```text
storage/
├── data/
│   ├── Logs/
│   ├── Mods/
│   ├── Saves/
│   └── serverconfig.json
└── server/
```

- `storage/server`: extracted official server files
- `storage/data`: world data, logs, mods, saves, and runtime configuration

## Local build and run

1. Adjust the environment variables if needed, especially `VS_DOWNLOAD_URL` or `VS_VERSION`.
2. Build and start the container:

```bash
docker compose up -d --build
```

3. Follow the logs:

```bash
docker compose logs -f
```

4. Attach to the server console:

```bash
docker attach vintagestory-server
```

5. Detach without stopping the container:

```text
Ctrl-p then Ctrl-q
```

## Docker Hub deployment example

For a remote server that should only pull a published image and never build locally, use a compose file like this:

```yaml
services:
  vintagestory:
    image: pyrr0/vintage-story-server:latest
    container_name: vintagestory-server
    restart: unless-stopped
    stop_grace_period: 45s
    environment:
      PUID: 1000
      PGID: 1000
      VS_VERSION: 1.22.0
      VS_SERVER_NAME: Vintage Story Docker Server
      VS_MAX_CLIENTS: 16
      VS_ADVERTISE_SERVER: "false"
      VS_VERIFY_PLAYER_AUTH: "true"
      VS_PASS_TIME_WHEN_EMPTY: "false"
      VS_ALLOW_PVP: "true"
      VS_ALLOW_FIRE_SPREAD: "true"
      VS_ALLOW_FALLING_BLOCKS: "true"
    ports:
      - "42420:42420/tcp"
      - "42420:42420/udp"
    volumes:
      - ./storage:/var/vintagestory
```

Update flow on the remote host:

```bash
docker compose pull
docker compose up -d
```

This does not perform background updates. The container image may be updated independently, but the game server under `storage/server` only changes when `VS_VERSION` or `VS_DOWNLOAD_URL` changes.

For a public server protected by a password and without any post-deployment console command, set these values in the environment:

```yaml
VS_ADVERTISE_SERVER: "true"
VS_PASSWORD: "change-me"
VS_WHITELIST_MODE: "off"
```

`VS_ADVERTISE_SERVER` publishes the server to the master server list. `VS_PASSWORD` protects access. `VS_WHITELIST_MODE=off` disables the dedicated-server default whitelist mode introduced in `1.20`.

## Main environment variables

- `VS_DOWNLOAD_URL`: preferred option. Paste the official Linux server download URL copied from the Vintage Story account page.
- `VS_VERSION`: stable version used to build the CDN URL when `VS_DOWNLOAD_URL` is not set. If empty, the project falls back to `.vintagestory-version`. Changing it replaces only `storage/server`.
- `VS_SERVER_NAME`: displayed server name.
- `VS_SERVER_DESCRIPTION`: public server description.
- `VS_SERVER_LANGUAGE`: server language.
- `VS_PORT`: internal listening port and published Docker port.
- `VS_MAX_CLIENTS`: maximum number of clients.
- `VS_ADVERTISE_SERVER`: whether the server should be listed publicly.
- `VS_WHITELIST_MODE`: whitelist behavior for dedicated servers. Supported values: `off`, `on`, `default`, `0`, `1`, `2`. For a public password-protected server, use `off`.
- `VS_VERIFY_PLAYER_AUTH`: whether Vintage Story account authentication is enforced.
- `VS_PASSWORD`: optional server password.
- `VS_WORLD_NAME`: world name when creating a fresh world.
- `VS_SAVE_FILE`: absolute path to a specific `.vcdbs` file if you want to force a given save file.

## Bootstrap behavior

On first startup, the container:

1. downloads the official server archive if needed
2. extracts it into `storage/server`
3. starts once to generate `storage/data/serverconfig.json`
4. applies the current environment settings
5. forces `ModPaths` to include both `Mods` and `storage/data/Mods`
6. restarts the server in the foreground

On an already initialized environment:

- if the requested source matches the installed source, the container reuses the existing contents of `storage/server`
- if `VS_VERSION` or `VS_DOWNLOAD_URL` changes, the container replaces `storage/server`
- `storage/data` is preserved, including saves, mods, logs, and `serverconfig.json`

## Version policy

- Initial install order: `VS_DOWNLOAD_URL`, then `VS_VERSION`, then the pinned stable version in `.vintagestory-version`
- Existing environment: no background auto-upgrade
- Intentional version switch: change `VS_VERSION` or `VS_DOWNLOAD_URL` and restart the container
- World data stays in `storage/data`; only the server binaries under `storage/server` are replaced

## 1.22 baseline

Official state observed on April 21, 2026:

- `1.22.0` is the current stable release.
- The official `v1.22` information page states that Vintage Story requires `.NET 10` starting with `1.22`.
- Direct inspection of the official stable archive `vs_server_linux-x64_1.22.0.tar.gz` shows `tfm: net10.0` and `Microsoft.NETCore.App 10.0.0`.
- The Linux server packaging remains broadly similar to `1.21.x`: `x86_64` ELF executable, `VintagestoryServer.runtimeconfig.json`, `server.sh`, `Lib/`, `assets/`, and `Mods/`.

Implications for this repository:

- The default pinned version on this `dev` branch is `1.22.0`.
- The image embeds both `.NET 8` and `.NET 10`, so `1.21.x` and `1.22.x` can be selected by changing only `VS_VERSION`.
- Although the official announcement mentions "Desktop Runtime", the inspected Linux server archive references `Microsoft.NETCore.App`, so the server image only needs the regular .NET runtime packages.
- A world upgrade from `1.21.6` to `1.22.0` keeps the `.vcdbs` save file in `storage/data/Saves`. The server binaries are replaced, then Vintage Story performs its own save migration logic on first launch.

Server-relevant changes highlighted by the official `1.22.0` notes:

- reduced heap pressure on multiplayer servers
- faster recipe matching with reduced memory usage
- less CPU cost for chunk unpacking and packet creation
- automatic block remapping on first run after a game version change
- master server heartbeat also works in standby mode
- fix for duplicated master server requests when public advertising is enabled
- fix for malformed welcome messages causing dedicated-server login crashes

## Updating the server

Normal restart without changing the requested version:

```bash
docker compose up -d
```

Switch to another stable version:

```bash
VS_VERSION=1.22.0 docker compose up -d
```

Switch by explicit official archive URL:

```bash
VS_DOWNLOAD_URL="https://cdn.vintagestory.at/gamefiles/stable/vs_server_linux-x64_1.22.0.tar.gz" docker compose up -d
```

## Networking

The official guide opens `42420/tcp` and `42420/udp`. The default `compose.yaml` publishes both protocols and follows `VS_PORT`.

## Publishing

The workflow `.github/workflows/docker-publish.yml` builds the image for `linux/amd64` and publishes it to `ghcr.io/<owner>/<repo>`. If both `DOCKERHUB_NAMESPACE` and `DOCKERHUB_TOKEN` are defined in GitHub Actions secrets, it also publishes to Docker Hub with the following tag mapping:

- `main` branch -> `latest`
- `dev` branch -> `dev`
- Git tags matching `v*` -> matching container tags

Old tags already present on Docker Hub are not deleted automatically by the workflow. They must be cleaned up manually if you want a stricter tag set.

This published image still does not contain the game binaries. The Vintage Story server archive is downloaded at runtime by design.
