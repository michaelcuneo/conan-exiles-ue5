# Conan Exiles Dedicated Server (Linux Native + SteamCMD + Docker)

Complete Docker setup for Conan Exiles dedicated server on Linux hosts using native Linux binaries and SteamCMD, with Portainer-friendly bind mounts and host networking.

## Features

- **SteamCMD install/update** on startup (Linux dedicated server build)
- **Native Linux runtime** (no Wine required)
- **Host networking** for game traffic and direct port control
- **Portainer-friendly bind mounts** under one backup root
- **First-run config generation** for `ServerSettings.ini`
- **Environment-driven configuration** with sane defaults

## Quick Start

### Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- At least 8GB RAM available for the container
- 50GB+ free disk space for game data

### 1) Build the image

```bash
docker compose build
```

### 2) Create host data directories

```bash
mkdir -p /srv/docker-data/conan-exiles/steamcmd
chown -R 1000:1000 /srv/docker-data/conan-exiles
```

### 3) Create `.env` from template (recommended)

```bash
cp .env.example .env
```

Edit `.env` and set at least:

- `CONAN_DATA_ROOT`
- `CONAN_ADMIN_PASSWORD`
- `CONAN_SERVER_NAME`

## Migrate Existing Saves (game.db)

- optional `CONAN_RCON_*`

### 4) Run the server

```bash
# Start in foreground (for testing)
docker compose up

# Start in background
docker compose up -d

# View logs
docker compose logs -f conan-exiles
```

### Universal setup checklist (works across most networks)

- Ensure host paths exist and are writable by UID 1000 (done in steps above)
- Open/forward these UDP ports to the Docker host: 7777, 7778, 27015
- If testing from LAN to your own public IP, enable NAT reflection/hairpin on your firewall (e.g., OPNsense/pfSense)
- If you’re behind multi-NIC/VPN or complex NAT, set a bind IP via MULTIHOME (see below)
- If Steam/Funcom services are having outages, use the outage fallback (-NOSTEAM) to play locally/direct (see below)

### 5) Stop the server

```bash
docker compose down

# Data is in bind mounts; remove host folders manually only if you intend to wipe data
```

## Configuration

Use `.env` (or Portainer environment variables) to customize settings:

```yaml
environment:
  - CONAN_SERVER_PORT=7777
  - CONAN_RAW_UDP_PORT=7778
  - CONAN_QUERY_PORT=27015
  - CONAN_SERVER_NAME=Conan Exiles Server
  - CONAN_MAX_PLAYERS=40
  - CONAN_REGION=0
  - CONAN_ADMIN_PASSWORD=replace-me
  - CONAN_SERVER_PASSWORD=
  - CONAN_RCON_ENABLED=false
  - CONAN_RCON_PORT=25575
  - CONAN_RCON_PASSWORD=
  - CONAN_DISABLE_BATTLEYE=true
  - CONAN_FORCE_NOSTEAM=false
  - CONAN_STEAM_APP_ID=443030
  - CONAN_UPDATE_ON_START=true
  - CONAN_VALIDATE_ON_START=false
  - STEAMCMD_LOGIN=anonymous
  - STEAMCMD_PASSWORD=
  - CONAN_EXTRA_ARGS=
```

## Ports

The server uses the following ports:

- `7777/UDP` - Main game traffic
- `7778/UDP` - Raw sockets / advertise
- `27015/UDP` - Steam query
- `25575/TCP` - RCON (if enabled)

This stack uses `network_mode: host`, so Docker does not publish ports.
The server binds directly to the host network.

Ensure these ports are open in the host firewall and any upstream router/firewall rules.

If you use `ufw` on the Docker host, optional allow rules are:

```bash
sudo ufw allow 7777/udp
sudo ufw allow 7778/udp
sudo ufw allow 27015/udp
sudo ufw allow 25575/tcp
```

If your server is behind OPNsense/pfSense (or another edge firewall), configure NAT/firewall there and keep host firewall rules minimal.

RCON values are applied into `ServerSettings.ini` by `entrypoint.sh`. Use `CONAN_EXTRA_ARGS` for advanced launch flags.

### "Authentication Failed" when joining

If the server lists correctly but clients fail to join with **Authentication Failed**, common causes are BattlEye and transient Steam backend issues.

- This image now defaults to `CONAN_DISABLE_BATTLEYE=true` (adds `-NoBattlEye`).
- If your existing `.env` was created earlier, add/update:

```env
CONAN_DISABLE_BATTLEYE=true
```

- Recreate the container:

```bash
docker compose up -d --force-recreate
```

If Steam backend is down or unstable, temporarily set:

```env
CONAN_FORCE_NOSTEAM=true
```

This enables direct-connect mode and bypasses Steam auth. For normal Steam listing/connectivity, keep `CONAN_FORCE_NOSTEAM=false`.

### NAT/Advertising behind OPNsense/pfSense (MULTIHOME)

If the server runs but doesn’t appear in the browser or favorites, bind it to the correct LAN interface and forward ports properly:

- Set `CONAN_EXTRA_ARGS` to include `-MULTIHOME=<LAN_IP>` of the Docker host (the destination of your OPNsense port forwards). Example:
  ```env
  CONAN_EXTRA_ARGS=-MULTIHOME=192.168.1.10
  ```
- In OPNsense/pfSense, create UDP port forwards from WAN to the Docker host for 7777, 7778, and 27015 (and TCP 25575 if RCON enabled). Ensure matching firewall rules are created.
- If testing from inside LAN using public IP, enable NAT reflection/hairpin on the firewall or test from a true external network.

Verify on the Docker host:

```bash
ss -lupn | grep -E ':7777|:7778|:27015'
```

You should see listeners on those ports (commonly 0.0.0.0:PORT or bound to your LAN IP when MULTIHOME is set).

### Outage fallback (no Steam backend)

If Steam backend services are flaky and the server won’t list or Steam API won’t initialize, you can still play by disabling Steam for the session:

1. In `.env` set: `CONAN_EXTRA_ARGS=-NOSTEAM`
2. Restart: `docker compose up -d --force-recreate`
3. Connect directly by IP/port (it will not appear in the public list):

- LAN: `192.168.1.x:7777`
- WAN: `your_public_ip:7777` (requires port forwards)

4. When services recover, clear `CONAN_EXTRA_ARGS` and restart to restore Steam listing.

### Auto-configured Engine.ini (Steam listing)

On first start (and every boot), this stack ensures the following in:
`${CONAN_DATA_ROOT}/steamcmd/conan-dedicated/ConanSandbox/Saved/Config/LinuxServer/Engine.ini`

- `[OnlineSubsystem]`
  - `DefaultPlatformService=Steam`
  - `bUseBuildIdOverride`/`BuildIdOverride` (only set if env `CONAN_BUILD_ID_OVERRIDE` is provided; otherwise disabled)
  - `ServerName` (from `CONAN_SERVER_NAME`)
- `[OnlineSubsystemSteam]`
  - `bEnabled=true`
  - `SteamDevAppId` (from `CONAN_STEAM_APP_ID`, defaults to `443030`)
  - `ServerQueryPort` (from `CONAN_QUERY_PORT`)
  - `ServerPort` (from `CONAN_SERVER_PORT`)

This mirrors the behavior many legacy images required for Steam server browser visibility so you don’t need to edit Engine.ini manually.

## Validate server files (SteamCMD)

If you suspect missing/corrupt files, run a one-off validation against the install directory (bind-mounted):

```bash
docker compose stop conan-exiles
docker compose run --rm --no-deps --entrypoint /home/steam/steamcmd/steamcmd.sh conan-exiles \
  +@sSteamCmdForcePlatformType linux \
  +force_install_dir /home/steam/steamcmd/conan-dedicated \
  +login anonymous \
  +app_update 443030 validate \
  +quit
docker compose up -d
```

## Troubleshooting (works across setups)

- Confirm listeners: `ss -lupn | grep -E ':7777|:7778|:27015'`
- Direct connect (bypasses listing): LAN `192.168.1.x:7777`, WAN `your_public_ip:7777`
- If joining from LAN to your public IP, enable NAT reflection/hairpin
- If Steam API fails to initialize, try outage fallback (`-NOSTEAM`) until services recover
- If clients get **Authentication Failed**, set `CONAN_DISABLE_BATTLEYE=true` and `CONAN_FORCE_NOSTEAM=true`, then recreate
- Validate files (section above)
- No mods? Ensure `ConanSandbox/Mods/modlist.txt` doesn’t exist or matches clients
- Password issues: ensure `ServerPassword=` line is present and empty in `ServerSettings.ini`

## Data Persistence

This stack uses bind mounts so Portainer and host backup jobs can back up directly from disk.

Set `CONAN_DATA_ROOT` (default: `/srv/docker-data/conan-exiles`) and the stack maps:

- `${CONAN_DATA_ROOT}/steamcmd` - SteamCMD + server installation files

`ConanSandbox/Saved` (including `ServerSettings.ini`) is persisted under:

- `${CONAN_DATA_ROOT}/steamcmd/conan-dedicated/ConanSandbox/Saved`

Create paths on the Docker host before deployment:

```bash
mkdir -p /srv/docker-data/conan-exiles/steamcmd
chown -R 1000:1000 /srv/docker-data/conan-exiles
```

## Migrate Existing Saves (game.db)

Bring your old world (players/builds) into this stack by copying your previous database.

Where to find your old saves

- Portainer-managed volume (common): `/var/lib/docker/volumes/<volume>/_data/ConanSandbox/Saved`
  - Example: `/var/lib/docker/volumes/conanexiles/_data/ConanSandbox/Saved`
  - Discover automatically (root required):
    ```bash
    sudo find /var/lib/docker/volumes -maxdepth 6 -type f \( -name game_0.db -o -name game.db \) -print
    ```
- Previous bind-mount layout: `<OLD_ROOT>/steamcmd/conan-dedicated/ConanSandbox/Saved`

Destination (this stack)

- `${CONAN_DATA_ROOT}/steamcmd/conan-dedicated/ConanSandbox/Saved`

Stop, copy, start (auto-pick newest DB)

```bash
# 1) Stop this server
docker compose stop

# 2) Set paths
OLD_SAVED="/var/lib/docker/volumes/conanexiles/_data/ConanSandbox/Saved"   # change if different
NEW_SAVED="${CONAN_DATA_ROOT}/steamcmd/conan-dedicated/ConanSandbox/Saved"

# 3) Auto-pick the newest DB (prefers UE5 game_0.db if newer), back up target, copy triad, fix ownership
db=$(for b in game_0.db game.db; do [ -f "$OLD_SAVED/$b" ] && echo "$(stat -c '%Y' "$OLD_SAVED/$b") $b"; done | sort -nr | awk 'NR==1{print $2}'); \
[ -n "$db" ] && { \
  [ -f "$NEW_SAVED/$db" ] && cp -a "$NEW_SAVED/$db" "$NEW_SAVED/$db.pre-migrate-$(date +%Y%m%d-%H%M%S).bak"; \
  for s in "" -shm -wal; do [ -f "$OLD_SAVED/${db}${s}" ] && sudo cp -a "$OLD_SAVED/${db}${s}" "$NEW_SAVED/"; done; \
  sudo chown 1000:1000 "$NEW_SAVED/$db"* 2>/dev/null || true; \
  ls -la "$NEW_SAVED/$db"* 2>/dev/null || true; \
} || echo "No game.db or game_0.db found under $OLD_SAVED"

# 4) Start the server and verify
docker compose up -d
docker compose logs --tail 120 conan-exiles
ss -lupn | grep -E ':7777|:7778|:27015' || true
```

Notes

- UE5 typically uses `game_0.db`; older installs may use `game.db`. The one-liner copies the newest one it finds and its sidecars (`*.db-shm`, `*.db-wal`).
- Keep your source data intact until you confirm the world loads correctly.

## Portainer Usage

1. In Portainer, create a new stack from this repo (or paste `docker-compose.yml`).
2. Add/override environment variables from `.env.example` in the stack UI.
3. Ensure host paths under `CONAN_DATA_ROOT` exist and are writable by UID `1000`.
4. Deploy stack.

## Advanced Usage

### Server config file location

Generated/managed config file:

`/home/steam/steamcmd/conan-dedicated/ConanSandbox/Saved/Config/LinuxServer/ServerSettings.ini`

When using default bind mounts, that maps to:

`${CONAN_DATA_ROOT}/steamcmd/conan-dedicated/ConanSandbox/Saved/Config/LinuxServer/ServerSettings.ini`

### Performance Tuning

Allocate more resources:

```yaml
deploy:
  resources:
    limits:
      cpus: "4"
      memory: 8G
    reservations:
      cpus: "2"
      memory: 4G
```

### Running Multiple Servers

Create separate compose files for different server instances:

```bash
docker compose -f docker-compose.server1.yml up -d
docker compose -f docker-compose.server2.yml up -d
```

## Monitoring

### Check Server Status

```bash
docker compose ps
docker compose exec conan-exiles ps aux
```

### View Logs

```bash
# Real-time logs
docker compose logs -f conan-exiles

# Last 100 lines
docker compose logs --tail 100 conan-exiles
```

### Health Check

```bash
docker compose ps
```

## Troubleshooting

### Server Won't Start

1. Check logs: `docker compose logs conan-exiles`
2. Verify ports aren't in use: `ss -lupn | grep 7777`
3. Ensure sufficient disk space: `df -h`

### Connection Issues

1. Verify listeners: `ss -lupn | grep -E '7777|7778|27015'` and `ss -ltpn | grep 25575`
2. Check host firewall rules
3. Confirm port forwarding on your router (if remote)

### Out of Memory

Increase allocated memory in `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      memory: 12G
```

## Best Practices

- Always back up your data before updating
- Use strong admin passwords
- Monitor resource usage regularly
- Keep Docker and images updated
- Run regular server restarts for stability
- Keep `CONAN_VALIDATE_ON_START=false` for faster normal boots
- Turn `CONAN_VALIDATE_ON_START=true` only for troubleshooting/corruption checks

## License

This Docker configuration is provided as-is. Conan Exiles is owned by Funcom.

## Included Files

- `Dockerfile` - Ubuntu 24.04 + native Linux runtime image
- `docker-compose.yml` - host networking + bind mounts
- `entrypoint.sh` - SteamCMD update, first-run config, native Linux launch
- `.env.example` - complete environment template
