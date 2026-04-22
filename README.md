# Vintage Story Server Docker

Generic Docker image for running a Vintage Story dedicated server on Linux `amd64`, with official server archive download at runtime, automatic `serverconfig.json` bootstrapping, and publishing support for both GitHub Container Registry and Docker Hub.

## Design choices

- Base image: `mcr.microsoft.com/dotnet/runtime:8.0-bookworm-slim`, matching the official `.NET Runtime 8.0` requirement for `1.21.6`.
- Target architecture: `amd64` only. The verified stable Linux server archive is `vs_server_linux-x64_1.21.6.tar.gz`. ARM64 remains officially documented as experimental.
- No game binaries are embedded in the published image. The image only contains the launcher logic and downloads the official Vintage Story server archive on first start.
- The container runs the server in the foreground. The bundled upstream `server.sh` script is designed for a traditional host setup with `screen` and `pgrep`, not for a container-native runtime.
- The server process does not run as root. The entrypoint starts as root only long enough to align `PUID` and `PGID`, create persistent directories, fix permissions, and immediately re-exec as the dedicated `vintagestory` user.
- No automatic server binary updates are performed. Once a server version is installed, it remains pinned until `VS_FORCE_REINSTALL=true` is explicitly set.
- The base .NET runtime is configurable through `DOTNET_RUNTIME_TAG`. The current default is `8.0-bookworm-slim`.

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
      VS_VERSION: 1.21.6
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

This does not auto-upgrade the installed Vintage Story server binaries by itself. The container image may be updated, but the game server already present in `storage/server` stays pinned unless you explicitly force a reinstall.

For a public server protected by a password and without any post-deployment console command, set these values in the environment:

```yaml
VS_ADVERTISE_SERVER: "true"
VS_PASSWORD: "change-me"
VS_WHITELIST_MODE: "off"
```

`VS_ADVERTISE_SERVER` publishes the server to the master server list. `VS_PASSWORD` protects access. `VS_WHITELIST_MODE=off` disables the dedicated-server default whitelist mode introduced in `1.20`.

## Main environment variables

- `VS_DOWNLOAD_URL`: preferred option. Paste the official Linux server download URL copied from the Vintage Story account page.
- `VS_VERSION`: stable version used to build the CDN URL when `VS_DOWNLOAD_URL` is not set. If empty, the project falls back to `.vintagestory-version`.
- `DOTNET_RUNTIME_TAG`: .NET runtime base image tag. Current default: `8.0-bookworm-slim`. Planned `1.22` validation target: `10.0-bookworm-slim`.
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
- `VS_FORCE_REINSTALL`: manual reinstallation guard. Default: `false`. When `false`, an already installed server binary is never replaced, even if `VS_VERSION` or `VS_DOWNLOAD_URL` changes.

## Bootstrap behavior

On first startup, the container:

1. downloads the official server archive if needed
2. extracts it into `storage/server`
3. starts once to generate `storage/data/serverconfig.json`
4. applies the current environment settings
5. forces `ModPaths` to include both `Mods` and `storage/data/Mods`
6. restarts the server in the foreground

On an already initialized environment, the container strictly reuses the existing contents of `storage/server`. A changed version in the environment does nothing unless `VS_FORCE_REINSTALL=true` is explicitly set.

`VS_FORCE_REINSTALL=true` exists for explicit operational cases only:

- upgrade the installed game server version on purpose
- reinstall the server files cleanly after changing `VS_VERSION` or `VS_DOWNLOAD_URL`
- recover from a broken or incomplete installation in `storage/server`

It is intentionally not part of the simple deployment example, because normal operation should keep the installed game server pinned.

## Version policy

- Initial install order: `VS_DOWNLOAD_URL`, then `VS_VERSION`, then the pinned stable version in `.vintagestory-version`
- Existing environment: never auto-upgrades the server binary
- Intentional version switch: use a separate data directory or set `VS_FORCE_REINSTALL=true`

## Preparing for 1.22

Official state observed on April 9, 2026:

- The latest stable release is still `1.21.6`, published on December 13, 2025.
- The latest known unstable release is `1.22.0-rc.7`, published on April 3, 2026.
- The official `v1.22` page states that Vintage Story requires `.NET 10` starting with `1.22`.
- Direct inspection of the official archive `vs_server_linux-x64_1.22.0-pre.5.tar.gz` shows `tfm: net10.0` and `Microsoft.NETCore.App 10.0.0`.
- The Linux server packaging remains broadly similar between `1.21.6` and `1.22.0-pre.5`: `x86_64` ELF executable, nearly identical archive structure, and no visible break in bundled native libraries.

Implications for this repository:

- The default image remains on `.NET 8` as long as `VS_VERSION=1.21.6`.
- A future `1.22` validation image should switch to `DOTNET_RUNTIME_TAG=10.0-bookworm-slim`.
- Although the official announcement mentions "Desktop Runtime", the inspected Linux server archive references `Microsoft.NETCore.App`, so the planned server image target remains `mcr.microsoft.com/dotnet/runtime`, not a desktop runtime image.
- The `1.22` pre-releases are explicitly discouraged for important save data. The correct upgrade strategy remains isolated validation, separate persistent data, and a manual cutover.

Server-relevant changes mentioned in the official `1.22` notes:

- `1.22.0-pre.4`: reduced CPU cost for chunk unpacking, packet creation, and related work, mainly affecting multiplayer servers
- `1.22.0-pre.4`: lag spike fixes around crafting and handbook usage
- `1.22.0-pre.5`: fix for duplicated masterserver requests when public server advertising is enabled
- `1.22.0-rc.7`: extra logging when the server cannot save, and autosave retry changed to `2000ms` instead of `500ms`

Recommended future validation profile:

```bash
DOTNET_RUNTIME_TAG=10.0-bookworm-slim \
VS_VERSION=1.22.0 \
VS_FORCE_REINSTALL=true \
docker compose up -d --build
```

For safe validation, use a separate persistent directory or a separate copy of `storage/`.

## Updating the server

Normal restart without changing the installed version:

```bash
docker compose up -d
```

Explicit reinstall:

```bash
VS_FORCE_REINSTALL=true docker compose up -d
```

Explicit switch to another version:

```bash
VS_VERSION=1.21.6 VS_FORCE_REINSTALL=true docker compose up -d
```

Explicit switch to a specific official archive URL:

```bash
VS_DOWNLOAD_URL="https://cdn.vintagestory.at/gamefiles/stable/vs_server_linux-x64_1.21.6.tar.gz" VS_FORCE_REINSTALL=true docker compose up -d
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
