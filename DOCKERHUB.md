# michaelcuneobusiness/conan-exiles-server

Conan Exiles Dedicated Server for Linux using Wine + SteamCMD, packaged for Docker.

- Image: docker.io/michaelcuneobusiness/conan-exiles-server:latest
- Host networking (UDP 7777, 7778, 27015; optional TCP 25575 for RCON)
- Persistent data via bind mounts (SteamCMD install + Wine prefix)
- First-run config generation and env-driven settings

Quick start (docker run)

```bash
# Create host data dirs
sudo mkdir -p /srv/docker-data/conan-exiles/{steamcmd,wine-prefix}
sudo chown -R 1000:1000 /srv/docker-data/conan-exiles

# Start the server (host networking)
# IMPORTANT: Adjust admin/server passwords before exposing to the internet
sudo docker run -d --name conan-exiles-server \
  --network host \
  -e CONAN_SERVER_PORT=7777 \
  -e CONAN_RAW_UDP_PORT=7778 \
  -e CONAN_QUERY_PORT=27015 \
  -e CONAN_SERVER_NAME="Conan Exiles Server" \
  -e CONAN_MAX_PLAYERS=40 \
  -e CONAN_REGION=0 \
  -e CONAN_ADMIN_PASSWORD=changeme \
  -e CONAN_SERVER_PASSWORD= \
  -e CONAN_RCON_ENABLED=false \
  -e CONAN_RCON_PORT=25575 \
  -e CONAN_RCON_PASSWORD= \
  -e CONAN_UPDATE_ON_START=true \
  -e CONAN_VALIDATE_ON_START=false \
  -e STEAMCMD_LOGIN=anonymous \
  -e STEAMCMD_PASSWORD= \
  -e CONAN_EXTRA_ARGS= \
  -v /srv/docker-data/conan-exiles/steamcmd:/home/steam/steamcmd \
  -v /srv/docker-data/conan-exiles/wine-prefix:/opt/conan-exiles/.wine \
  docker.io/michaelcuneobusiness/conan-exiles-server:latest
```

Compose example

```yaml
services:
  conan-exiles:
    image: michaelcuneobusiness/conan-exiles-server:latest
    build:
      context: .
      dockerfile: Dockerfile
    container_name: conan-exiles-server
    restart: unless-stopped
    network_mode: host
    environment:
      - CONAN_SERVER_PORT=7777
      - CONAN_RAW_UDP_PORT=7778
      - CONAN_QUERY_PORT=27015
      - CONAN_SERVER_NAME=Conan Exiles Server
      - CONAN_MAX_PLAYERS=40
      - CONAN_REGION=0
      - CONAN_ADMIN_PASSWORD=changeme
      - CONAN_SERVER_PASSWORD=
      - CONAN_RCON_ENABLED=false
      - CONAN_RCON_PORT=25575
      - CONAN_RCON_PASSWORD=
      - CONAN_UPDATE_ON_START=true
      - CONAN_VALIDATE_ON_START=false
      - STEAMCMD_LOGIN=anonymous
      - STEAMCMD_PASSWORD=
      - CONAN_EXTRA_ARGS=
    volumes:
      - type: bind
        source: /srv/docker-data/conan-exiles/steamcmd
        target: /home/steam/steamcmd
      - type: bind
        source: /srv/docker-data/conan-exiles/wine-prefix
        target: /opt/conan-exiles/.wine
```

Ports

- 7777/UDP - Game
- 7778/UDP - Raw UDP/Advertise
- 27015/UDP - Steam query
- 25575/TCP - RCON (optional)

Saves and migration

- Saves live under /home/steam/steamcmd/conan-dedicated/ConanSandbox/Saved in the container
- On the host (with the example), that maps to /srv/docker-data/conan-exiles/steamcmd/conan-dedicated/ConanSandbox/Saved
- UE5 typically uses game_0.db (plus -wal/-shm) as the active DB; older installs may use game.db
- To migrate, stop the container and copy your old DB files into the Saved path, fix ownership to UID 1000, and restart

Health

- A basic healthcheck looks for the ConanExilesServer.exe process
- Use `docker logs -f conan-exiles-server` for live logs

Notes

- Requires a Linux host with Docker Engine + host network support
- Keep admin/server passwords secure and change defaults before exposing publicly
