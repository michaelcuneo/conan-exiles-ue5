#!/bin/bash
set -Eeuo pipefail

echo "=== Conan Exiles Server Startup (Linux native) ==="

STEAMCMD_DIR="/home/steam/steamcmd"
STEAMCMD_SH="${STEAMCMD_DIR}/steamcmd.sh"
SERVER_DIR="${STEAMCMD_DIR}/conan-dedicated"
CONFIG_DIR="${SERVER_DIR}/ConanSandbox/Saved/Config/LinuxServer"
SETTINGS_FILE="${CONFIG_DIR}/ServerSettings.ini"
ENGINE_FILE="${CONFIG_DIR}/Engine.ini"
GAME_FILE="${CONFIG_DIR}/Game.ini"
APP_ID="${CONAN_STEAM_APP_ID:-443030}"
STEAM_HOME="/home/ubuntu"

set_ini_value() {
    local key="$1"
    local value="$2"

    if grep -qiE "^${key}=" "${SETTINGS_FILE}"; then
        sed -i -E "s|^${key}=.*$|${key}=${value}|I" "${SETTINGS_FILE}"
    else
        printf "%s=%s\n" "${key}" "${value}" >> "${SETTINGS_FILE}"
    fi
}

write_default_settings_if_missing() {
    mkdir -p "${CONFIG_DIR}"

    if [[ ! -f "${SETTINGS_FILE}" ]]; then
        cat > "${SETTINGS_FILE}" <<'EOF'
[ServerSettings]
ServerName=Conan Exiles Server
MaxPlayers=40
ServerRegion=0
PVPEnabled=true
CanDamagePlayerOwnedStructures=true
AdminPassword=
ServerPassword=
EnablePVP=true
EnableAntiCheat=False
EOF
    fi

    if [[ ! -f "${ENGINE_FILE}" ]]; then
        cat > "${ENGINE_FILE}" <<'EOF'
[OnlineSubsystem]
DefaultPlatformService=Steam

[OnlineSubsystemSteam]
bEnabled=true
SteamDevAppId=443030
GameServerQueryPort=27015
EOF
    fi
}

write_engine_ini() {
    mkdir -p "${CONFIG_DIR}"

    cat > "${ENGINE_FILE}" <<EOF
[OnlineSubsystem]
ServerName=${CONAN_SERVER_NAME:-Conan Exiles Server}
EOF

    rm -f "${GAME_FILE}" || true
}

prepare_steam_runtime() {
    local steamclient_src="${SERVER_DIR}/linux64/steamclient.so"

    if [[ ! -f "${steamclient_src}" ]]; then
        steamclient_src="${STEAMCMD_DIR}/linux64/steamclient.so"
    fi

    if [[ ! -f "${steamclient_src}" ]]; then
        echo "[error] steamclient.so not found in expected locations"
        exit 1
    fi

    mkdir -p \
        "${STEAM_HOME}/.steam/sdk64" \
        "${STEAM_HOME}/.steam/root/sdk64" \
        "${STEAM_HOME}/.local/share/Steam/sdk64" \
        "${SERVER_DIR}/ConanSandbox/Binaries/Linux"

    ln -sf "${steamclient_src}" "${STEAM_HOME}/.steam/sdk64/steamclient.so"
    ln -sf "${steamclient_src}" "${STEAM_HOME}/.steam/root/sdk64/steamclient.so"
    ln -sf "${steamclient_src}" "${STEAM_HOME}/.local/share/Steam/sdk64/steamclient.so"
    printf "%s\n" "${APP_ID}" > "${SERVER_DIR}/ConanSandbox/Binaries/Linux/steam_appid.txt"
    printf "%s\n" "${APP_ID}" > "${SERVER_DIR}/steam_appid.txt"
}

update_server_settings() {
    set_ini_value "ServerName" "${CONAN_SERVER_NAME:-Conan Exiles Server}"
    set_ini_value "MaxPlayers" "${CONAN_MAX_PLAYERS:-40}"
    set_ini_value "ServerRegion" "${CONAN_REGION:-0}"
    set_ini_value "AdminPassword" "${CONAN_ADMIN_PASSWORD:-admin}"
    set_ini_value "ServerPassword" "${CONAN_SERVER_PASSWORD:-}"

    local rcon_enabled="${CONAN_RCON_ENABLED:-false}"
    if [[ "${rcon_enabled,,}" == "true" ]]; then
        set_ini_value "RconEnabled" "1"
        set_ini_value "RconPort" "${CONAN_RCON_PORT:-25575}"
        set_ini_value "RconPassword" "${CONAN_RCON_PASSWORD:-}"
    fi
}

install_or_update_server() {
    local login="${STEAMCMD_LOGIN:-anonymous}"
    local password="${STEAMCMD_PASSWORD:-}"
    local app_id="${APP_ID}"
    local platform="${CONAN_STEAMCMD_PLATFORM:-linux}"

    if [[ ! -x "${STEAMCMD_SH}" ]]; then
        echo "[error] SteamCMD not found at ${STEAMCMD_SH}"
        exit 1
    fi

    local update_cmd=("${STEAMCMD_SH}" "+@sSteamCmdForcePlatformType" "${platform}" "+force_install_dir" "${SERVER_DIR}" "+login" "${login}")
    if [[ -n "${password}" && "${login}" != "anonymous" ]]; then
        update_cmd+=("${password}")
    fi
    update_cmd+=("+app_update" "${app_id}")

    if [[ "${CONAN_VALIDATE_ON_START:-false}" == "true" ]]; then
        update_cmd+=("validate")
    fi
    update_cmd+=("+quit")

    if [[ "${CONAN_UPDATE_ON_START:-true}" == "true" || ! -x "${SERVER_DIR}/ConanSandbox/Binaries/Linux/ConanSandboxServer" ]]; then
        echo "Updating Conan dedicated server (platform=${platform}, app=${app_id})..."
        "${update_cmd[@]}"
    else
        echo "Skipping update (CONAN_UPDATE_ON_START=false)."
    fi
}

start_server_linux() {
    local server_bin=""
    local candidates=(
        "${SERVER_DIR}/ConanSandboxServer.sh"
        "${SERVER_DIR}/ConanSandbox/Binaries/Linux/ConanSandboxServer-Linux-Shipping"
        "${SERVER_DIR}/ConanSandbox/Binaries/Linux/ConanSandboxServer"
    )
    for candidate in "${candidates[@]}"; do
        if [[ -x "${candidate}" ]]; then
            server_bin="${candidate}"
            break
        fi
    done
    if [[ -z "${server_bin}" ]]; then
        echo "[error] Linux server binary not found in expected locations."
        exit 1
    fi

    local server_port="${CONAN_SERVER_PORT:-7777}"
    local raw_port="${CONAN_RAW_UDP_PORT:-7778}"
    local query_port="${CONAN_QUERY_PORT:-27015}"
    local map_name="${CONAN_MAP:-TheIsland}"

    local launch_args=("${map_name}" "-Port=${server_port}" "-QueryPort=${query_port}" "-RawSocketsPort=${raw_port}")

    if [[ "${CONAN_DISABLE_BATTLEYE:-true}" == "true" ]]; then
        launch_args+=("-NoBattlEye")
    fi
    if [[ "${CONAN_FORCE_NOSTEAM:-false}" == "true" ]]; then
        launch_args+=("-NOSTEAM")
    fi
    if [[ -n "${CONAN_EXTRA_ARGS:-}" ]]; then
        read -r -a extra_args <<< "${CONAN_EXTRA_ARGS}"
        launch_args+=("${extra_args[@]}")
    fi

    echo "Starting Linux server binary: ${server_bin}"
    echo "Launch args: ${launch_args[*]}"
    cd "$(dirname "${server_bin}")"
    exec "${server_bin}" "${launch_args[@]}"
}

export HOME="${STEAM_HOME}"
export USER="ubuntu"
export LD_LIBRARY_PATH="${SERVER_DIR}/linux64:${SERVER_DIR}/ConanSandbox/Binaries/Linux:${LD_LIBRARY_PATH:-}"

write_default_settings_if_missing
update_server_settings
write_engine_ini
install_or_update_server
prepare_steam_runtime
start_server_linux

set_ini_value() {
    local key="$1"
    local value="$2"

    if grep -qiE "^${key}=" "${SETTINGS_FILE}"; then
        sed -i -E "s|^${key}=.*$|${key}=${value}|I" "${SETTINGS_FILE}"
    else
        printf "%s=%s\n" "${key}" "${value}" >> "${SETTINGS_FILE}"
    fi
}

initialize_server_settings() {
    mkdir -p "${CONFIG_DIR}"

    if [[ ! -f "${SETTINGS_FILE}" ]]; then
        cat > "${SETTINGS_FILE}" <<'EOF'
[ServerSettings]
ServerName=Conan Exiles Server
MaxPlayers=40
ServerRegion=0
PVPEnabled=true
CanDamagePlayerOwnedStructures=true
AdminPassword=
ServerPassword=
EnablePVP=true
RconEnabled=False
RconPort=25575
RconPassword=
EOF
    fi

    set_ini_value "ServerName" "${CONAN_SERVER_NAME:-Conan Exiles Server}"
    set_ini_value "MaxPlayers" "${CONAN_MAX_PLAYERS:-40}"
    set_ini_value "ServerRegion" "${CONAN_REGION:-0}"
    set_ini_value "AdminPassword" "${CONAN_ADMIN_PASSWORD:-}"
    set_ini_value "ServerPassword" "${CONAN_SERVER_PASSWORD:-}"
    set_ini_value "RconEnabled" "${CONAN_RCON_ENABLED:-false}"
    set_ini_value "RconPort" "${CONAN_RCON_PORT:-25575}"
    set_ini_value "RconPassword" "${CONAN_RCON_PASSWORD:-}"
}

# Ensure Engine.ini contains Steam/advertising basics so servers show up without manual edits
ensure_engine_ini() {
    mkdir -p "${CONFIG_DIR}"
    touch "${ENGINE_FILE}"

    # Values (allow override via env if provided)
    local build_id="${CONAN_BUILD_ID_OVERRIDE:-}"
    local steam_app_id="${CONAN_STEAM_APP_ID:-443030}"
    local server_name_ini="${CONAN_SERVER_NAME:-Conan Exiles Server}"
    local qport="${CONAN_QUERY_PORT:-27015}"
    local gport="${CONAN_SERVER_PORT:-7777}"
    local use_build_override="False"
    local build_override_value="0"

    if [[ -n "${build_id}" ]]; then
        use_build_override="True"
        build_override_value="${build_id}"
    fi

    cp -f "${ENGINE_FILE}" "${ENGINE_FILE}.bak-$(date +%Y-%m-%d-%H%M%S)" 2>/dev/null || true

    local tmp
    tmp="${ENGINE_FILE}.tmp.$$"

    awk '
        BEGIN {
            skip = 0
            current = ""
        }
        /^[[]/ {
            low = tolower($0)
            if (low == "[onlinesubsystem]" || low == "[onlinesubsystemsteam]") {
                skip = 1
                current = ""
                next
            }
            skip = 0
            current = low
        }
        {
            if (skip) next

            if (current == "") {
                if ($0 ~ /^bUseBuildIdOverride=/) next
                if ($0 ~ /^BuildIdOverride=/) next
                if ($0 ~ /^DefaultPlatformService=/) next
                if ($0 ~ /^SteamDevAppId=/) next
                if ($0 ~ /^ServerQueryPort=/) next
                if ($0 ~ /^ServerPort=/) next
                if ($0 ~ /^GameServerPort=/) next
            }

            print
        }
    ' "${ENGINE_FILE}" > "${tmp}"

    cat >> "${tmp}" <<EOF

[OnlineSubsystem]
bUseBuildIdOverride=${use_build_override}
BuildIdOverride=${build_override_value}
ServerName=${server_name_ini}
DefaultPlatformService=Steam

[OnlineSubsystemSteam]
bEnabled=true
SteamDevAppId=${steam_app_id}
bUseSteamNetworking=false
ServerQueryPort=${qport}
ServerPort=${gport}
GameServerPort=${gport}
EOF

    mv -f "${tmp}" "${ENGINE_FILE}"
}

ensure_steam_runtime_files() {
    local server_exe_path="$1"
    local server_dirname
    server_dirname="$(dirname "${server_exe_path}")"

    local steam_app_id="${CONAN_STEAM_APP_ID:-443030}"
    local steam_api_src="${SERVER_DIR}/Engine/Binaries/ThirdParty/Steamworks/Steamv161/Win64/steam_api64.dll"
    local steamclient64_src="${SERVER_DIR}/steamclient64.dll"
    local steamclient_src="${SERVER_DIR}/steamclient.dll"
    local tier0_src="${SERVER_DIR}/tier0_s64.dll"
    local vstdlib_src="${SERVER_DIR}/vstdlib_s64.dll"

    copy_if_needed() {
        local src="$1"
        local dst="$2"
        if [[ -f "${src}" ]] && [[ "${src}" != "${dst}" ]]; then
            cp -f "${src}" "${dst}"
        fi
    }

    copy_if_needed "${steam_api_src}" "${server_dirname}/steam_api64.dll"
    copy_if_needed "${steamclient64_src}" "${server_dirname}/steamclient64.dll"
    copy_if_needed "${steamclient_src}" "${server_dirname}/steamclient.dll"
    copy_if_needed "${tier0_src}" "${server_dirname}/tier0_s64.dll"
    copy_if_needed "${vstdlib_src}" "${server_dirname}/vstdlib_s64.dll"

    printf "%s\n" "${steam_app_id}" > "${server_dirname}/steam_appid.txt"
}

cleanup() {
    if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
        kill -TERM "${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
    fi

    wineserver -k >/dev/null 2>&1 || true

    if [[ -n "${XVFB_PID}" ]] && kill -0 "${XVFB_PID}" 2>/dev/null; then
        kill -TERM "${XVFB_PID}" 2>/dev/null || true
        wait "${XVFB_PID}" 2>/dev/null || true
    fi
}

on_terminate() {
    echo "Received shutdown signal, stopping Conan Exiles..."
    cleanup
    exit 0
}

trap on_terminate SIGTERM SIGINT

export DISPLAY="${DISPLAY:-:99}"
export WINEARCH="${WINEARCH:-win64}"
export WINEPREFIX="${WINEPREFIX:-/opt/conan-exiles/.wine}"

mkdir -p "${STEAMCMD_DIR}" "${WINEPREFIX}"

echo "Starting Xvfb on ${DISPLAY}..."
Xvfb "${DISPLAY}" -screen 0 1024x768x24 >/dev/null 2>&1 &
XVFB_PID=$!
sleep 2

if [[ ! -x "${STEAMCMD_SH}" ]]; then
    echo "SteamCMD not found in mounted path; bootstrapping..."
    tmp_tar="/tmp/steamcmd_linux.tar.gz"
    curl -fsSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" -o "${tmp_tar}"
    tar -xzf "${tmp_tar}" -C "${STEAMCMD_DIR}"
    rm -f "${tmp_tar}"
    chmod +x "${STEAMCMD_SH}"
fi

if [[ "${CONAN_UPDATE_ON_START:-true}" == "true" ]]; then
    echo "Installing/updating Conan Exiles dedicated server via SteamCMD..."

    steamcmd_args=(
        +@sSteamCmdForcePlatformType windows
        +force_install_dir "${SERVER_DIR}"
        +login "${STEAMCMD_LOGIN:-anonymous}"
    )

    if [[ -n "${STEAMCMD_PASSWORD:-}" ]] && [[ "${STEAMCMD_LOGIN:-anonymous}" != "anonymous" ]]; then
        steamcmd_args=(
            +@sSteamCmdForcePlatformType windows
            +force_install_dir "${SERVER_DIR}"
            +login "${STEAMCMD_LOGIN}" "${STEAMCMD_PASSWORD}"
        )
    fi

    if [[ "${CONAN_VALIDATE_ON_START:-false}" == "true" ]]; then
        steamcmd_args+=(+app_update 443030 validate)
    else
        steamcmd_args+=(+app_update 443030)
    fi

    steamcmd_args+=(+quit)
    "${STEAMCMD_SH}" "${steamcmd_args[@]}"
else
    echo "Skipping SteamCMD update (CONAN_UPDATE_ON_START=false)."
fi

if [[ -n "${CONAN_SERVER_EXE:-}" ]]; then
    if [[ -f "${CONAN_SERVER_EXE}" ]]; then
        SERVER_EXE="${CONAN_SERVER_EXE}"
    elif [[ -f "${SERVER_DIR}/${CONAN_SERVER_EXE}" ]]; then
        SERVER_EXE="${SERVER_DIR}/${CONAN_SERVER_EXE}"
    else
        echo "WARNING: CONAN_SERVER_EXE was set but not found: ${CONAN_SERVER_EXE}" >&2
    fi
fi

if [[ -z "${SERVER_EXE}" ]]; then
    for candidate in \
        "${SERVER_DIR}/ConanSandbox/Binaries/Win64/ConanSandboxServer.exe" \
        "${SERVER_DIR}/ConanSandbox/Binaries/Win64/ConanSandboxServer-Win64-Shipping.exe" \
        "${SERVER_DIR}/ConanSandbox/Binaries/Win64/ConanSandboxServer-Win64-Test.exe" \
        "${SERVER_DIR}/ConanSandboxServer.exe" \
        ; do
        if [[ -f "${candidate}" ]]; then
            SERVER_EXE="${candidate}"
            break
        fi
    done
fi

if [[ -z "${SERVER_EXE}" ]]; then
    server_exe_candidate="$(find "${SERVER_DIR}" -type f \( -iname "*ConanSandbox*Server*.exe" -o -iname "*Server-Win64*.exe" \) | head -n 1 || true)"
    if [[ -n "${server_exe_candidate}" ]]; then
        SERVER_EXE="${server_exe_candidate}"
    fi
fi

if [[ -z "${SERVER_EXE}" ]] || [[ ! -f "${SERVER_EXE}" ]]; then
    echo "ERROR: Conan server executable not found under ${SERVER_DIR}" >&2
    echo "DEBUG: Available EXE files under install dir:" >&2
    find "${SERVER_DIR}" -type f -iname "*.exe" 2>/dev/null | head -n 50 >&2 || true
    cleanup
    exit 1
fi

if [[ ! -d "${WINEPREFIX}/drive_c" ]]; then
    echo "Initializing Wine prefix..."
    wineboot --init >/dev/null 2>&1 || true
fi

initialize_server_settings
ensure_engine_ini
ensure_steam_runtime_files "${SERVER_EXE}"

# Include legacy flags commonly used by the classic image to aid Steam registration
# -server ensures dedicated server mode
SERVER_ARGS=("-log" "-server" "-Unattended")

# BattlEye frequently causes join/auth failures under Wine; disable by default unless explicitly enabled
if [[ "${CONAN_DISABLE_BATTLEYE:-true}" == "true" ]]; then
    SERVER_ARGS+=("-NoBattlEye")
fi

# Force direct-connect mode when Steam backend is unstable/unavailable under Wine
if [[ "${CONAN_FORCE_NOSTEAM:-false}" == "true" ]]; then
    SERVER_ARGS+=("-NOSTEAM")
fi

if [[ -n "${CONAN_SERVER_PORT:-}" ]]; then
    SERVER_ARGS+=("-Port=${CONAN_SERVER_PORT}")
fi
if [[ -n "${CONAN_QUERY_PORT:-}" ]]; then
    SERVER_ARGS+=("-QueryPort=${CONAN_QUERY_PORT}")
fi
if [[ -n "${CONAN_RAW_UDP_PORT:-}" ]]; then
    SERVER_ARGS+=("-RawSocketsPort=${CONAN_RAW_UDP_PORT}")
fi
if [[ -n "${CONAN_MAX_PLAYERS:-}" ]]; then
    SERVER_ARGS+=("-MaxPlayers=${CONAN_MAX_PLAYERS}")
fi
if [[ -n "${CONAN_ADMIN_PASSWORD:-}" ]]; then
    SERVER_ARGS+=("-AdminPassword=${CONAN_ADMIN_PASSWORD}")
fi
if [[ -n "${CONAN_SERVER_PASSWORD:-}" ]]; then
    SERVER_ARGS+=("-ServerPassword=${CONAN_SERVER_PASSWORD}")
fi

if [[ -n "${CONAN_EXTRA_ARGS:-}" ]]; then
    read -r -a EXTRA_ARGS <<< "${CONAN_EXTRA_ARGS}"
    SERVER_ARGS+=("${EXTRA_ARGS[@]}")
fi

if [[ $# -gt 0 ]]; then
    SERVER_ARGS+=("$@")
fi

echo "Starting Conan Exiles server under Wine..."
echo "Executable: ${SERVER_EXE}"

cd "$(dirname "${SERVER_EXE}")"
wine "${SERVER_EXE}" "${SERVER_ARGS[@]}" &
SERVER_PID=$!

wait "${SERVER_PID}"
exit_code=$?

cleanup
echo "=== Server stopped (exit ${exit_code}) ==="
exit "${exit_code}"
