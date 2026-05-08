# Conan Exiles UE5 Server Container (Native Linux runtime)
# Installs and runs Conan Exiles dedicated server via SteamCMD

FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    curl \
    wget \
    procps \
    libc6-i386 \
    lib32gcc-s1 \
    lib32stdc++6 \
    libstdc++6 \
    libgcc-s1 \
    libssl3 \
    tini \
    && rm -rf /var/lib/apt/lists/*

# Create directories and assign to UID/GID 1000
RUN mkdir -p /home/steam/steamcmd && \
    mkdir -p /opt/conan-exiles && \
    chown -R 1000:1000 /home/steam /opt/conan-exiles

WORKDIR /opt/conan-exiles

# Download and set up SteamCMD
RUN wget -q "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" -O /tmp/steamcmd.tar.gz && \
    tar -xzf /tmp/steamcmd.tar.gz -C /home/steam/steamcmd && \
    rm /tmp/steamcmd.tar.gz && \
    chown -R 1000:1000 /home/steam/steamcmd

ENV CONAN_SERVER_PORT=7777 \
    CONAN_RAW_UDP_PORT=7778 \
    CONAN_QUERY_PORT=27015 \
    CONAN_MAX_PLAYERS=70 \
    CONAN_SERVER_NAME="Conan Exiles Server" \
    CONAN_ADMIN_PASSWORD=admin \
    CONAN_SERVER_PASSWORD="" \
    CONAN_RCON_ENABLED=false \
    CONAN_RCON_PORT=25575 \
    CONAN_DISABLE_BATTLEYE=true \
    CONAN_FORCE_NOSTEAM=false \
    CONAN_STEAM_APP_ID=443030 \
    CONAN_STEAMCMD_PLATFORM=linux

# Expose ports
EXPOSE 7777/udp 7778/udp 27015/udp 25575/tcp

USER 1000:1000

# Create entrypoint script
COPY --chown=1000:1000 entrypoint.sh /opt/conan-exiles/entrypoint.sh
RUN chmod +x /opt/conan-exiles/entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/conan-exiles/entrypoint.sh"]
