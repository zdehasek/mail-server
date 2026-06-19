#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

resolve_script_path() {
  local source="$1"
  local dir target

  while [[ -L "$source" ]]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    target="$(readlink "$source")"
    if [[ "$target" == /* ]]; then
      source="$target"
    else
      source="$dir/$target"
    fi
  done

  dir="$(cd -P "$(dirname "$source")" && pwd)"
  printf '%s/%s\n' "$dir" "$(basename "$source")"
}

config_home() {
  local sudo_home

  if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    sudo_home="$(getent passwd "$SUDO_USER" | cut -d: -f6 || true)"
    if [[ -n "$sudo_home" ]]; then
      printf '%s\n' "$sudo_home"
      return 0
    fi
  fi

  if [[ -n "${HOME:-}" ]]; then
    printf '%s\n' "$HOME"
    return 0
  fi

  getent passwd "$(id -un)" | cut -d: -f6
}

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_IS_FILE="false"
if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
  SCRIPT_IS_FILE="true"
  SCRIPT_SOURCE="$(resolve_script_path "$SCRIPT_SOURCE")"
  ROOT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
  ROOT_DIR="$PWD"
fi
PIPE_MODE="true"
if [[ "$SCRIPT_IS_FILE" == "true" && -f "$ROOT_DIR/install.sh" && -f "$ROOT_DIR/lib/common.sh" ]]; then
  PIPE_MODE="false"
fi
CONFIG_FILE="${CONFIG:-${ENV_FILE:-}}"
INSTALL_DIR="${MAILSERVER_INSTALL_DIR:-/opt/mailserver}"
CONFIG_DIR="${MAILSERVER_CONFIG_DIR:-$(config_home)/.email-server}"
DEFAULT_CONFIG_FILE="$CONFIG_DIR/config.env"
CLI_PATH="${MAILSERVER_CLI_PATH:-/usr/local/bin/mailserver}"
REPO_URL="${MAILSERVER_REPO_URL:-https://github.com/zdehasek/email-server.git}"
REPO_REF="${MAILSERVER_REF:-}"
COMMAND=""
COMMAND_ARGS=()

use_color() {
  [[ -n "${NO_COLOR:-}" ]] && return 1
  [[ -n "${FORCE_COLOR:-}" && "${FORCE_COLOR:-}" != "0" ]] && return 0
  [[ -n "${CLICOLOR_FORCE:-}" && "${CLICOLOR_FORCE:-}" != "0" ]] && return 0
  [[ -t 1 && "${TERM:-}" != "dumb" ]]
}

color() {
  local code="$1"
  shift
  if use_color; then
    printf '\033[%sm%s\033[0m' "$code" "$*"
  else
    printf '%s' "$*"
  fi
}

say() {
  printf '%s\n' "$(color 30 "🔹 $*")"
}

ok() {
  printf '%s\n' "$(color 32 "✅ $*")"
}

warn() {
  printf '%s\n' "$(color "38;5;208" "⚠️ $*")" >&2
}

die() {
  printf '%s\n' "$(color 31 "❌ $*")" >&2
  exit 1
}

format_command() {
  local arg rendered=""
  for arg in "$@"; do
    printf -v arg '%q' "$arg"
    rendered+="${rendered:+ }$arg"
  done
  printf '%s\n' "$rendered"
}

default_config() {
  if [[ -n "$CONFIG_FILE" ]]; then
    printf '%s\n' "$CONFIG_FILE"
  else
    printf '%s\n' "$DEFAULT_CONFIG_FILE"
  fi
}

show_help() {
  cat <<'HELP'
📬 Mail server installer

Usage:
  mailserver [--config PATH] COMMAND [OPTIONS]
  curl -fsSL https://raw.githubusercontent.com/zdehasek/email-server/master/mailserver.sh | sudo bash

Setup:
  init                         Create ~/.email-server/config.env interactively
  install-cli                  Install mailserver into PATH
  doctor                       Validate local prerequisites and config
  setup-dry-run                Run doctor, dry-run install, and DNS output
  dry-run                      Show install actions without applying them
  install                      Install on this server
  setup                        Run doctor, install, verify, and DNS output
  update                       Update this installer checkout from git

Health checks:
  verify                       Check local configs and active services
  check                        Run DNS, SSL/TLS, and service checks
  dns-state                    Check A/AAAA, MX, SPF, DMARC, PTR, DKIM
  check-ssl                    Check HTTPS, IMAPS, and SMTP TLS certs
  service-state                Check services, ports, and web endpoints
  print-dns                    Print DNS records, including generated DKIM

Client configuration:
  client-info                  Print Apple Mail, Thunderbird, and CalDAV settings
  client-config                Alias for client-info
  client-info --user user@example.com

Mailbox operations:
  list-users
  add-user --user user@example.com [--full-name "Full Name"]
  remove-user --user user@example.com
  setup-primary-mailbox
  add-alias --source postmaster@example.com --dest user@example.com
  change-password --user user@example.com

Backup:
  backup
  install-backup-cron

Examples:
  mailserver init
  mailserver doctor
  mailserver setup-dry-run
  sudo mailserver install
  mailserver client-info --user user@example.com
  ./mailserver.sh doctor --config .env.example
  curl -fsSL https://raw.githubusercontent.com/zdehasek/email-server/master/mailserver.sh | sudo bash
  curl -fsSL https://raw.githubusercontent.com/zdehasek/email-server/master/mailserver.sh | sudo MAILSERVER_INSTALL_DIR=/opt/mailserver bash -s -- setup-dry-run

Notes:
  The default config is ~/.email-server/config.env. When run through sudo,
  sudo user's home is used so sudo mailserver install sees the same config
  created by mailserver init.
  Install and setup run locally on the target server. This CLI does not provide
  a remote deploy command.
  Curl-pipe use bootstraps a local git checkout, then runs this CLI there.
  With no curl-pipe command argument, it runs init by default.
HELP
}

show_command_help() {
  case "$1" in
    add-user)
      printf 'Usage: mailserver add-user --user user@example.com [--full-name "Full Name"] [--config PATH]\n'
      ;;
    remove-user|change-password)
      printf 'Usage: mailserver %s --user user@example.com [--config PATH]\n' "$1"
      ;;
    add-alias)
      printf 'Usage: mailserver add-alias --source source@example.com --dest dest@example.com [--config PATH]\n'
      ;;
    client-info|client-config)
      printf 'Usage: mailserver %s [--user user@example.com] [--config PATH]\n' "$1"
      ;;
    init)
      printf 'Usage: mailserver init [--domain DOMAIN] [--admin-email EMAIL] [--mail-hostname HOST] [--webmail-hostname HOST] [--dav-hostname HOST] [--public-ipv4 IP] [--public-ipv6 IP] [--timezone TZ] [--non-interactive] [--config PATH]\n'
      ;;
    install-cli)
      printf 'Usage: mailserver install-cli\n'
      ;;
    update)
      printf 'Usage: mailserver update\n'
      ;;
    *)
      show_help
      ;;
  esac
}

parse_global_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ -n "${2:-}" ]] || die "Missing value for --config."
        CONFIG_FILE="$2"
        shift 2
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      help)
        if [[ -n "${2:-}" ]]; then
          show_command_help "$2"
        else
          show_help
        fi
        exit 0
        ;;
      -*)
        die "Unknown global option: $1"
        ;;
      *)
        COMMAND="$1"
        shift
        COMMAND_ARGS=("$@")
        return 0
        ;;
    esac
  done

  if [[ "$PIPE_MODE" == "true" ]]; then
    COMMAND="init"
    COMMAND_ARGS=()
    return 0
  fi

  show_help
  exit 0
}

extract_common_args() {
  REMAINING_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ -n "${2:-}" ]] || die "Missing value for --config."
        CONFIG_FILE="$2"
        shift 2
        ;;
      --help|-h)
        show_command_help "$COMMAND"
        exit 0
        ;;
      *)
        REMAINING_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

config_arg() {
  printf '%s\n' "$(default_config)"
}

chown_for_sudo_user() {
  local path="$1"
  local sudo_home

  [[ "$EUID" -eq 0 && -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" && -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]] || return 0
  sudo_home="$(getent passwd "$SUDO_USER" | cut -d: -f6 || true)"
  [[ -n "$sudo_home" && "$path" == "$sudo_home"/.email-server* ]] || return 0
  chown "$SUDO_UID:$SUDO_GID" "$path"
}

install_cli_link() {
  local mode="${1:-interactive}"
  local link="$CLI_PATH"
  local source="$ROOT_DIR/mailserver.sh"
  local existing_source link_dir link_parent

  [[ -f "$source" ]] || die "Cannot install CLI because mailserver.sh is missing in $ROOT_DIR."
  chmod +x "$source"
  link_dir="$(dirname "$link")"
  link_parent="$(dirname "$link_dir")"

  if [[ -e "$link" && ! -L "$link" ]]; then
    if [[ "$mode" == "optional" ]]; then
      warn "Cannot install $link automatically because it already exists and is not a symlink."
      return 1
    fi
    die "$link already exists and is not a symlink."
  fi
  if [[ "$mode" == "optional" && -L "$link" ]]; then
    existing_source="$(resolve_script_path "$link" 2>/dev/null || true)"
    if [[ -n "$existing_source" && "$existing_source" != "$source" ]]; then
      warn "Cannot install $link automatically because it already points to $existing_source."
      return 1
    fi
  fi

  if [[ "$EUID" -eq 0 ]]; then
    mkdir -p "$link_dir"
    ln -sfn "$source" "$link"
  elif [[ -d "$link_dir" && -w "$link_dir" ]]; then
    ln -sfn "$source" "$link"
  elif [[ ! -e "$link_dir" && -d "$link_parent" && -w "$link_parent" ]]; then
    mkdir -p "$link_dir"
    ln -sfn "$source" "$link"
  elif [[ "$mode" == "interactive" ]] && command -v sudo >/dev/null 2>&1; then
    run_root_cmd mkdir -p "$link_dir"
    run_root_cmd ln -sfn "$source" "$link"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo mkdir -p "$link_dir"
    sudo ln -sfn "$source" "$link"
  else
    [[ "$mode" == "optional" ]] || die "Cannot write $link. Re-run with sudo or set MAILSERVER_CLI_PATH."
    warn "Could not install mailserver into PATH. Run $ROOT_DIR/mailserver.sh install-cli later."
    return 1
  fi

  ok "Installed CLI: $link -> $source"
}

bootstrap_checkout() {
  local dest="$INSTALL_DIR"

  command -v git >/dev/null 2>&1 || die "git is required for curl-pipe install. Install git, then retry."
  command -v mkdir >/dev/null 2>&1 || die "mkdir is required."

  if [[ -e "$dest/.git" ]]; then
    ok "Using existing installer checkout: $dest"
  elif [[ -e "$dest" && ! -d "$dest" ]]; then
    die "Install path exists and is not a directory: $dest"
  elif [[ -e "$dest" && -n "$(find "$dest" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    if [[ -f "$dest/mailserver.sh" ]]; then
      local backup
      backup="${dest}.non-git-backup.$(date -u +%Y%m%dT%H%M%SZ)"
      warn "Install directory is not a git checkout; moving it to $backup"
      mv "$dest" "$backup"
      say "Cloning installer into $dest"
      git clone "$REPO_URL" "$dest"
      ok "Previous installer directory kept at $backup"
    else
      die "Install directory exists and is not an email-server git checkout: $dest"
    fi
  else
    say "Cloning installer into $dest"
    mkdir -p "$(dirname "$dest")"
    git clone "$REPO_URL" "$dest"
  fi

  if [[ -n "$REPO_REF" ]]; then
    say "Checking out $REPO_REF"
    git -C "$dest" fetch --tags --prune
    git -C "$dest" checkout "$REPO_REF"
  fi

  [[ -x "$dest/mailserver.sh" ]] || chmod +x "$dest/mailserver.sh"
  ROOT_DIR="$dest"
  PIPE_MODE="false"
  ok "Installer ready: $dest"
  install_cli_link optional || true
}

require_checkout_files() {
  [[ "$PIPE_MODE" != "true" ]] || bootstrap_checkout
  [[ -f "$ROOT_DIR/install.sh" && -f "$ROOT_DIR/lib/common.sh" ]] || die "Installer checkout is incomplete: $ROOT_DIR"
}

run_cmd() {
  say "$(format_command "$@")"
  "$@"
}

run_root_cmd() {
  if [[ "$EUID" -eq 0 ]]; then
    say "$(format_command "$@")"
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    say "sudo $(format_command "$@")"
    sudo "$@"
  else
    die "This command needs root. Re-run with sudo."
  fi
}

has_tty() {
  [[ ( -t 0 || -t 1 || -t 2 ) && -r /dev/tty && -w /dev/tty ]]
}

prompt_tty() {
  local label="$1"
  local default="${2:-}"
  local reply

  has_tty || return 1
  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$label" "$default" > /dev/tty
  else
    printf '%s: ' "$label" > /dev/tty
  fi
  IFS= read -r reply < /dev/tty
  printf '%s\n' "${reply:-$default}"
}

say_tty() {
  local message="$*"
  if has_tty; then
    printf '%s %s\n' "$(color 36 "•")" "$message" > /dev/tty
  else
    say "$message"
  fi
}

is_public_ipv4() {
  local ip="$1"
  local a b c d
  local ai bi ci di

  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<< "$ip"
  ai=$((10#$a))
  bi=$((10#$b))
  ci=$((10#$c))
  di=$((10#$d))
  (( ai <= 255 && bi <= 255 && ci <= 255 && di <= 255 )) || return 1

  (( ai == 0 )) && return 1
  (( ai == 10 )) && return 1
  (( ai == 127 )) && return 1
  (( ai == 169 && bi == 254 )) && return 1
  (( ai == 172 && bi >= 16 && bi <= 31 )) && return 1
  (( ai == 192 && bi == 168 )) && return 1
  (( ai == 100 && bi >= 64 && bi <= 127 )) && return 1
  (( ai >= 224 )) && return 1

  return 0
}

detect_public_ipv4() {
  local ip

  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -o -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n 1 || true)"
    if is_public_ipv4 "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi

    ip="$(ip -o -4 addr show scope global 2>/dev/null | awk '{ split($4, a, "/"); print a[1] }' | while IFS= read -r candidate; do is_public_ipv4 "$candidate" && { printf "%s\n" "$candidate"; break; }; done || true)"
    if is_public_ipv4 "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  command -v curl >/dev/null 2>&1 || return 0
  curl -fsS --connect-timeout 2 --max-time 5 https://api.ipify.org 2>/dev/null || true
}

detect_timezone() {
  local zone=""

  if [[ -n "${TZ:-}" ]]; then
    zone="$TZ"
  elif command -v timedatectl >/dev/null 2>&1; then
    zone="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  fi

  if [[ -z "$zone" && -f /etc/timezone ]]; then
    zone="$(head -n 1 /etc/timezone)"
  fi

  if [[ -z "$zone" && -L /etc/localtime ]]; then
    zone="$(readlink /etc/localtime 2>/dev/null || true)"
    zone="${zone#/usr/share/zoneinfo/}"
  fi

  printf '%s\n' "${zone:-UTC}"
}

timezone_exists() {
  local zone="$1"
  [[ -n "$zone" && "$zone" != *".."* && -f "/usr/share/zoneinfo/$zone" ]]
}

validate_timezone_or_die() {
  local zone="$1"
  [[ -d /usr/share/zoneinfo ]] || return 0
  timezone_exists "$zone" || die "Invalid timezone: $zone. Use an IANA name like Europe/Prague."
}

available_timezones() {
  {
    printf '%s\n' "Europe/Prague" "UTC"
    if command -v timedatectl >/dev/null 2>&1; then
      timedatectl list-timezones 2>/dev/null || true
    elif [[ -f /usr/share/zoneinfo/zone1970.tab ]]; then
      awk 'NF && $1 !~ /^#/ { print $3 }' /usr/share/zoneinfo/zone1970.tab
    elif [[ -f /usr/share/zoneinfo/zone.tab ]]; then
      awk 'NF && $1 !~ /^#/ { print $3 }' /usr/share/zoneinfo/zone.tab
    fi
  } | awk 'NF && !seen[$0]++'
}

prompt_timezone_tty() {
  local default="$1"
  local reply
  local zones=()
  local selected
  local i

  has_tty || return 1
  mapfile -t zones < <(available_timezones)
  if [[ "${#zones[@]}" -eq 0 ]]; then
    zones=("Europe/Prague" "UTC")
  fi

  while true; do
    printf 'Server timezone:\n' > /dev/tty
    for i in "${!zones[@]}"; do
      printf '  %d) %s\n' "$((i + 1))" "${zones[$i]}" > /dev/tty
    done
    if [[ -n "$default" ]]; then
      printf '  Enter = %s, or type any IANA timezone like Europe/Berlin\n' "$default" > /dev/tty
    else
      printf '  Type any IANA timezone like Europe/Berlin\n' > /dev/tty
    fi
    printf 'Timezone choice [1-%d/%s]: ' "${#zones[@]}" "${default:-IANA timezone}" > /dev/tty
    IFS= read -r reply < /dev/tty
    reply="${reply:-$default}"

    if [[ "$reply" =~ ^[0-9]+$ && "$reply" -ge 1 && "$reply" -le "${#zones[@]}" ]]; then
      selected="${zones[$((reply - 1))]}"
    else
      selected="$reply"
    fi

    if [[ ! -d /usr/share/zoneinfo ]] || timezone_exists "$selected"; then
      printf '%s\n' "$selected"
      return 0
    fi

    printf 'Invalid timezone: %s. Use an IANA name like Europe/Prague.\n' "$selected" > /dev/tty
  done
}

config_value() {
  local value="$1"
  if [[ "$value" =~ ^[A-Za-z0-9_./:@%+=,-]*$ ]]; then
    printf '%s\n' "$value"
  else
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//\$/\\\$}"
    value="${value//\`/\\\`}"
    printf '"%s"\n' "$value"
  fi
}

set_config_entry() {
  local file="$1"
  local key="$2"
  local value
  value="$(config_value "$3")"
  sed -i "s|^$key=.*|$key=$value|" "$file"
}

cmd_init() {
  extract_common_args "$@"
  local domain=""
  local mail_hostname=""
  local admin_email=""
  local webmail_hostname=""
  local dav_hostname=""
  local public_ipv4=""
  local public_ipv6=""
  local timezone=""
  local non_interactive="false"
  local arg

  while [[ "${#REMAINING_ARGS[@]}" -gt 0 ]]; do
    arg="${REMAINING_ARGS[0]}"
    REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
    case "$arg" in
      --domain)
        [[ -n "${REMAINING_ARGS[0]:-}" ]] || die "Missing value for --domain."
        domain="${REMAINING_ARGS[0]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        ;;
      --mail-hostname)
        [[ -n "${REMAINING_ARGS[0]:-}" ]] || die "Missing value for --mail-hostname."
        mail_hostname="${REMAINING_ARGS[0]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        ;;
      --admin-email)
        [[ -n "${REMAINING_ARGS[0]:-}" ]] || die "Missing value for --admin-email."
        admin_email="${REMAINING_ARGS[0]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        ;;
      --webmail-hostname)
        [[ -n "${REMAINING_ARGS[0]:-}" ]] || die "Missing value for --webmail-hostname."
        webmail_hostname="${REMAINING_ARGS[0]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        ;;
      --dav-hostname)
        [[ -n "${REMAINING_ARGS[0]:-}" ]] || die "Missing value for --dav-hostname."
        dav_hostname="${REMAINING_ARGS[0]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        ;;
      --public-ipv4)
        [[ -n "${REMAINING_ARGS[0]:-}" ]] || die "Missing value for --public-ipv4."
        public_ipv4="${REMAINING_ARGS[0]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        ;;
      --public-ipv6)
        [[ -n "${REMAINING_ARGS[0]:-}" ]] || die "Missing value for --public-ipv6."
        public_ipv6="${REMAINING_ARGS[0]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        ;;
      --timezone)
        [[ -n "${REMAINING_ARGS[0]:-}" ]] || die "Missing value for --timezone."
        timezone="${REMAINING_ARGS[0]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        ;;
      --non-interactive)
        non_interactive="true"
        ;;
      *)
        die "Unknown init option: $arg"
        ;;
    esac
  done
  require_checkout_files

  local dest
  dest="$(config_arg)"
  if [[ -f "$dest" ]]; then
    ok "Config already exists: $dest"
    return 0
  fi

  if [[ "$non_interactive" != "true" && ( -z "$domain" || -z "$admin_email" || -z "$public_ipv4" ) ]]; then
    if has_tty; then
      say_tty "Collecting setup answers first. No network or install steps will run until prompts finish."
      domain="${domain:-$(prompt_tty "Primary mail domain" "${MAILSERVER_DOMAIN:-}")}"
      mail_hostname="${mail_hostname:-mail.$domain}"
      admin_email="${admin_email:-admin@$domain}"
      webmail_hostname="${webmail_hostname:-$mail_hostname}"
      dav_hostname="${dav_hostname:-dav.$domain}"
      timezone="${timezone:-$(detect_timezone)}"
      mail_hostname="$(prompt_tty "Mail hostname / MX target" "$mail_hostname")"
      admin_email="$(prompt_tty "Admin email for Let's Encrypt" "$admin_email")"
      webmail_hostname="$(prompt_tty "Webmail hostname" "$webmail_hostname")"
      dav_hostname="$(prompt_tty "CalDAV/CardDAV hostname" "$dav_hostname")"
      public_ipv4="$(prompt_tty "Server public IPv4, blank to auto-detect after prompts" "$public_ipv4")"
      public_ipv6="$(prompt_tty "Server public IPv6, optional" "$public_ipv6")"
      timezone="$(prompt_timezone_tty "$timezone")"
      say_tty "Setup answers collected."
    else
      warn "No interactive terminal available; created config with example values."
      warn "Re-run init with --domain, --admin-email, and --public-ipv4 to avoid editing the file manually."
    fi
  fi

  if [[ -n "$domain" ]]; then
    mail_hostname="${mail_hostname:-mail.$domain}"
    admin_email="${admin_email:-admin@$domain}"
    webmail_hostname="${webmail_hostname:-$mail_hostname}"
    dav_hostname="${dav_hostname:-dav.$domain}"
    timezone="${timezone:-$(detect_timezone)}"
    validate_timezone_or_die "$timezone"
    if [[ -z "$public_ipv4" ]]; then
      say "Detecting server IPv4 from Linux networking; external lookup is fallback, up to 5 seconds"
      public_ipv4="$(detect_public_ipv4)"
    fi
  fi

  say "Writing config: $dest"
  mkdir -p "$(dirname "$dest")"
  local config_tmp
  config_tmp="$(mktemp "$dest.tmp.XXXXXX")"
  cp "$ROOT_DIR/.env.example" "$config_tmp"

  if [[ -n "$domain" ]]; then
    set_config_entry "$config_tmp" "PRIMARY_DOMAIN" "$domain"
    set_config_entry "$config_tmp" "MAIL_HOSTNAME" "$mail_hostname"
    set_config_entry "$config_tmp" "ADMIN_EMAIL" "$admin_email"
    set_config_entry "$config_tmp" "WEBMAIL_HOSTNAME" "$webmail_hostname"
    set_config_entry "$config_tmp" "DAV_HOSTNAME" "$dav_hostname"
    set_config_entry "$config_tmp" "RADICALE_CALDAV_BASE_URL" "https://$dav_hostname/"
    set_config_entry "$config_tmp" "TIMEZONE" "$timezone"
    set_config_entry "$config_tmp" "POSTMASTER_ADDRESS" "postmaster@$domain"
    set_config_entry "$config_tmp" "ABUSE_ADDRESS" "abuse@$domain"
    set_config_entry "$config_tmp" "PRIMARY_MAILBOX" "$admin_email"
    set_config_entry "$config_tmp" "PRIMARY_ALIAS_ADDRESSES" "postmaster@$domain abuse@$domain dmarc@$domain $admin_email"
  fi
  [[ -n "$public_ipv4" ]] && set_config_entry "$config_tmp" "SERVER_PUBLIC_IPV4" "$public_ipv4"
  [[ -n "$public_ipv6" ]] && set_config_entry "$config_tmp" "SERVER_PUBLIC_IPV6" "$public_ipv6"

  chmod 600 "$config_tmp"
  mv "$config_tmp" "$dest"
  if [[ "$dest" == "$DEFAULT_CONFIG_FILE" ]]; then
    chmod 700 "$(dirname "$dest")"
    chown_for_sudo_user "$(dirname "$dest")"
    chown_for_sudo_user "$dest"
  fi
  ok "Created $dest."
  say "Next: mailserver doctor"
}

cmd_install_cli() {
  extract_common_args "$@"
  [[ "${#REMAINING_ARGS[@]}" -eq 0 ]] || die "install-cli does not accept positional arguments."
  require_checkout_files
  install_cli_link interactive
}

replace_non_git_checkout() {
  local parent backup

  command -v git >/dev/null 2>&1 || die "git is required to repair installer checkout. Install git, then retry."

  parent="$(dirname "$ROOT_DIR")"
  if [[ "$EUID" -ne 0 && ( ! -w "$parent" || ! -w "$ROOT_DIR" ) ]]; then
    die "Update needs write access to $ROOT_DIR. Re-run: sudo mailserver update"
  fi

  backup="${ROOT_DIR}.non-git-backup.$(date -u +%Y%m%dT%H%M%SZ)"
  warn "$ROOT_DIR is not a git checkout; moving it to $backup and cloning a fresh installer checkout."
  mv "$ROOT_DIR" "$backup"
  if ! git clone "$REPO_URL" "$ROOT_DIR"; then
    mv "$backup" "$ROOT_DIR" 2>/dev/null || true
    die "Could not clone $REPO_URL into $ROOT_DIR. Restored previous installer directory."
  fi
  if [[ -n "$REPO_REF" ]]; then
    say "Checking out $REPO_REF"
    git -C "$ROOT_DIR" fetch --tags --prune
    git -C "$ROOT_DIR" checkout "$REPO_REF"
  fi
  [[ -x "$ROOT_DIR/mailserver.sh" ]] || chmod +x "$ROOT_DIR/mailserver.sh"
  install_cli_link optional || true
  ok "Repaired installer checkout. Previous directory kept at $backup"
}

cmd_update() {
  extract_common_args "$@"
  [[ "${#REMAINING_ARGS[@]}" -eq 0 ]] || die "update does not accept positional arguments."
  require_checkout_files

  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    replace_non_git_checkout
  fi

  local worktree branch upstream
  worktree="$(git -C "$ROOT_DIR" rev-parse --show-toplevel)"
  if [[ -n "$(git -C "$worktree" status --porcelain)" ]]; then
    die "Working tree has uncommitted changes. Commit or stash them before updating."
  fi

  branch="$(git -C "$worktree" branch --show-current)"
  [[ -n "$branch" ]] || die "Cannot update a detached HEAD checkout."

  say "Fetching git remote updates"
  git -C "$worktree" fetch --prune

  if upstream="$(git -C "$worktree" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
    say "Fast-forwarding $branch from $upstream"
    git -C "$worktree" pull --ff-only
  elif git -C "$worktree" rev-parse --verify --quiet "origin/$branch" >/dev/null; then
    say "Fast-forwarding $branch from origin/$branch"
    git -C "$worktree" merge --ff-only "origin/$branch"
  else
    die "No upstream found for branch $branch."
  fi

  install_cli_link optional || true
  ok "Installer checkout is up to date."
}

cmd_doctor() {
  extract_common_args "$@"
  [[ "${#REMAINING_ARGS[@]}" -eq 0 ]] || die "doctor does not accept positional arguments."
  require_checkout_files
  run_cmd "$ROOT_DIR/doctor.sh" --config "$(config_arg)"
}

cmd_dry_run() {
  extract_common_args "$@"
  [[ "${#REMAINING_ARGS[@]}" -eq 0 ]] || die "dry-run does not accept positional arguments."
  require_checkout_files
  run_root_cmd "$ROOT_DIR/install.sh" --config "$(config_arg)" --dry-run --assume-yes
}

cmd_install() {
  extract_common_args "$@"
  [[ "${#REMAINING_ARGS[@]}" -eq 0 ]] || die "install does not accept positional arguments."
  require_checkout_files
  run_root_cmd "$ROOT_DIR/install.sh" --config "$(config_arg)" --assume-yes
}

cmd_setup_dry_run() {
  extract_common_args "$@"
  [[ "${#REMAINING_ARGS[@]}" -eq 0 ]] || die "setup-dry-run does not accept positional arguments."
  require_checkout_files
  local config
  config="$(config_arg)"
  run_cmd "$ROOT_DIR/doctor.sh" --config "$config"
  run_root_cmd "$ROOT_DIR/install.sh" --config "$config" --dry-run --assume-yes
  run_cmd "$ROOT_DIR/scripts/print-dns.sh" --config "$config"
}

cmd_setup() {
  extract_common_args "$@"
  [[ "${#REMAINING_ARGS[@]}" -eq 0 ]] || die "setup does not accept positional arguments."
  require_checkout_files
  local config
  config="$(config_arg)"
  run_cmd "$ROOT_DIR/doctor.sh" --config "$config"
  run_root_cmd "$ROOT_DIR/install.sh" --config "$config" --assume-yes
  run_root_cmd "$ROOT_DIR/verify.sh" --config "$config"
  run_root_cmd "$ROOT_DIR/scripts/print-dns.sh" --config "$config"
}

cmd_verify() {
  extract_common_args "$@"
  [[ "${#REMAINING_ARGS[@]}" -eq 0 ]] || die "verify does not accept positional arguments."
  require_checkout_files
  run_root_cmd "$ROOT_DIR/verify.sh" --config "$(config_arg)"
}

cmd_check() {
  extract_common_args "$@"
  [[ "${#REMAINING_ARGS[@]}" -eq 0 ]] || die "check does not accept positional arguments."
  require_checkout_files
  local config status
  config="$(config_arg)"
  status=0
  "$ROOT_DIR/scripts/dns-state.sh" --config "$config" || status=$?
  printf '\n'
  "$ROOT_DIR/scripts/check-ssl.sh" --config "$config" || status=$?
  printf '\n'
  "$ROOT_DIR/scripts/service-state.sh" --config "$config" || status=$?
  return "$status"
}

cmd_simple_script() {
  local script="$1"
  local root_needed="$2"
  shift 2
  extract_common_args "$@"
  [[ "${#REMAINING_ARGS[@]}" -eq 0 ]] || die "$COMMAND does not accept positional arguments."
  require_checkout_files
  if [[ "$root_needed" == "true" ]]; then
    run_root_cmd "$ROOT_DIR/$script" --config "$(config_arg)"
  else
    run_cmd "$ROOT_DIR/$script" --config "$(config_arg)"
  fi
}

cmd_client_info() {
  extract_common_args "$@"
  require_checkout_files
  local user=""
  local args=()

  while [[ "${#REMAINING_ARGS[@]}" -gt 0 ]]; do
    case "${REMAINING_ARGS[0]}" in
      --user)
        [[ -n "${REMAINING_ARGS[1]:-}" ]] || die "Missing value for --user."
        user="${REMAINING_ARGS[1]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
        ;;
      *)
        die "Unknown client-info option: ${REMAINING_ARGS[0]}"
        ;;
    esac
  done

  args=(--config "$(config_arg)")
  [[ -z "$user" ]] || args+=(--user "$user")
  run_cmd "$ROOT_DIR/scripts/print-client-config.sh" "${args[@]}"
}

cmd_user_arg() {
  local script="$1"
  shift
  extract_common_args "$@"
  require_checkout_files
  local user=""
  local full_name=""

  while [[ "${#REMAINING_ARGS[@]}" -gt 0 ]]; do
    case "${REMAINING_ARGS[0]}" in
      --user)
        [[ -n "${REMAINING_ARGS[1]:-}" ]] || die "Missing value for --user."
        user="${REMAINING_ARGS[1]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
        ;;
      --full-name)
        [[ -n "${REMAINING_ARGS[1]:-}" ]] || die "Missing value for --full-name."
        full_name="${REMAINING_ARGS[1]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
        ;;
      *)
        if [[ -z "$user" ]]; then
          user="${REMAINING_ARGS[0]}"
          REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        elif [[ "$script" == "scripts/add-user.sh" && -z "$full_name" ]]; then
          full_name="${REMAINING_ARGS[0]}"
          REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        else
          die "Unexpected argument: ${REMAINING_ARGS[0]}"
        fi
        ;;
    esac
  done

  [[ -n "$user" ]] || die "Missing --user user@example.com."
  if [[ "$script" == "scripts/add-user.sh" && -n "$full_name" ]]; then
    run_root_cmd "$ROOT_DIR/$script" --config "$(config_arg)" "$user" "$full_name"
  else
    run_root_cmd "$ROOT_DIR/$script" --config "$(config_arg)" "$user"
  fi
}

cmd_add_alias() {
  extract_common_args "$@"
  require_checkout_files
  local source_addr=""
  local dest_addr=""

  while [[ "${#REMAINING_ARGS[@]}" -gt 0 ]]; do
    case "${REMAINING_ARGS[0]}" in
      --source)
        [[ -n "${REMAINING_ARGS[1]:-}" ]] || die "Missing value for --source."
        source_addr="${REMAINING_ARGS[1]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
        ;;
      --dest|--destination)
        [[ -n "${REMAINING_ARGS[1]:-}" ]] || die "Missing value for --dest."
        dest_addr="${REMAINING_ARGS[1]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
        ;;
      *)
        if [[ -z "$source_addr" ]]; then
          source_addr="${REMAINING_ARGS[0]}"
          REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        elif [[ -z "$dest_addr" ]]; then
          dest_addr="${REMAINING_ARGS[0]}"
          REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        else
          die "Unexpected argument: ${REMAINING_ARGS[0]}"
        fi
        ;;
    esac
  done

  [[ -n "$source_addr" ]] || die "Missing --source source@example.com."
  [[ -n "$dest_addr" ]] || die "Missing --dest dest@example.com."
  run_root_cmd "$ROOT_DIR/scripts/add-alias.sh" --config "$(config_arg)" "$source_addr" "$dest_addr"
}

main() {
  parse_global_args "$@"
  case "$COMMAND" in
    init) cmd_init "${COMMAND_ARGS[@]}" ;;
    install-cli) cmd_install_cli "${COMMAND_ARGS[@]}" ;;
    update) cmd_update "${COMMAND_ARGS[@]}" ;;
    doctor) cmd_doctor "${COMMAND_ARGS[@]}" ;;
    dry-run) cmd_dry_run "${COMMAND_ARGS[@]}" ;;
    install) cmd_install "${COMMAND_ARGS[@]}" ;;
    setup-dry-run) cmd_setup_dry_run "${COMMAND_ARGS[@]}" ;;
    setup) cmd_setup "${COMMAND_ARGS[@]}" ;;
    verify) cmd_verify "${COMMAND_ARGS[@]}" ;;
    check) cmd_check "${COMMAND_ARGS[@]}" ;;
    print-dns) cmd_simple_script scripts/print-dns.sh true "${COMMAND_ARGS[@]}" ;;
    dns-state) cmd_simple_script scripts/dns-state.sh false "${COMMAND_ARGS[@]}" ;;
    check-ssl) cmd_simple_script scripts/check-ssl.sh false "${COMMAND_ARGS[@]}" ;;
    service-state) cmd_simple_script scripts/service-state.sh false "${COMMAND_ARGS[@]}" ;;
    list-users) cmd_simple_script scripts/list-users.sh true "${COMMAND_ARGS[@]}" ;;
    setup-primary-mailbox) cmd_simple_script scripts/setup-primary-mailbox.sh true "${COMMAND_ARGS[@]}" ;;
    backup) cmd_simple_script scripts/backup.sh true "${COMMAND_ARGS[@]}" ;;
    install-backup-cron) cmd_simple_script scripts/install-backup-cron.sh true "${COMMAND_ARGS[@]}" ;;
    client-info|client-config) cmd_client_info "${COMMAND_ARGS[@]}" ;;
    add-user) cmd_user_arg scripts/add-user.sh "${COMMAND_ARGS[@]}" ;;
    remove-user) cmd_user_arg scripts/remove-user.sh "${COMMAND_ARGS[@]}" ;;
    change-password) cmd_user_arg scripts/change-password.sh "${COMMAND_ARGS[@]}" ;;
    add-alias) cmd_add_alias "${COMMAND_ARGS[@]}" ;;
    *)
      die "Unknown command: $COMMAND. Run mailserver help."
      ;;
  esac
}

main "$@"
