#!/usr/bin/env sh
# dae installer — patched for OpenWrt / GL.iNet MT6000 (busybox ash)
# Original: https://github.com/daeuniverse/dae-installer

set -e

## ── Color ────────────────────────────────────────────────────────────────────
if command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RESET=$(tput sgr0)
else
    RED='' GREEN='' YELLOW='' RESET=''
fi

## ── OS check ─────────────────────────────────────────────────────────────────
if [ "$(uname)" != 'Linux' ]; then
    echo "${RED}error: This script only supports Linux.${RESET}"
    exit 1
fi

## ── SHA256 wrapper ───────────────────────────────────────────────────────────
SHA256SUM() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v busybox >/dev/null 2>&1; then
        busybox sha256sum "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $2}'
    else
        echo "${RED}error: No sha256 tool found (sha256sum / busybox / openssl).${RESET}"
        exit 1
    fi
}

## ── Dependency check (curl + unzip) ─────────────────────────────────────────
tool_need=''
for tool in curl unzip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        tool_need="$tool $tool_need"
    fi
done

if [ -n "$tool_need" ]; then
    echo "${YELLOW}Installing missing tools: $tool_need${RESET}"
    if command -v opkg >/dev/null 2>&1; then
        opkg update && opkg install $tool_need
    elif command -v apk >/dev/null 2>&1; then
        apk add $tool_need
    elif command -v apt >/dev/null 2>&1; then
        apt update && apt install -y $tool_need
    else
        echo "${RED}error: Cannot install $tool_need — no known package manager.${RESET}"
        exit 1
    fi
fi

## ── Architecture detection ───────────────────────────────────────────────────
check_arch() {
    if [ -n "$MACHINE" ]; then return; fi

    arch="$(uname -m)"
    case "$arch" in
        aarch64 | armv8)   MACHINE='arm64' ;;
        armv7 | armv7l)    MACHINE='armv7' ;;
        armv6l)            MACHINE='armv6' ;;
        armv5tel)          MACHINE='armv5' ;;
        x86_64 | amd64)
            if grep -q avx2 /proc/cpuinfo 2>/dev/null; then
                MACHINE='x86_64_v3_avx2'
            elif grep -q sse /proc/cpuinfo 2>/dev/null; then
                MACHINE='x86_64_v2_sse'
            else
                MACHINE='x86_64'
            fi
            ;;
        i386 | i686)       MACHINE='x86_32' ;;
        mips)              MACHINE='mips32' ;;
        mipsle)            MACHINE='mips32le' ;;
        mips64)            MACHINE='mips64' ;;
        mips64le)          MACHINE='mips64le' ;;
        riscv64)           MACHINE='riscv64' ;;
        *)
            echo "${RED}error: Unsupported architecture: $arch${RESET}"
            exit 1
            ;;
    esac

    echo "${GREEN}Detected architecture: $MACHINE${RESET}"
}

## ── Version helpers ──────────────────────────────────────────────────────────
# POSIX version compare — no sort -V (not in busybox)
# Returns: 0=equal  1=$1>$2  2=$1<$2
ver_compare() {
    v1_base="$(echo "$1" | sed 's/^v//;s/-[^0-9].*//')"
    v2_base="$(echo "$2" | sed 's/^v//;s/-[^0-9].*//')"

    a1="$(echo "$v1_base" | cut -d. -f1)"
    b1="$(echo "$v1_base" | cut -d. -f2)"
    c1="$(echo "$v1_base" | cut -d. -f3)"
    a2="$(echo "$v2_base" | cut -d. -f1)"
    b2="$(echo "$v2_base" | cut -d. -f2)"
    c2="$(echo "$v2_base" | cut -d. -f3)"

    for pair in "${a1:-0}:${a2:-0}" "${b1:-0}:${b2:-0}" "${c1:-0}:${c2:-0}"; do
        n1="${pair%%:*}"
        n2="${pair##*:}"
        if [ "$n1" -gt "$n2" ]; then echo 1; return; fi
        if [ "$n1" -lt "$n2" ]; then echo 2; return; fi
    done
    echo 0
}

check_local_version() {
    echo "${GREEN}[1/4] Checking local dae version...${RESET}"
    if command -v /usr/bin/dae >/dev/null 2>&1; then
        current_version=$(/usr/bin/dae --version 2>/dev/null | awk 'NR==1{print $3}')
        echo "${GREEN}      Local version : ${current_version}${RESET}"
    else
        echo "${YELLOW}      dae not installed yet.${RESET}"
    fi
    current_version="${current_version:-0}"
}

check_online_version() {
    if [ "$allow_prereleases" = 'yes' ]; then
        api_url='https://api.github.com/repos/daeuniverse/dae/releases?per_page=1'
        echo "${GREEN}[2/4] Fetching latest release (including pre-releases)...${RESET}"
    else
        api_url='https://api.github.com/repos/daeuniverse/dae/releases/latest'
        echo "${GREEN}[2/4] Fetching latest stable release...${RESET}"
    fi

    tmp="$(mktemp /tmp/dae.XXXXXX)"
    if ! curl -sf "$api_url" -o "$tmp"; then
        echo "${RED}error: Failed to fetch release info from GitHub API.${RESET}"
        rm -f "$tmp"; exit 1
    fi

    latest_version="$(grep '"tag_name"' "$tmp" | head -n1 | \
        sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
    rm -f "$tmp"

    if [ -z "$latest_version" ]; then
        echo "${RED}error: Could not parse latest version.${RESET}"
        exit 1
    fi
    echo "${GREEN}      Remote version: ${latest_version}${RESET}"
}

compare_version() {
    echo "${GREEN}[3/4] Comparing versions...${RESET}"
    if [ "$current_version" = "$latest_version" ]; then
        compare_status=0
        echo "${GREEN}      Already up-to-date.${RESET}"
        return
    fi
    compare_status="$(ver_compare "$current_version" "$latest_version")"
    case "$compare_status" in
        1) echo "${YELLOW}      Local ($current_version) is newer than remote ($latest_version).${RESET}" ;;
        2) echo "${GREEN}      Update available: $current_version -> $latest_version${RESET}" ;;
    esac
}

## ── Download URLs ────────────────────────────────────────────────────────────
get_download_urls() {
    if [ "$use_cdn" = 'yes' ]; then
        _gh="https://github.abskoop.workers.dev/https://github.com/daeuniverse/dae/releases/download/$latest_version"
        _raw="https://cdn.jsdelivr.net/gh/daeuniverse/dae@$latest_version"
    else
        _gh="https://github.com/daeuniverse/dae/releases/download/$latest_version"
        _raw="https://github.com/daeuniverse/dae/raw/$latest_version"
    fi

    dae_url="${_gh}/dae-linux-${MACHINE}.zip"
    dae_hash_url="${_gh}/dae-linux-${MACHINE}.zip.dgst"
    example_config_url="${_raw}/example.dae"
    bash_completion_url="${_raw}/install/shell-completion/dae.bash"
    zsh_completion_url="${_raw}/install/shell-completion/dae.zsh"
    fish_completion_url="${_raw}/install/shell-completion/dae.fish"
    geoip_url='https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat'
    geosite_url='https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat'
}

## ── GeoIP ────────────────────────────────────────────────────────────────────
check_share_dir() { mkdir -p /usr/share/dae; }

download_geoip() {
    geoip_tmp="$(mktemp -d /tmp/dae.XXXXXX)"
    echo "${GREEN}Downloading GeoIP from: $geoip_url${RESET}"
    curl -L "$geoip_url" -o "$geoip_tmp/geoip.dat" || \
        { echo "${RED}error: GeoIP download failed.${RESET}"; rm -rf "$geoip_tmp"; exit 1; }
    curl -sL "${geoip_url}.sha256sum" -o "$geoip_tmp/geoip.dat.sha256sum" || \
        { echo "${RED}error: GeoIP checksum download failed.${RESET}"; rm -rf "$geoip_tmp"; exit 1; }
    local_hash="$(SHA256SUM "$geoip_tmp/geoip.dat")"
    remote_hash="$(awk '{print $1}' < "$geoip_tmp/geoip.dat.sha256sum")"
    echo "${GREEN}      Checksum: $local_hash${RESET}"
    if [ "$local_hash" != "$remote_hash" ]; then
        echo "${RED}error: GeoIP checksum mismatch — local=$local_hash remote=$remote_hash${RESET}"
        rm -rf "$geoip_tmp"; exit 1
    fi
}
update_geoip() {
    check_share_dir
    cp "$geoip_tmp/geoip.dat" /usr/share/dae/
    rm -rf "$geoip_tmp"
    echo "${GREEN}GeoIP installed/updated.${RESET}"
}

## ── GeoSite ──────────────────────────────────────────────────────────────────
download_geosite() {
    geosite_tmp="$(mktemp -d /tmp/dae.XXXXXX)"
    echo "${GREEN}Downloading GeoSite from: $geosite_url${RESET}"
    curl -L "$geosite_url" -o "$geosite_tmp/geosite.dat" || \
        { echo "${RED}error: GeoSite download failed.${RESET}"; rm -rf "$geosite_tmp"; exit 1; }
    curl -sL "${geosite_url}.sha256sum" -o "$geosite_tmp/geosite.dat.sha256sum" || \
        { echo "${RED}error: GeoSite checksum download failed.${RESET}"; rm -rf "$geosite_tmp"; exit 1; }
    local_hash="$(SHA256SUM "$geosite_tmp/geosite.dat")"
    remote_hash="$(awk '{print $1}' < "$geosite_tmp/geosite.dat.sha256sum")"
    echo "${GREEN}      Checksum: $local_hash${RESET}"
    if [ "$local_hash" != "$remote_hash" ]; then
        echo "${RED}error: GeoSite checksum mismatch — local=$local_hash remote=$remote_hash${RESET}"
        rm -rf "$geosite_tmp"; exit 1
    fi
}
update_geosite() {
    check_share_dir
    cp "$geosite_tmp/geosite.dat" /usr/share/dae/
    rm -rf "$geosite_tmp"
    echo "${GREEN}GeoSite installed/updated.${RESET}"
}

## ── dae binary ───────────────────────────────────────────────────────────────
download_dae() {
    echo "${GREEN}[4/4] Downloading dae binary...${RESET}"
    echo "${GREEN}      URL: $dae_url${RESET}"
    curl -L "$dae_url" -o "dae-linux-${MACHINE}.zip" || \
        { echo "${RED}error: dae download failed.${RESET}"; exit 1; }
    local_hash="$(SHA256SUM "dae-linux-${MACHINE}.zip")"
    curl -sL "$dae_hash_url" -o "dae-linux-${MACHINE}.zip.dgst" || \
        { echo "${RED}error: checksum file download failed.${RESET}"
          rm -f "dae-linux-${MACHINE}.zip.dgst"; exit 1; }
    # Try matching by filename first, then fall back to line 3
    remote_hash="$(awk -v name="./dae-linux-${MACHINE}.zip" \
        '$0 ~ name {print $1}' "dae-linux-${MACHINE}.zip.dgst" | head -n1)"
    if [ -z "$remote_hash" ]; then
        remote_hash="$(awk 'NR==3{print $1}' "dae-linux-${MACHINE}.zip.dgst")"
    fi
    if [ "$local_hash" != "$remote_hash" ]; then
        echo "${RED}error: dae checksum mismatch — local=$local_hash remote=$remote_hash${RESET}"
        rm -f "dae-linux-${MACHINE}.zip" "dae-linux-${MACHINE}.zip.dgst"
        exit 1
    fi
    rm -f "dae-linux-${MACHINE}.zip.dgst"
    echo "${GREEN}      Checksum OK.${RESET}"
}

install_dae() {
    tmp_dir="$(mktemp -d /tmp/dae.XXXXXX)"
    echo "${GREEN}Extracting dae...${RESET}"
    unzip -q "dae-linux-${MACHINE}.zip" -d "$tmp_dir"
    cp "$tmp_dir/dae-linux-${MACHINE}" /usr/bin/dae
    chmod +x /usr/bin/dae
    rm -f "dae-linux-${MACHINE}.zip"
    rm -rf "$tmp_dir"
    echo "${GREEN}dae installed → /usr/bin/dae${RESET}"
    install_initd
}

install_initd() {
    if [ -f /etc/init.d/dae ]; then
        echo "${GREEN}init.d/dae already exists, skipping.${RESET}"
        return
    fi
    echo "${GREEN}Installing /etc/init.d/dae...${RESET}"
    mkdir -p /var/log/dae
    cat > /etc/init.d/dae << 'INITD'
#!/bin/sh /etc/rc.common

USE_PROCD=1

START=99
STOP=10

readonly NAME="dae"
readonly PROG="/usr/bin/dae"
readonly CONF="/etc/dae/config.dae"
readonly LOG="/var/log/dae/dae.log"

EXTRA_COMMANDS="reload_config"
EXTRA_HELP="        reload_config   Reload $NAME config"

start_service() {
    config_load $NAME

    mkdir -p /var/log/dae
    $PROG validate -c $CONF >> $LOG 2>&1 || return 1

    procd_open_instance $NAME
        procd_set_param command $PROG
        procd_append_param command run --logfile $LOG -c $CONF

        local size
        size=$(uci -q get ${NAME}.settings.logfile_maxsize)
        size="${size:-1}"
        if [ -n "$size" ] && [ "$size" -gt 0 ]; then
            procd_append_param command --logfile-maxsize $size
        fi

        procd_set_param limits core="unlimited"
        procd_set_param limits nofile="1000000 1000000"
        procd_set_param respawn
        procd_set_param stderr 1

    procd_close_instance
}

restart() {
    stop
    start
}

reload_service() {
    stop
    start
}

service_triggers() {
    procd_add_reload_trigger $NAME
}

reload_config() {
    $PROG reload
}
INITD
    chmod +x /etc/init.d/dae
    echo "${GREEN}init.d/dae installed.${RESET}"
}

## ── Config / completions ─────────────────────────────────────────────────────
download_example_config() {
    mkdir -p /etc/dae
    echo "${GREEN}Downloading example config...${RESET}"
    curl -sL "$example_config_url" -o /etc/dae/example.dae || notify_example='yes'
}

download_completions() {
    if command -v bash >/dev/null 2>&1; then
        mkdir -p /usr/share/bash-completion/completions
        curl -sL "$bash_completion_url" -o /usr/share/bash-completion/completions/dae \
            || echo "${YELLOW}bash completion download failed (non-fatal).${RESET}"
    fi
    if command -v zsh >/dev/null 2>&1; then
        mkdir -p /usr/share/zsh/site-functions
        curl -sL "$zsh_completion_url" -o /usr/share/zsh/site-functions/_dae \
            || echo "${YELLOW}zsh completion download failed (non-fatal).${RESET}"
    fi
    if command -v fish >/dev/null 2>&1; then
        mkdir -p /usr/share/fish/vendor_completions.d
        curl -sL "$fish_completion_url" -o /usr/share/fish/vendor_completions.d/dae.fish \
            || echo "${YELLOW}fish completion download failed (non-fatal).${RESET}"
    fi
}

## ── Service (procd-first, systemd fallback) ──────────────────────────────────
stop_dae() {
    dae_stopped=''
    if [ -f /etc/init.d/dae ] && [ -f /run/dae.pid ] && [ -s /run/dae.pid ]; then
        echo "${GREEN}Stopping dae (procd)...${RESET}"
        /etc/init.d/dae stop && dae_stopped='1'
    elif command -v systemctl >/dev/null 2>&1 && \
         [ "$(systemctl is-active dae 2>/dev/null)" = 'active' ]; then
        echo "${GREEN}Stopping dae (systemd)...${RESET}"
        systemctl stop dae && dae_stopped='1'
    fi
}

start_dae() {
    if [ "$dae_stopped" = '1' ] && [ -f /etc/init.d/dae ]; then
        echo "${GREEN}Starting dae...${RESET}"
        if /etc/init.d/dae start; then
            echo "${GREEN}dae started.${RESET}"
        else
            echo "${RED}Failed to start dae — check /etc/dae/config.dae${RESET}"
        fi
    fi
}

## ── Banner ───────────────────────────────────────────────────────────────────
echo_dae() {
    cat <<EOF

   __| | __ _  ___       Copyright (C) $(date +%Y)@daeuniverse
  / \` |/ _\` |/ _ \\      https://github.com/daeuniverse/dae
 | (_| | (_| |  __/      Licensed under AGPL-3.0
  \\__,_|\\__,_|\\___|

This software comes with ABSOLUTELY NO WARRANTY.
EOF
}

## ── Post-install notices ─────────────────────────────────────────────────────
notice_installed_tool() {
    if [ -n "$tool_need" ]; then
        echo "${GREEN}Installed during setup: $tool_need${RESET}"
        echo "${GREEN}You may remove them if no longer needed.${RESET}"
    fi
}

notify_configuration() {
    echo '--------------------------------------------------------------------'
    if [ "$notify_example" = 'yes' ]; then
        echo "${YELLOW}warning: Example config not downloaded.${RESET}"
        echo "${YELLOW}  https://github.com/daeuniverse/dae/raw/$latest_version/example.dae${RESET}"
        echo '--------------------------------------------------------------------'
    fi
    echo "${GREEN}Installed version: $latest_version${RESET}"
    echo '--------------------------------------------------------------------'
    if command -v service >/dev/null 2>&1; then
        echo "${GREEN}Start:  service dae start${RESET}"
        echo "${GREEN}Enable: service dae enable${RESET}"
    else
        echo "${YELLOW}No init script found — write a procd service manually.${RESET}"
    fi
    echo '--------------------------------------------------------------------'
    echo "${GREEN}Config: /etc/dae/config.dae${RESET}"
    echo "${GREEN}Secure: chmod 600 /etc/dae/config.dae${RESET}"
    echo '--------------------------------------------------------------------'
}

## ── Full installation ────────────────────────────────────────────────────────
installation() {
    echo_dae
    download_dae
    download_geoip
    download_geosite
    download_example_config
    download_completions
    stop_dae
    install_dae
    update_geoip
    update_geosite
    start_dae
    notice_installed_tool
    notify_configuration
}

should_we_install_dae() {
    check_arch
    if [ "$force_install" = 'yes' ]; then
        check_online_version
        current_version='0'
    else
        check_local_version
        check_online_version
    fi
    compare_version
    get_download_urls

    case "$compare_status" in
        0) echo "${GREEN}dae is up-to-date ($current_version).${RESET}"
           notice_installed_tool ;;
        1) echo "${YELLOW}Local $current_version > remote $latest_version.${RESET}"
           echo "${GREEN}Use force-install to override.${RESET}" ;;
        2) if [ "$current_version" = '0' ]; then
               echo "${GREEN}Installing dae $latest_version...${RESET}"
           else
               echo "${GREEN}Upgrading dae $current_version → $latest_version...${RESET}"
           fi
           installation ;;
    esac
}

## ── Help ─────────────────────────────────────────────────────────────────────
show_helps() {
    cat <<EOF
Usage: $0 [command]

Commands:
  install                install/update dae  (default)
  install-prerelease     include pre-release versions
  force-install          skip version check, reinstall
  update-geoip           update GeoIP database only
  update-geosite         update GeoSite database only
  use-cdn                use Cloudflare/jsDelivr CDN mirrors
  help                   show this message
EOF
}

## ── Entry point ──────────────────────────────────────────────────────────────
current_dir="$(pwd)"
cd /tmp || { echo "${YELLOW}Cannot cd to /tmp${RESET}"; exit 1; }
trap 'cd "$current_dir"' EXIT INT TERM

if [ $# -eq 0 ]; then
    # Default behavior for "install/update" should follow stable releases.
    # Pre-releases are enabled only via explicit "install-prerelease".
    allow_prereleases=''
    should_we_install_dae
    exit 0
fi

show_help='' error_help='' normal_install='' force_install=''
allow_prereleases='' use_cdn=''
geoip_should_update='' geosite_should_update=''

for arg in "$@"; do
    case "$arg" in
        install)                        normal_install='yes' ;;
        install-prerelease | \
        install-prereleases)            allow_prereleases='yes' ;;
        force-install)                  force_install='yes' ;;
        use-cdn)                        use_cdn='yes' ;;
        update-geoip)                   geoip_should_update='yes' ;;
        update-geosite)                 geosite_should_update='yes' ;;
        help)                           show_help='yes' ;;
        *) echo "${RED}error: Unknown command: $arg${RESET}"; error_help='yes' ;;
    esac
done

if [ "$show_help" = 'yes' ] || [ "$error_help" = 'yes' ]; then
    show_helps
    [ "$error_help" = 'yes' ] && exit 1
    exit 0
fi

if [ "$force_install" = 'yes' ] || [ "$normal_install" = 'yes' ] || \
   [ "$allow_prereleases" = 'yes' ]; then
    should_we_install_dae
fi

if [ "$geoip_should_update" = 'yes' ]; then
    check_arch; get_download_urls
    download_geoip; update_geoip
fi

if [ "$geosite_should_update" = 'yes' ]; then
    check_arch; get_download_urls
    download_geosite; update_geosite
fi
