#!/usr/bin/env bash
#
# RomM installer / uninstaller (Docker Compose)
# Detects distro, ensures Docker + Compose, writes a compose stack
# (RomM + MariaDB + Redis), starts it, and prints the URL.
#
# Usage:
#   bash romm-install.sh            # install
#   bash romm-install.sh uninstall  # stop and optionally remove data
#

set -euo pipefail

START_TIME=$(date +%s)
DEFAULT_DIR="/opt/romm"
DEFAULT_PORT=8081
ROMM_IMAGE="rommapp/romm:latest"
DB_IMAGE="mariadb:latest"

# ── helpers (logs to stderr) ───────────────────────────────────────────────
die() { echo -e "\n\033[1;31mError:\033[0m $*" >&2; exit 1; }
info() { echo -e "\033[1;34m==>\033[0m $*" >&2; }
ok() { echo -e "\033[1;32m==>\033[0m $*" >&2; }
warn() { echo -e "\033[1;33m==>\033[0m $*" >&2; }
prompt() { local var="$1" msg="$2" default="$3"; read -rp "$msg [$default]: " input; printf -v "$var" '%s' "${input:-$default}"; }
ask_yn() { local msg="$1" default="${2:-n}"; local ans; read -rp "$msg [y/N]: " ans; ans="${ans:-$default}"; [[ "$ans" =~ ^[Yy] ]]; }

elapsed() {
  local end=$(date +%s)
  local secs=$((end - START_TIME))
  printf '%dm %ds' $((secs/60)) $((secs%60))
}

# ── distro detection ───────────────────────────────────────────────────────
detect_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    ID="${ID:-}"
    ID_LIKE="${ID_LIKE:-}"
  else
    die "Cannot detect distro (/etc/os-release missing)."
  fi

  case "$ID" in
    debian|ubuntu|linuxmint|pop|elementary|zorin) PKG="apt" ;;
    fedora|rhel|rocky|almalinux|centos|ol)         PKG="dnf" ;;
    arch|manjaro|endeavouros|garuda)               PKG="pacman" ;;
    opensuse*|sles)                                PKG="zypper" ;;
    alpine)                                        PKG="apk" ;;
    *)
      case "$ID_LIKE" in
        *debian*|*ubuntu*) PKG="apt" ;;
        *rhel*|*fedora*)   PKG="dnf" ;;
        *arch*)            PKG="pacman" ;;
        *suse*)            PKG="zypper" ;;
        *) die "Unsupported distro: $ID (ID_LIKE=$ID_LIKE). Supported: Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE, Alpine." ;;
      esac
      ;;
  esac
  info "Detected: $ID ($PKG)"
}

# ── docker ─────────────────────────────────────────────────────────────────
install_docker() {
  info "Checking Docker..."

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ok "Docker + Compose already available"
  else
    info "Installing Docker..."
    case "$PKG" in
      apt)
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2 curl ca-certificates openssl
        ;;
      dnf)
        if ! command -v docker >/dev/null 2>&1; then
          sudo dnf install -y docker docker-compose curl ca-certificates openssl || \
          sudo dnf install -y moby-engine docker-compose curl ca-certificates openssl
        else
          sudo dnf install -y docker-compose curl ca-certificates openssl || true
        fi
        ;;
      pacman)
        sudo pacman -Sy --noconfirm docker docker-compose curl ca-certificates openssl
        ;;
      zypper)
        sudo zypper --non-interactive install docker docker-compose curl ca-certificates openssl
        ;;
      apk)
        sudo apk add --no-cache docker docker-cli-compose curl ca-certificates openssl
        ;;
    esac
  fi

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now docker 2>/dev/null || true
  elif command -v rc-service >/dev/null 2>&1; then
    sudo rc-update add docker default 2>/dev/null || true
    sudo rc-service docker start 2>/dev/null || true
  fi

  if ! docker compose version >/dev/null 2>&1; then
    die "Docker Compose plugin not available. Install docker-compose-v2 / docker-compose and re-run."
  fi
  ok "Docker ready."
}

# ── prompts ────────────────────────────────────────────────────────────────
ask_config() {
  echo
  prompt INSTALL_DIR "Install directory" "$DEFAULT_DIR"
  prompt PORT "Host port" "$DEFAULT_PORT"
  prompt LIBRARY_DIR "ROM library directory" "$INSTALL_DIR/library"
  prompt ASSETS_DIR "Assets directory (saves/states)" "$INSTALL_DIR/assets"
  prompt CONFIG_DIR "Config directory" "$INSTALL_DIR/config"
  prompt DB_PASSWORD "Database password" "romm"
  prompt ROMM_IMAGE "RomM image" "$ROMM_IMAGE"

  [[ "$PORT" =~ ^[0-9]+$ ]] || die "Port must be a number."

  # auth secret
  AUTH_SECRET=$(openssl rand -hex 32 2>/dev/null || cat /proc/sys/kernel/random/uuid | tr -d '-')
  info "Generated ROMM_AUTH_SECRET_KEY"

  echo
  info "Metadata providers are optional. Leave blank and set them later in the UI."
  prompt SCREENSCRAPER_USER "ScreenScraper username (optional)" ""
  prompt SCREENSCRAPER_PASSWORD "ScreenScraper password (optional)" ""
  prompt IGDB_CLIENT_ID "IGDB client ID (optional)" ""
  prompt IGDB_CLIENT_SECRET "IGDB client secret (optional)" ""
}

# ── files ──────────────────────────────────────────────────────────────────
setup_files() {
  info "Setting up $INSTALL_DIR ..."
  sudo mkdir -p "$INSTALL_DIR" "$LIBRARY_DIR" "$ASSETS_DIR" "$CONFIG_DIR"
  sudo chown -R "$USER:$USER" "$INSTALL_DIR" "$LIBRARY_DIR" "$ASSETS_DIR" "$CONFIG_DIR" 2>/dev/null || true

  info "Writing .env..."
  cat > "$INSTALL_DIR/.env" <<ENV
DB_PASSWORD=${DB_PASSWORD}
AUTH_SECRET=${AUTH_SECRET}
SCREENSCRAPER_USER=${SCREENSCRAPER_USER}
SCREENSCRAPER_PASSWORD=${SCREENSCRAPER_PASSWORD}
IGDB_CLIENT_ID=${IGDB_CLIENT_ID}
IGDB_CLIENT_SECRET=${IGDB_CLIENT_SECRET}
ENV

  info "Writing docker-compose.yml..."
  cat > "$INSTALL_DIR/docker-compose.yml" <<YML
services:
  romm:
    image: ${ROMM_IMAGE}
    container_name: romm
    restart: unless-stopped
    environment:
      - DB_HOST=romm-db
      - DB_NAME=romm
      - DB_USER=romm-user
      - DB_PASSWD=\${DB_PASSWORD}
      - ROMM_AUTH_SECRET_KEY=\${AUTH_SECRET}
      - SCREENSCRAPER_USER=\${SCREENSCRAPER_USER}
      - SCREENSCRAPER_PASSWORD=\${SCREENSCRAPER_PASSWORD}
      - IGDB_CLIENT_ID=\${IGDB_CLIENT_ID}
      - IGDB_CLIENT_SECRET=\${IGDB_CLIENT_SECRET}
      - HASHEOUS_API_ENABLED=true
      - SCAN_WORKERS=4
    volumes:
      - romm_resources:/romm/resources
      - romm_redis_data:/redis-data
      - ${LIBRARY_DIR}:/romm/library
      - ${ASSETS_DIR}:/romm/assets
      - ${CONFIG_DIR}:/romm/config
    ports:
      - "${PORT}:8080"
    depends_on:
      romm-db:
        condition: service_healthy
        restart: true

  romm-db:
    image: ${DB_IMAGE}
    container_name: romm-db
    restart: unless-stopped
    environment:
      - MARIADB_ROOT_PASSWORD=\${DB_PASSWORD}
      - MARIADB_DATABASE=romm
      - MARIADB_USER=romm-user
      - MARIADB_PASSWORD=\${DB_PASSWORD}
    volumes:
      - mysql_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      start_period: 30s
      start_interval: 10s
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  mysql_data:
  romm_resources:
  romm_redis_data:
YML

  ok "Files ready."
}

start_stack() {
  info "Starting RomM (docker compose up -d)..."
  cd "$INSTALL_DIR"
  if docker info >/dev/null 2>&1; then
    docker compose up -d
  else
    sudo docker compose up -d
  fi
  ok "Containers started."
}

# ── uninstall ──────────────────────────────────────────────────────────────
uninstall() {
  echo "RomM uninstaller"
  echo "================"
  detect_distro

  echo
  prompt INSTALL_DIR "Install directory" "$DEFAULT_DIR"

  if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    info "Stopping containers..."
    cd "$INSTALL_DIR"
    if docker info >/dev/null 2>&1; then
      docker compose down || true
    else
      sudo docker compose down || true
    fi
    ok "Containers stopped."
  else
    warn "No docker-compose.yml found in $INSTALL_DIR"
  fi

  if ask_yn "Remove install directory $INSTALL_DIR (compose file and .env)?"; then
    sudo rm -rf "$INSTALL_DIR"
    ok "Install directory removed."
  fi

  if ask_yn "Also remove Docker volumes (database + resources)? This deletes RomM data."; then
    if docker info >/dev/null 2>&1; then
      docker volume ls -q | grep -E 'romm|mysql_data|romm_resources|romm_redis' | xargs -r docker volume rm || true
    else
      sudo docker volume ls -q | grep -E 'romm|mysql_data|romm_resources|romm_redis' | xargs -r sudo docker volume rm || true
    fi
    ok "Volumes removed."
  fi

  if ask_yn "Also remove Docker packages? (may affect other containers)"; then
    info "Removing Docker packages..."
    case "$PKG" in
      apt)    sudo apt-get remove -y docker.io docker-compose-v2 || true ;;
      dnf)    sudo dnf remove -y docker docker-compose moby-engine || true ;;
      pacman) sudo pacman -Rns --noconfirm docker docker-compose || true ;;
      zypper) sudo zypper --non-interactive remove docker docker-compose || true ;;
      apk)    sudo apk del docker docker-cli-compose || true ;;
    esac
    ok "Package removal finished."
  fi

  echo
  ok "Uninstall finished in $(elapsed)"
}

# ── main ───────────────────────────────────────────────────────────────────
main() {
  local mode="${1:-install}"

  case "$mode" in
    uninstall|remove|--uninstall|-u)
      uninstall
      ;;
    install|"")
      echo "RomM installer (Docker Compose)"
      echo "==============================="
      detect_distro
      install_docker
      ask_config
      setup_files
      start_stack

      local ip
      ip=$(hostname -I 2>/dev/null | awk '{print $1}') || ip="localhost"

      echo
      ok "Done in $(elapsed)"
      echo
      echo "  Open:  http://${ip:-localhost}:${PORT}"
      echo "  Dir:   $INSTALL_DIR"
      echo "  Library: $LIBRARY_DIR"
      echo "  Assets:  $ASSETS_DIR"
      echo
      echo "First start can take a minute while MariaDB initializes."
      echo "Create your admin account on first visit."
      echo
      echo "Library folder structure (example):"
      echo "  $LIBRARY_DIR/roms/nes/"
      echo "  $LIBRARY_DIR/roms/snes/"
      echo "  $LIBRARY_DIR/roms/switch/"
      echo
      echo "Useful commands (run from $INSTALL_DIR):"
      echo "  docker compose ps"
      echo "  docker compose logs -f romm"
      echo "  docker compose down"
      echo
      echo "To uninstall later: bash $0 uninstall"
      ;;
    *)
      die "Unknown option: $mode. Use: $0 [install|uninstall]"
      ;;
  esac
}

main "$@"
