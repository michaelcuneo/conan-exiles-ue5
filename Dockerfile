# Conan Exiles UE5 Server Container with Wine
# Installs and runs the Conan Exiles server via SteamCMD and Wine

FROM ubuntu:24.04

# Install 32-bit architecture support and dependencies
RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
    wine-stable \
    wine32 \
    wine64 \
    winetricks \
    xvfb \
    ca-certificates \
    tzdata \
    curl \
    wget \
    procps \
    lib32gcc-s1 \
    lib32stdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Create directories and assign to UID/GID 1000
RUN mkdir -p /home/steam/steamcmd && \
    mkdir -p /opt/conan-exiles && \
    mkdir -p /opt/conan-exiles/.wine && \
    chown -R 1000:1000 /home/steam /opt/conan-exiles

WORKDIR /opt/conan-exiles

# Download and set up SteamCMD
RUN wget -q "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" -O /tmp/steamcmd.tar.gz && \
    tar -xzf /tmp/steamcmd.tar.gz -C /home/steam/steamcmd && \
    rm /tmp/steamcmd.tar.gz && \
    chown -R 1000:1000 /home/steam/steamcmd

# Wine environment setup
ENV WINEARCH=win64 \
    WINEPREFIX=/opt/conan-exiles/.wine \
    DISPLAY=:99 \
    CONAN_SERVER_PORT=7777 \
    CONAN_RAW_UDP_PORT=7778 \
    CONAN_QUERY_PORT=27015 \
    CONAN_MAX_PLAYERS=70 \
    CONAN_SERVER_NAME="Conan Exiles Server" \
    CONAN_ADMIN_PASSWORD=admin \
    CONAN_SERVER_PASSWORD="" \
    CONAN_RCON_ENABLED=false \
    CONAN_RCON_PORT=25575

# Expose ports
EXPOSE 7777/udp 7778/udp 27015/udp 25575/tcp

USER 1000:1000

# Initialize Wine prefix
RUN DISPLAY=:99 wineboot --init 2>/dev/null || true

# Create entrypoint script
COPY --chown=1000:1000 entrypoint.sh /opt/conan-exiles/entrypoint.sh
RUN chmod +x /opt/conan-exiles/entrypoint.sh

ENTRYPOINT ["/opt/conan-exiles/entrypoint.sh"]
