#!/bin/bash
set -Eeuo pipefail

echo "=== Conan Exiles Server Startup ==="

STEAMCMD_DIR="/home/steam/steamcmd"
STEAMCMD_SH="${STEAMCMD_DIR}/steamcmd.sh"
SERVER_DIR="${STEAMCMD_DIR}/conan-dedicated"
SERVER_EXE=""
CONFIG_DIR="${SERVER_DIR}/ConanSandbox/Saved/Config/WindowsServer"
SETTINGS_FILE="${CONFIG_DIR}/ServerSettings.ini"
ENGINE_FILE="${CONFIG_DIR}/Engine.ini"
XVFB_PID=""
SERVER_PID=""

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

    local tmp
    tmp="${ENGINE_FILE}.tmp.$$"

    ensure_section() {
        local section="$1"
        if ! grep -qiE "^\\[${section}\\]$" "${ENGINE_FILE}"; then
            printf "\n[%s]\n" "${section}" >> "${ENGINE_FILE}"
        fi
    }

    set_kv_in_section() {
        local section="$1" key="$2" value="$3"
        ensure_section "${section}"
        awk -v sec="${section}" -v key="${key}" -v val="${value}" '
            BEGIN{ins=0}
            /^[[]/{ins = (tolower($0)=="[" tolower(sec) "]")}
            {
                if (ins && tolower($0) ~ "^" tolower(key) "=") { print key"="val; next }
                print
            }
        ' "${ENGINE_FILE}" > "${tmp}"
        # If key was not present, append it at end of section (by adding again)
        if ! awk -v sec="${section}" -v key="${key}" 'BEGIN{ins=0;found=0}
            /^[[]/{ins = ($0=="["sec"]")}
            { if (ins && $0 ~ "^"key"=") found=1 }
            END{exit(found?0:1)}' "${ENGINE_FILE}"; then
            # append key at end
            printf "%s=%s\n" "${key}" "${value}" >> "${tmp}"
        fi
        mv -f "${tmp}" "${ENGINE_FILE}"
    }

    # Values (allow override via env if provided)
    local build_id="${CONAN_BUILD_ID_OVERRIDE:-812257115}"
    local server_name_ini="${CONAN_SERVER_NAME:-Conan Exiles Server}"
    local qport="${CONAN_QUERY_PORT:-27015}"
    local gport="${CONAN_SERVER_PORT:-7777}"

    # [OnlineSubsystem]
    set_kv_in_section "OnlineSubsystem" "bUseBuildIdOverride" "True"
    set_kv_in_section "OnlineSubsystem" "BuildIdOverride" "${build_id}"
    set_kv_in_section "OnlineSubsystem" "ServerName" "${server_name_ini}"
    set_kv_in_section "OnlineSubsystem" "DefaultPlatformService" "Steam"

    # [OnlineSubsystemSteam]
    set_kv_in_section "OnlineSubsystemSteam" "bEnabled" "true"
    set_kv_in_section "OnlineSubsystemSteam" "SteamDevAppId" "440900"
    set_kv_in_section "OnlineSubsystemSteam" "ServerQueryPort" "${qport}"
    set_kv_in_section "OnlineSubsystemSteam" "ServerPort" "${gport}"
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
        "${SERVER_DIR}/ConanSandboxServer.exe"; do
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

SERVER_ARGS=("-log" "-Unattended")

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

wine "${SERVER_EXE}" "${SERVER_ARGS[@]}" &
SERVER_PID=$!

wait "${SERVER_PID}"
exit_code=$?

cleanup
echo "=== Server stopped (exit ${exit_code}) ==="
exit "${exit_code}"
