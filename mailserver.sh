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
CONFIG_DIR="${MAILSERVER_CONFIG_DIR:-$(config_home)/.mail-server}"
DEFAULT_CONFIG_FILE="$CONFIG_DIR/config.env"
CLI_PATH="${MAILSERVER_CLI_PATH:-/usr/local/bin/mailserver}"
REPO_URL="${MAILSERVER_REPO_URL:-https://github.com/zdehasek/mail-server.git}"
REPO_REF="${MAILSERVER_REF:-}"
COMMAND=""
COMMAND_ARGS=()

use_color() {
  [[ -n "${FORCE_COLOR:-}" && "${FORCE_COLOR:-}" != "0" ]] && return 0
  [[ -n "${CLICOLOR_FORCE:-}" && "${CLICOLOR_FORCE:-}" != "0" ]] && return 0
  [[ -n "${NO_COLOR:-}" ]] && return 1
  [[ ( -t 1 || -t 2 ) && "${TERM:-}" != "dumb" ]]
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
  printf '%s\n' "$(color 36 "🔹 $*")"
}

ok() {
  printf '%s\n' "$(color 32 "✅ $*")"
}

usage_line() {
  printf '%s\n' "$(color 36 "$*")"
}

warn() {
  printf '%s\n' "$(color "38;5;208" "⚠️ $*")" >&2
}

die() {
  printf '%s\n' "$(color 31 "❌ $*")" >&2
  exit 1
}

normalize_domain() {
  local domain="$1"
  printf '%s\n' "${domain,,}"
}

validate_domain_or_die() {
  local domain="$1"
  [[ "$domain" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ && "$domain" == *.* && "$domain" != *..* ]] || die "Invalid domain: $domain"
}

is_valid_domain() {
  local domain="$1"
  [[ "$domain" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ && "$domain" == *.* && "$domain" != *..* ]]
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
  mailserver RESOURCE ACTION [OPTIONS]
  curl -fsSL https://raw.githubusercontent.com/zdehasek/mail-server/master/mailserver.sh | sudo bash

Setup:
  init                         Guided setup: config, DNS checks, install, verify
  init --config-only           Create ~/.mail-server/config.env only
  reset-setup                  Move local setup config aside
  remove --purge               Permanently delete services, databases, config, and mail data
  install-cli                  Install mailserver into PATH
  doctor [--fix]               Validate prerequisites, DNS, TLS, services, and config drift
  setup-dry-run                Run doctor, dry-run install, and DNS output
  dry-run                      Show install actions without applying them
  install                      Install on this server
  setup                        Run doctor, install, verify, and DNS output
  update                       Update this installer checkout from git

Health checks:
  verify                       Check local configs and active services
  dns-state                    Check A/AAAA, MX, SPF, DMARC, PTR, DKIM
  check-ssl                    Check HTTPS, IMAPS, and SMTP TLS certs
  service-state                Check services, ports, and web endpoints
  config-drift [--fix]         Compare or repair live SOGo/autoconfig files
  e2e-delivery                 Inject local test mail, fetch via IMAP, check SOGo DAV
  tls-policy-state             Check MTA-STS, TLS reporting, and DANE DNS state
  rspamd-state                 Show Rspamd controller status or counters
  print-dns                    Print DNS records, including generated DKIM
  apply-cloudflare-dns         Create or update DNS records through Cloudflare API

Client configuration:
  client-info                  Print Apple Mail, Thunderbird, and CalDAV settings
  client-info --user user@example.com

Mailbox operations:
  domains ls
  domains set --domain example.com
  domains add --domain example.com
  domains rm --domain example.com
  aliases ls [--domain example.com]
  forwards ls [--domain example.com]
  users ls
  users add --user user@example.com [--full-name "Full Name"]
  users rm --user user@example.com
  setup-primary-mailbox
  aliases add --source postmaster@example.com --dest user@example.com
  aliases set --source postmaster@example.com --dest user@example.com
  forwards add --source user@example.com --dest user@example.net [--allow-mailbox-source]
  users passwd --user user@example.com

Backup:
  backup
  restore --list|--inspect ARCHIVE|--validate ARCHIVE|--extract ARCHIVE --target DIR
  install-backup-cron

Examples:
  mailserver init
  mailserver init --config-only
  mailserver reset-setup
  sudo mailserver remove --purge
  mailserver doctor
  mailserver setup-dry-run
  sudo mailserver apply-cloudflare-dns
  sudo mailserver install
  sudo mailserver domains ls
  sudo mailserver users add --user user@example.com
  sudo mailserver aliases ls --domain example.com
  sudo mailserver forwards add --source user@example.com --dest user@example.net --allow-mailbox-source
  mailserver client-info --user user@example.com
  ./mailserver.sh doctor --config .env.example
  curl -fsSL https://raw.githubusercontent.com/zdehasek/mail-server/master/mailserver.sh | sudo bash
  curl -fsSL https://raw.githubusercontent.com/zdehasek/mail-server/master/mailserver.sh | sudo MAILSERVER_INSTALL_DIR=/opt/mailserver bash -s -- setup-dry-run

Notes:
  The default config is ~/.mail-server/config.env. When run through sudo,
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
      usage_line 'Usage: mailserver users add --user user@example.com [--full-name "Full Name"] [--config PATH]'
      ;;
    add-domain)
      usage_line 'Usage: mailserver domains add --domain example.com [--alias-dest admin@example.com] [--no-default-aliases] [--config PATH]'
      ;;
    set-domain)
      usage_line 'Usage: mailserver domains set --domain example.com [--admin-email admin@example.com] [--primary-mailbox admin@example.com] [--mail-hostname mail.example.com] [--webmail-hostname mail.example.com] [--dav-hostname dav.example.com] [--config PATH]'
      ;;
    remove-domain)
      usage_line 'Usage: mailserver domains rm --domain example.com [--config PATH]'
      ;;
    remove)
      usage_line 'Usage: sudo mailserver remove --purge [--config PATH] [--dry-run]'
      ;;
    doctor)
      usage_line 'Usage: mailserver doctor [--fix] [--config PATH]'
      ;;
    print-dns|dns-state)
      usage_line "Usage: mailserver $1 [--domain example.com] [--skip-dkim] [--skip-ptr] [--config PATH]"
      ;;
    apply-cloudflare-dns)
      usage_line 'Usage: sudo mailserver apply-cloudflare-dns [--domain example.com] [--zone-id ID] [--token TOKEN|--token-file PATH] [--dry-run] [--config PATH]'
      ;;
    config-drift)
      usage_line 'Usage: sudo mailserver config-drift [--fix] [--config PATH]'
      ;;
    e2e-delivery)
      usage_line 'Usage: mailserver e2e-delivery [--user user@example.com] [--password-file PATH] [--no-cleanup] [--config PATH]'
      ;;
    tls-policy-state)
      usage_line 'Usage: mailserver tls-policy-state [--domain example.com] [--config PATH]'
      ;;
    rspamd-state)
      usage_line 'Usage: mailserver rspamd-state [status|counters|commands] [--config PATH]'
      ;;
    list-domains)
      usage_line 'Usage: mailserver domains ls [--config PATH]'
      ;;
    list-aliases)
      usage_line 'Usage: mailserver aliases ls [--domain example.com] [--config PATH]'
      ;;
    list-forwards)
      usage_line 'Usage: mailserver forwards ls [--domain example.com] [--config PATH]'
      ;;
    list-users)
      usage_line 'Usage: mailserver users ls [--config PATH]'
      ;;
    remove-user)
      usage_line 'Usage: mailserver users rm --user user@example.com [--config PATH]'
      ;;
    change-password)
      usage_line 'Usage: mailserver users passwd --user user@example.com [--config PATH]'
      ;;
    add-alias)
      usage_line 'Usage: mailserver aliases add --source source@example.com --dest dest@example.com [--config PATH]'
      ;;
    set-alias)
      usage_line 'Usage: mailserver aliases set --source source@example.com --dest dest@example.com [--config PATH]'
      ;;
    add-forward)
      usage_line 'Usage: mailserver forwards add --source mailbox@example.com --dest dest@example.com [--allow-mailbox-source] [--config PATH]'
      ;;
    client-info)
      usage_line 'Usage: mailserver client-info [--user user@example.com] [--config PATH]'
      ;;
    restore)
      usage_line 'Usage: mailserver restore --list|--inspect ARCHIVE|--validate ARCHIVE|--extract ARCHIVE --target DIR [--config PATH]'
      ;;
    init)
      usage_line 'Usage: mailserver init [--config-only] [--domain DOMAIN] [--admin-email EMAIL] [--mail-hostname HOST] [--webmail-hostname HOST] [--dav-hostname HOST] [--public-ipv4 IP] [--public-ipv6 IP] [--timezone TZ] [--non-interactive] [--config PATH]'
      ;;
    reset-setup)
      usage_line 'Usage: mailserver reset-setup [--yes] [--config PATH]'
      ;;
    install-cli)
      usage_line 'Usage: mailserver install-cli'
      ;;
    update)
      usage_line 'Usage: mailserver update'
      ;;
    *)
      show_help
      ;;
  esac
}

show_resource_help() {
  case "$1" in
    domain|domains)
      usage_line 'Usage: mailserver domains ls|add|rm|set [OPTIONS]'
      ;;
    user|users)
      usage_line 'Usage: mailserver users ls|add|rm|passwd [OPTIONS]'
      ;;
    alias|aliases)
      usage_line 'Usage: mailserver aliases ls|add|set [OPTIONS]'
      ;;
    forward|forwards)
      usage_line 'Usage: mailserver forwards ls|add [OPTIONS]'
      ;;
    *)
      show_help
      ;;
  esac
}

show_command_help_for_args() {
  local saved_command="$COMMAND"
  local saved_args=("${COMMAND_ARGS[@]}")

  if [[ $# -eq 0 ]]; then
    show_help
    return 0
  fi

  COMMAND="$1"
  shift
  COMMAND_ARGS=("$@")
  if [[ "${#COMMAND_ARGS[@]}" -eq 0 ]]; then
    case "$COMMAND" in
      domain|domains|user|users|alias|aliases|forward|forwards)
        show_resource_help "$COMMAND"
        COMMAND="$saved_command"
        COMMAND_ARGS=("${saved_args[@]}")
        return 0
        ;;
    esac
  fi
  normalize_command
  show_command_help "$COMMAND"

  COMMAND="$saved_command"
  COMMAND_ARGS=("${saved_args[@]}")
}

normalize_command() {
  local resource="$COMMAND"
  local action="${COMMAND_ARGS[0]:-}"

  case "$resource" in
    list-domains)
      die "Use: mailserver domains ls"
      ;;
    add-domain)
      die "Use: mailserver domains add --domain example.com"
      ;;
    remove-domain)
      die "Use: mailserver domains rm --domain example.com"
      ;;
    set-domain)
      die "Use: mailserver domains set --domain example.com"
      ;;
    list-users)
      die "Use: mailserver users ls"
      ;;
    add-user)
      die "Use: mailserver users add --user user@example.com"
      ;;
    remove-user)
      die "Use: mailserver users rm --user user@example.com"
      ;;
    change-password)
      die "Use: mailserver users passwd --user user@example.com"
      ;;
    list-aliases)
      die "Use: mailserver aliases ls"
      ;;
    add-alias)
      die "Use: mailserver aliases add --source source@example.com --dest dest@example.com"
      ;;
    set-alias)
      die "Use: mailserver aliases set --source source@example.com --dest dest@example.com"
      ;;
    list-forwards)
      die "Use: mailserver forwards ls"
      ;;
    add-forward)
      die "Use: mailserver forwards add --source source@example.com --dest dest@example.com"
      ;;
    client-config)
      die "Use: mailserver client-info"
      ;;
    check)
      die "Use: mailserver doctor"
      ;;
    delete-setup|remove-setup)
      COMMAND="reset-setup"
      ;;
    domain|domains)
      [[ -n "$action" ]] || { show_resource_help "$resource"; exit 0; }
      COMMAND_ARGS=("${COMMAND_ARGS[@]:1}")
      case "$action" in
        ls) COMMAND="list-domains" ;;
        add) COMMAND="add-domain" ;;
        rm) COMMAND="remove-domain" ;;
        set) COMMAND="set-domain" ;;
        help|--help|-h)
          show_command_help list-domains
          exit 0
          ;;
        *) die "Unknown domains action: $action. Use: ls, add, rm, or set." ;;
      esac
      ;;
    user|users)
      [[ -n "$action" ]] || { show_resource_help "$resource"; exit 0; }
      COMMAND_ARGS=("${COMMAND_ARGS[@]:1}")
      case "$action" in
        ls) COMMAND="list-users" ;;
        add) COMMAND="add-user" ;;
        rm) COMMAND="remove-user" ;;
        passwd) COMMAND="change-password" ;;
        help|--help|-h)
          show_command_help list-users
          exit 0
          ;;
        *) die "Unknown users action: $action. Use: ls, add, rm, or passwd." ;;
      esac
      ;;
    alias|aliases)
      [[ -n "$action" ]] || { show_resource_help "$resource"; exit 0; }
      COMMAND_ARGS=("${COMMAND_ARGS[@]:1}")
      case "$action" in
        ls) COMMAND="list-aliases" ;;
        add) COMMAND="add-alias" ;;
        set) COMMAND="set-alias" ;;
        help|--help|-h)
          show_command_help list-aliases
          exit 0
          ;;
        *) die "Unknown aliases action: $action. Use: ls, add, or set." ;;
      esac
      ;;
    forward|forwards)
      [[ -n "$action" ]] || { show_resource_help "$resource"; exit 0; }
      COMMAND_ARGS=("${COMMAND_ARGS[@]:1}")
      case "$action" in
        ls) COMMAND="list-forwards" ;;
        add) COMMAND="add-forward" ;;
        help|--help|-h)
          show_command_help list-forwards
          exit 0
          ;;
        *) die "Unknown forwards action: $action. Use: ls or add." ;;
      esac
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
          shift
          show_command_help_for_args "$@"
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
  [[ -n "$sudo_home" && "$path" == "$sudo_home"/.mail-server* ]] || return 0
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
      die "Install directory exists and is not a mail-server git checkout: $dest"
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
  if use_color; then
    FORCE_COLOR="${FORCE_COLOR:-1}" CLICOLOR_FORCE="${CLICOLOR_FORCE:-1}" "$@"
  else
    "$@"
  fi
}

run_root_cmd() {
  if [[ "$EUID" -eq 0 ]]; then
    say "$(format_command "$@")"
    if use_color; then
      FORCE_COLOR="${FORCE_COLOR:-1}" CLICOLOR_FORCE="${CLICOLOR_FORCE:-1}" "$@"
    else
      "$@"
    fi
  elif command -v sudo >/dev/null 2>&1; then
    say "sudo $(format_command "$@")"
    if use_color; then
      sudo env FORCE_COLOR="${FORCE_COLOR:-1}" CLICOLOR_FORCE="${CLICOLOR_FORCE:-1}" "$@"
    else
      sudo "$@"
    fi
  else
    die "This command needs root. Re-run with sudo."
  fi
}

has_tty() {
  [[ ( -t 0 || -t 1 || -t 2 ) && -r /dev/tty && -w /dev/tty ]]
}

terminal_width() {
  local cols
  cols="${COLUMNS:-}"
  if [[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ ]]; then
    cols="$(tput cols 2>/dev/null || printf '80')"
  fi
  (( cols < 40 )) && cols=40
  (( cols > 110 )) && cols=110
  printf '%s\n' "$cols"
}

screen_line() {
  local char="${1:--}"
  local width
  width="$(terminal_width)"
  printf '%*s\n' "$width" '' | tr ' ' "$char"
}

wizard_clear() {
  has_tty || return 0
  printf '\033[H\033[2J' > /dev/tty
}

wizard_write() {
  if has_tty; then
    printf '%b\n' "$*" > /dev/tty
  else
    printf '%b\n' "$*"
  fi
}

wizard_header() {
  local step="$1"
  local title="$2"
  local log_file="${3:-}"

  wizard_clear
  wizard_write "$(color 36 "Mail server setup")"
  screen_line "-" | while IFS= read -r line; do wizard_write "$line"; done
  wizard_write "$(color 1 "Step $step: $title")"
  if [[ -n "$log_file" ]]; then
    wizard_write "$(color "2" "Detailed output is saved to: $log_file")"
  fi
  wizard_write ""
}

wizard_note() {
  local message="$1"
  wizard_write "$(color 36 "›") $message"
}

wizard_success() {
  local message="$1"
  wizard_write "$(color 32 "✓") $message"
}

wizard_problem() {
  local message="$1"
  wizard_write "$(color 31 "!") $message"
}

wizard_record_color_code() {
  local line="$1"

  if [[ "$line" =~ ^[[:alnum:]_.-]+\.\ (MX|A|AAAA|TXT|CAA|CNAME|TLSA)\  ]]; then
    printf '%s\n' "1;36"
  elif [[ "$line" =~ ^[[:alnum:]_.-]+[[:space:]]+IN[[:space:]]+TXT ]]; then
    printf '%s\n' "1;36"
  elif [[ "$line" =~ ^[0-9a-fA-F:.]+\ -\>\  ]]; then
    printf '%s\n' "1;36"
  elif [[ "$line" == "Publish these DNS records:" || "$line" == "DKIM record:" || "$line" == "DKIM record generated by OpenDKIM:" || "$line" == "DKIM record generated locally:" || "$line" == "Recommended TLS policy DNS records:" || "$line" == "Provider PTR/rDNS must be:" ]]; then
    printf '%s\n' "1"
  elif [[ "$line" == DKIM\ record\ is\ not\ generated\ yet* || "$line" == "  Skipped by --skip-dkim."* ]]; then
    printf '%s\n' "38;5;208"
  elif [[ "$line" == Expected\ name* || "$line" == "  Expected name:"* ]]; then
    printf '%s\n' "36"
  fi
}

wizard_record_write_line() {
  local line="$1"
  local color_code="${2:-}"

  if [[ -n "$color_code" ]]; then
    wizard_write "$(color "$color_code" "$line")"
  else
    wizard_write "$line"
  fi
}

wizard_dns_record_key() {
  local line="$1"
  line="$(sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g; s/[[:space:]]+/ /g; s/^ //; s/ $//' <<< "$line")"
  printf '%s\n' "$line"
}

wizard_dns_status_icon() {
  local status="$1"

  case "$status" in
    ok) color 32 "✅ OK    " ;;
    fail) color 31 "❌ missing" ;;
    different) color 31 "❌ different" ;;
    warn) color "38;5;208" "⚠ warn   " ;;
    *) printf '         ' ;;
  esac
}

wizard_dns_status_key_from_line() {
  local line="$1"
  local message expected

  if [[ "$line" == *"OK    "* ]]; then
    message="${line#*OK    }"
  elif [[ "$line" == *"FAIL  "* ]]; then
    message="${line#*FAIL  }"
    if [[ "$message" == *" expected: "* ]]; then
      expected="${message#* expected: }"
      expected="${expected%; got:*}"
      wizard_dns_record_key "$expected"
      return 0
    fi
  elif [[ "$line" == *"WARN  "* ]]; then
    message="${line#*WARN  }"
    if [[ "$message" == *" expected: "* ]]; then
      expected="${message#* expected: }"
      expected="${expected%; got:*}"
      wizard_dns_record_key "$expected"
      return 0
    fi
  else
    return 1
  fi

  if [[ "$message" == PTR/rDNS\ * ]]; then
    message="${message#PTR/rDNS }"
  fi
  wizard_dns_record_key "$message"
}

wizard_dns_status_from_line() {
  local line="$1"

  if [[ "$line" == *"OK    "* ]]; then
    printf '%s\n' "ok"
  elif [[ "$line" == *"FAIL  "* ]]; then
    if [[ "$line" == *" got: <none>"* ]]; then
      printf '%s\n' "fail"
    else
      printf '%s\n' "different"
    fi
  elif [[ "$line" == *"WARN  "* ]]; then
    printf '%s\n' "warn"
  else
    return 1
  fi
}

wizard_dns_statuses_from_output() {
  local dns_output="$1"
  local line status key

  WIZARD_DNS_RECORD_STATUS=()
  while IFS= read -r line; do
    status="$(wizard_dns_status_from_line "$line" || true)"
    [[ -n "$status" ]] || continue
    key="$(wizard_dns_status_key_from_line "$line" || true)"
    [[ -n "$key" ]] || continue
    WIZARD_DNS_RECORD_STATUS["$key"]="$status"
  done <<< "$dns_output"
}

wizard_records() {
  local text="$1"
  local dns_output="${2:-}"
  local color_code status status_icon line_to_write key
  declare -gA WIZARD_DNS_RECORD_STATUS
  if [[ -n "$dns_output" ]]; then
    wizard_dns_statuses_from_output "$dns_output"
  else
    WIZARD_DNS_RECORD_STATUS=()
  fi

  wizard_write "$(color 1 "Records to publish")"
  screen_line "-" | while IFS= read -r line; do wizard_write "$line"; done
  while IFS= read -r line; do
    color_code="$(wizard_record_color_code "$line")"
    key="$(wizard_dns_record_key "$line")"
    status=""
    if [[ -n "$key" ]]; then
      status="${WIZARD_DNS_RECORD_STATUS[$key]:-}"
    fi
    if [[ -n "$status" ]]; then
      status_icon="$(wizard_dns_status_icon "$status")"
      line_to_write="$status_icon $line"
    else
      line_to_write="$line"
    fi
    wizard_record_write_line "$line_to_write" "$color_code"
  done <<< "$text"
  screen_line "-" | while IFS= read -r line; do wizard_write "$line"; done
}

wizard_log_file() {
  local dir
  dir="${MAILSERVER_WIZARD_LOG_DIR:-${TMPDIR:-/tmp}}"
  mkdir -p "$dir"
  mktemp "$dir/mailserver-init.XXXXXX.log"
}

wizard_last_command_output() {
  local log_file="$1"
  awk '
    /^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\] / {
      output = ""
      next
    }
    {
      output = output $0 "\n"
    }
    END {
      printf "%s", output
    }
  ' "$log_file"
}

wizard_failure_excerpt() {
  local log_file="$1"
  local relevant

  relevant="$(
    wizard_last_command_output "$log_file" |
      grep -E 'FAIL[[:space:]]|ERROR|WARN[[:space:]]|❌|⚠️' |
      tail -n 20 || true
  )"

  if [[ -n "$relevant" ]]; then
    wizard_write "Relevant failure lines:"
    while IFS= read -r line; do wizard_write "  $line"; done <<< "$relevant"
  else
    wizard_write "Last log lines:"
    tail -n 14 "$log_file" | sed 's/^/  /' | while IFS= read -r line; do wizard_write "$line"; done
  fi
}

wizard_run_cmd() {
  local label="$1"
  local log_file="$2"
  local status
  local retry_command
  shift 2

  retry_command="$(format_command "$@")"
  wizard_note "$label"
  set +e
  printf '\n[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$retry_command" >> "$log_file"
  if use_color; then
    FORCE_COLOR="${FORCE_COLOR:-1}" CLICOLOR_FORCE="${CLICOLOR_FORCE:-1}" "$@" 2>&1 | tee -a "$log_file"
  else
    "$@" 2>&1 | tee -a "$log_file"
  fi
  status=${PIPESTATUS[0]}
  set -e
  if [[ "$status" -eq 0 ]]; then
    wizard_success "$label finished"
    return 0
  fi

  wizard_problem "$label failed."
  wizard_failure_excerpt "$log_file"
  wizard_write ""
  wizard_write "Next: fix the failures above, then rerun: $retry_command"
  wizard_write "Full log: $log_file"
  return "$status"
}

wizard_run_root_cmd() {
  local label="$1"
  local log_file="$2"
  shift 2

  if [[ "$EUID" -eq 0 ]]; then
    wizard_run_cmd "$label" "$log_file" "$@"
  elif command -v sudo >/dev/null 2>&1; then
    wizard_run_cmd "$label" "$log_file" sudo env FORCE_COLOR="${FORCE_COLOR:-1}" CLICOLOR_FORCE="${CLICOLOR_FORCE:-1}" "$@"
  else
    die "This command needs root. Re-run with sudo."
  fi
}

prompt_tty() {
  local label="$1"
  local default="${2:-}"
  local reply
  local prompt

  has_tty || return 1
  if [[ -n "$default" ]]; then
    prompt="$label: "
    IFS= read -e -r -i "$default" -p "$prompt" reply < /dev/tty || true
  else
    prompt="$label: "
    IFS= read -e -r -p "$prompt" reply < /dev/tty || true
  fi
  printf '%s\n' "$reply"
}

prompt_secret_tty() {
  local label="$1"
  local reply

  has_tty || return 1
  printf '%s: ' "$label" > /dev/tty
  IFS= read -r -s reply < /dev/tty || true
  printf '\n' > /dev/tty
  printf '%s\n' "$reply"
}

prompt_enter_tty() {
  local message="$1"

  if has_tty; then
    printf '%s' "$message" > /dev/tty
    IFS= read -r _ < /dev/tty || true
  else
    say "$message"
  fi
}

maybe_apply_cloudflare_dns() {
  local config="$1"
  local log_file="$2"
  shift 2
  local token_file=""
  local token=""
  local zone_id="${CLOUDFLARE_ZONE_ID:-}"
  local cleanup_token_file="false"
  local status

  has_tty || return 0
  confirm_tty "Apply these DNS records through Cloudflare now?" "no" || return 0

  if [[ -n "${CLOUDFLARE_API_TOKEN_FILE:-}" ]]; then
    token_file="$CLOUDFLARE_API_TOKEN_FILE"
  elif [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    token_file="$(mktemp "${TMPDIR:-/tmp}/mailserver-cloudflare-token.XXXXXX")"
    chmod 0600 "$token_file"
    printf '%s' "$CLOUDFLARE_API_TOKEN" > "$token_file"
    cleanup_token_file="true"
  else
    token="$(prompt_secret_tty "Cloudflare API token (Zone:DNS Write, Zone:Zone Read; not stored)")"
    [[ -n "$token" ]] || {
      wizard_problem "Cloudflare DNS skipped: empty API token."
      return 0
    }
    token_file="$(mktemp "${TMPDIR:-/tmp}/mailserver-cloudflare-token.XXXXXX")"
    chmod 0600 "$token_file"
    printf '%s' "$token" > "$token_file"
    cleanup_token_file="true"
  fi

  if [[ -z "$zone_id" ]]; then
    zone_id="$(prompt_tty "Cloudflare zone ID, blank to auto-detect" "")"
  fi

  if [[ -n "$zone_id" ]]; then
    set +e
    wizard_run_root_cmd "Applying Cloudflare DNS records" "$log_file" env CLOUDFLARE_API_TOKEN_FILE="$token_file" "$ROOT_DIR/scripts/apply-cloudflare-dns.sh" --config "$config" --zone-id "$zone_id" "$@"
    status=$?
    set -e
  else
    set +e
    wizard_run_root_cmd "Applying Cloudflare DNS records" "$log_file" env CLOUDFLARE_API_TOKEN_FILE="$token_file" "$ROOT_DIR/scripts/apply-cloudflare-dns.sh" --config "$config" "$@"
    status=$?
    set -e
  fi

  if [[ "$cleanup_token_file" == "true" ]]; then
    rm -f -- "$token_file"
  fi
  return "$status"
}

confirm_tty() {
  local prompt="$1"
  local default="${2:-no}"
  local reply suffix

  if [[ "$default" == "yes" ]]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi

  if ! has_tty; then
    [[ "$default" == "yes" ]]
    return "$?"
  fi

  printf '%s %s ' "$prompt" "$suffix" > /dev/tty
  IFS= read -r reply < /dev/tty || true
  reply="${reply:-$default}"
  [[ "$reply" == "y" || "$reply" == "Y" || "$reply" == "yes" || "$reply" == "YES" ]]
}

prompt_domain_tty() {
  local default="${1:-}"
  local reply domain

  has_tty || return 1
  while true; do
    reply="$(prompt_tty "Primary mail domain only, for example example.org" "$default")"
    domain="$(normalize_domain "$reply")"
    if [[ "$domain" == *@* ]]; then
      warn "That looks like an email address; using only the domain after @."
      domain="${domain##*@}"
    fi

    if is_valid_domain "$domain"; then
      printf '%s\n' "$domain"
      return 0
    fi

    printf 'Invalid domain: %s. Enter a domain like example.org, not an email address.\n' "$reply" > /dev/tty
  done
}

say_tty() {
  local message="$*"
  if has_tty; then
    printf '%s\n' "$(color 36 "• $message")" > /dev/tty
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
    IFS= read -e -r -i "${default:-Europe/Prague}" -p "Timezone choice [1-${#zones[@]}/IANA]: " reply < /dev/tty || true

    if [[ "$reply" =~ ^[0-9]+$ && "$reply" -ge 1 && "$reply" -le "${#zones[@]}" ]]; then
      selected="${zones[$((reply - 1))]}"
    else
      selected="${reply:-${default:-Europe/Prague}}"
    fi

    if [[ ! -d /usr/share/zoneinfo ]] || timezone_exists "$selected"; then
      printf '%s\n' "$selected"
      return 0
    fi

    printf 'Invalid timezone: %s. Use an IANA name like Europe/Prague.\n' "$selected" > /dev/tty
  done
}

print_wizard_step() {
  local title="$1"
  printf '\n%s\n' "$(color 36 "== $title ==")"
}

dns_check_args_for_stage() {
  local stage="$1"

  case "$stage" in
    preinstall) printf '%s\n' "" ;;
    final) printf '%s\n' "" ;;
    *) die "Unknown DNS check stage: $stage" ;;
  esac
}

wait_for_dns_stage() {
  local config="$1"
  local stage="$2"
  local title="$3"
  local step="$4"
  local log_file="$5"
  local args=()
  local stage_arg
  local dns_records
  local dns_output
  local status

  while IFS= read -r stage_arg; do
    [[ -n "$stage_arg" ]] && args+=("$stage_arg")
  done < <(dns_check_args_for_stage "$stage")

  wizard_header "$step" "$title" "$log_file"
  wizard_note "Publish the DNS records below. This setup will not continue until they resolve correctly."
  wizard_write ""
  if [[ "$EUID" -eq 0 ]]; then
    dns_records="$("$ROOT_DIR/scripts/print-dns.sh" --config "$config" "${args[@]}" 2>>"$log_file")"
  elif command -v sudo >/dev/null 2>&1; then
    dns_records="$(sudo "$ROOT_DIR/scripts/print-dns.sh" --config "$config" "${args[@]}" 2>>"$log_file")"
  else
    die "This command needs root. Re-run with sudo."
  fi
  set +e
  dns_output="$("$ROOT_DIR/scripts/dns-state.sh" --config "$config" "${args[@]}" 2>&1)"
  status=$?
  dns_output+=$'\n'
  dns_output+="$("$ROOT_DIR/scripts/tls-policy-state.sh" --config "$config" "${args[@]}" 2>&1)"
  set -e
  {
    printf '\n[%s] DNS status snapshot: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$title"
    printf '%s\n' "$dns_output"
  } >> "$log_file"
  wizard_records "$dns_records" "$dns_output"
  if [[ "$stage" == "preinstall" ]]; then
    maybe_apply_cloudflare_dns "$config" "$log_file" "${args[@]}"
  fi

  while true; do
    wizard_write ""
    prompt_enter_tty "Press Enter to check DNS. Use Ctrl-C to stop and resume later. "
    wizard_header "$step" "$title" "$log_file"
    wizard_note "Checking DNS now..."
    set +e
    dns_output="$("$ROOT_DIR/scripts/dns-state.sh" --config "$config" "${args[@]}" 2>&1)"
    status=$?
    dns_output+=$'\n'
    dns_output+="$("$ROOT_DIR/scripts/tls-policy-state.sh" --config "$config" "${args[@]}" 2>&1)"
    set -e
    {
      printf '\n[%s] DNS check: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$title"
      printf '%s\n' "$dns_output"
    } >> "$log_file"
    if [[ "$status" -eq 0 ]]; then
      wizard_success "DNS checks passed for this step."
      return 0
    fi
    wizard_problem "DNS is not ready yet. Fix the records below or wait for propagation, then retry."
    wizard_records "$dns_records" "$dns_output"
    wizard_write ""
    wizard_write "Full DNS output: $log_file"
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

set_or_append_config_entry() {
  local file="$1"
  local key="$2"
  local value
  value="$(config_value "$3")"
  if grep -q "^$key=" "$file"; then
    sed -i "s|^$key=.*|$key=$value|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

email_with_domain() {
  local email="$1"
  local old_domain="$2"
  local new_domain="$3"
  local localpart domain

  [[ "$email" == *@* ]] || {
    printf '%s\n' "$email"
    return 0
  }

  localpart="${email%@*}"
  domain="${email#*@}"
  if [[ "$(normalize_domain "$domain")" == "$(normalize_domain "$old_domain")" ]]; then
    printf '%s@%s\n' "$localpart" "$new_domain"
  else
    printf '%s\n' "$email"
  fi
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
  local config_only="false"
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
      --config-only|--no-wizard)
        config_only="true"
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
    if [[ "$config_only" == "true" || "$non_interactive" == "true" ]] || ! has_tty; then
      return 0
    fi
    if ! confirm_tty "Continue the guided setup with this config?" "yes"; then
      say "Keeping existing config unchanged."
      return 0
    fi
    run_guided_setup "$dest"
    return 0
  fi

  if [[ "$non_interactive" != "true" && ( -z "$domain" || -z "$admin_email" || -z "$public_ipv4" ) ]]; then
    if has_tty; then
      say_tty "Collecting setup answers first. No network or install steps will run until prompts finish."
      domain="${domain:-$(prompt_domain_tty "${MAILSERVER_DOMAIN:-}")}"
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
  if [[ "$config_only" == "true" || "$non_interactive" == "true" ]] || ! has_tty; then
    say "Next: mailserver doctor"
    return 0
  fi

  run_guided_setup "$dest"
}

run_guided_setup() {
  local config="$1"
  local log_file

  require_checkout_files
  log_file="$(wizard_log_file)"

  wizard_header "1/4" "Local checks" "$log_file"
  wizard_note "First I will check this host and config. Fix any failure before DNS or install."
  wizard_run_cmd "Checking prerequisites and config" "$log_file" env MAILSERVER_SKIP_PREFLIGHT_DNS=true "$ROOT_DIR/doctor.sh" --preflight-only --config "$config"
  prompt_enter_tty "Press Enter to continue to DNS setup. "

  wait_for_dns_stage "$config" preinstall "2. DNS setup" "2/4" "$log_file"

  wizard_header "3/4" "Install mail stack" "$log_file"
  wizard_note "DNS is ready enough for certificates and mail routing."
  wizard_note "Now I will configure packages, services, the primary mailbox, certificates, and DKIM."
  wizard_write ""
  wizard_run_root_cmd "Installing and configuring the mail stack" "$log_file" "$ROOT_DIR/install.sh" --config "$config" --assume-yes
  wizard_run_root_cmd "Verifying generated config and services" "$log_file" "$ROOT_DIR/verify.sh" --config "$config"
  prompt_enter_tty "Press Enter to continue to final checks. "

  wizard_header "4/4" "Final checks" "$log_file"
  wizard_run_cmd "Checking TLS certificates" "$log_file" "$ROOT_DIR/scripts/check-ssl.sh" --config "$config"
  wizard_run_cmd "Checking service status and ports" "$log_file" "$ROOT_DIR/scripts/service-state.sh" --config "$config"
  wizard_write ""
  if confirm_tty "Install the recurring backup cron now?" "yes"; then
    wizard_run_root_cmd "Installing recurring backup cron" "$log_file" "$ROOT_DIR/scripts/install-backup-cron.sh" --config "$config"
  else
    wizard_problem "Backup cron skipped. Install it later with: sudo mailserver install-backup-cron --config $config"
  fi

  wizard_write ""
  wizard_success "Guided setup complete."
  wizard_write "Primary mailbox password, if generated, is stored at PRIMARY_MAILBOX_PASSWORD_FILE from $config."
  wizard_write "Client settings: mailserver client-info --config $config"
  wizard_write "Detailed log: $log_file"
}

cmd_set_domain() {
  extract_common_args "$@"
  local domain=""
  local admin_email=""
  local primary_mailbox=""
  local mail_hostname=""
  local webmail_hostname=""
  local dav_hostname=""
  local keep_primary_mailbox="false"
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
      --admin-email)
        [[ -n "${REMAINING_ARGS[0]:-}" ]] || die "Missing value for --admin-email."
        admin_email="${REMAINING_ARGS[0]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        ;;
      --primary-mailbox)
        [[ -n "${REMAINING_ARGS[0]:-}" ]] || die "Missing value for --primary-mailbox."
        primary_mailbox="${REMAINING_ARGS[0]}"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
        ;;
      --mail-hostname)
        [[ -n "${REMAINING_ARGS[0]:-}" ]] || die "Missing value for --mail-hostname."
        mail_hostname="${REMAINING_ARGS[0]}"
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
      --keep-primary-mailbox)
        keep_primary_mailbox="true"
        ;;
      *)
        if [[ -z "$domain" ]]; then
          domain="$arg"
        else
          die "Unexpected argument: $arg"
        fi
        ;;
    esac
  done

  [[ -n "$domain" ]] || die "Missing --domain example.com."
  domain="$(normalize_domain "$domain")"
  validate_domain_or_die "$domain"

  local config old_primary old_admin old_primary_mailbox config_tmp backup
  config="$(config_arg)"
  [[ -f "$config" ]] || die "Config file not found: $config"

  # shellcheck source=/dev/null
  source "$config"
  old_primary="$(normalize_domain "${PRIMARY_DOMAIN:-}")"
  [[ -n "$old_primary" ]] || die "PRIMARY_DOMAIN is empty in $config"

  old_admin="${ADMIN_EMAIL:-admin@$old_primary}"
  old_primary_mailbox="${PRIMARY_MAILBOX:-}"
  admin_email="${admin_email:-$(email_with_domain "$old_admin" "$old_primary" "$domain")}"
  if [[ "$keep_primary_mailbox" == "true" ]]; then
    primary_mailbox="${primary_mailbox:-$old_primary_mailbox}"
  else
    primary_mailbox="${primary_mailbox:-$(email_with_domain "${old_primary_mailbox:-$admin_email}" "$old_primary" "$domain")}"
  fi

  [[ "$admin_email" == *@* ]] || die "Invalid admin email address: $admin_email"
  [[ -z "$primary_mailbox" || "$primary_mailbox" == *@* ]] || die "Invalid primary mailbox: $primary_mailbox"
  [[ -z "$mail_hostname" ]] || validate_domain_or_die "$mail_hostname"
  [[ -z "$webmail_hostname" ]] || validate_domain_or_die "$webmail_hostname"
  [[ -z "$dav_hostname" ]] || validate_domain_or_die "$dav_hostname"

  config_tmp="$(mktemp "$config.tmp.XXXXXX")"
  cp -p "$config" "$config_tmp"
  set_or_append_config_entry "$config_tmp" "PRIMARY_DOMAIN" "$domain"
  set_or_append_config_entry "$config_tmp" "ADMIN_EMAIL" "$admin_email"
  set_or_append_config_entry "$config_tmp" "POSTMASTER_ADDRESS" "postmaster@$domain"
  set_or_append_config_entry "$config_tmp" "ABUSE_ADDRESS" "abuse@$domain"
  set_or_append_config_entry "$config_tmp" "PRIMARY_MAILBOX" "$primary_mailbox"
  set_or_append_config_entry "$config_tmp" "PRIMARY_ALIAS_ADDRESSES" "postmaster@$domain abuse@$domain dmarc@$domain $primary_mailbox"
  [[ -z "$mail_hostname" ]] || set_or_append_config_entry "$config_tmp" "MAIL_HOSTNAME" "$mail_hostname"
  [[ -z "$webmail_hostname" ]] || set_or_append_config_entry "$config_tmp" "WEBMAIL_HOSTNAME" "$webmail_hostname"
  if [[ -n "$dav_hostname" ]]; then
    set_or_append_config_entry "$config_tmp" "DAV_HOSTNAME" "$dav_hostname"
  fi

  backup="$config.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -p "$config" "$backup"
  mv "$config_tmp" "$config"
  chown_for_sudo_user "$config"
  chown_for_sudo_user "$backup"

  ok "Updated primary domain in $config: $old_primary -> $domain"
  ok "Backup kept at $backup"
  say "Next: mailserver doctor, then sudo mailserver setup-primary-mailbox and sudo mailserver print-dns"
}

cmd_install_cli() {
  extract_common_args "$@"
  [[ "${#REMAINING_ARGS[@]}" -eq 0 ]] || die "install-cli does not accept positional arguments."
  require_checkout_files
  install_cli_link interactive
}

cmd_reset_setup() {
  extract_common_args "$@"
  local assume_yes="false"
  local arg

  while [[ "${#REMAINING_ARGS[@]}" -gt 0 ]]; do
    arg="${REMAINING_ARGS[0]}"
    REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
    case "$arg" in
      --yes|-y)
        assume_yes="true"
        ;;
      *)
        die "Unknown reset-setup option: $arg"
        ;;
    esac
  done

  local config backup
  config="$(config_arg)"
  [[ -f "$config" ]] || die "Setup config not found: $config"

  warn "This only removes the local setup config. It does not uninstall services or delete mail data."
  if [[ "$assume_yes" != "true" ]]; then
    confirm_tty "Move $config aside?" "no" || die "Cancelled."
  fi

  backup="$config.deleted.$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$config" "$backup"
  chown_for_sudo_user "$backup"
  ok "Moved setup config to $backup"
  say "Run mailserver init to create a fresh setup."
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
  local arg
  for arg in "${REMAINING_ARGS[@]}"; do
    case "$arg" in
      --fix|--preflight-only) ;;
      *) die "doctor does not accept positional arguments." ;;
    esac
  done
  require_checkout_files
  run_cmd "$ROOT_DIR/doctor.sh" --config "$(config_arg)" "${REMAINING_ARGS[@]}"
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
  run_cmd "$ROOT_DIR/doctor.sh" --preflight-only --config "$config"
  run_root_cmd "$ROOT_DIR/install.sh" --config "$config" --dry-run --assume-yes
  run_cmd "$ROOT_DIR/scripts/print-dns.sh" --config "$config"
}

cmd_setup() {
  extract_common_args "$@"
  [[ "${#REMAINING_ARGS[@]}" -eq 0 ]] || die "setup does not accept positional arguments."
  require_checkout_files
  local config
  config="$(config_arg)"
  run_cmd "$ROOT_DIR/doctor.sh" --preflight-only --config "$config"
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

cmd_option_script() {
  local script="$1"
  local root_needed="$2"
  shift 2
  extract_common_args "$@"
  require_checkout_files
  if [[ "$root_needed" == "true" ]]; then
    run_root_cmd "$ROOT_DIR/$script" --config "$(config_arg)" "${REMAINING_ARGS[@]}"
  else
    run_cmd "$ROOT_DIR/$script" --config "$(config_arg)" "${REMAINING_ARGS[@]}"
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
  local allow_mailbox_source="false"
  local script="scripts/add-alias.sh"

  if [[ "$COMMAND" == "set-alias" ]]; then
    script="scripts/set-alias.sh"
  elif [[ "$COMMAND" == "add-forward" ]]; then
    script="scripts/add-forward.sh"
  fi

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
      --allow-mailbox-source)
        [[ "$COMMAND" == "add-forward" ]] || die "Unexpected argument: ${REMAINING_ARGS[0]}"
        allow_mailbox_source="true"
        REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
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
  if [[ "$allow_mailbox_source" == "true" ]]; then
    run_root_cmd "$ROOT_DIR/$script" --config "$(config_arg)" "$source_addr" "$dest_addr" --allow-mailbox-source
  else
    run_root_cmd "$ROOT_DIR/$script" --config "$(config_arg)" "$source_addr" "$dest_addr"
  fi
}

main() {
  parse_global_args "$@"
  normalize_command
  case "$COMMAND" in
    init) cmd_init "${COMMAND_ARGS[@]}" ;;
    reset-setup) cmd_reset_setup "${COMMAND_ARGS[@]}" ;;
    remove) cmd_option_script scripts/remove.sh true "${COMMAND_ARGS[@]}" ;;
    set-domain) cmd_set_domain "${COMMAND_ARGS[@]}" ;;
    install-cli) cmd_install_cli "${COMMAND_ARGS[@]}" ;;
    update) cmd_update "${COMMAND_ARGS[@]}" ;;
    doctor) cmd_doctor "${COMMAND_ARGS[@]}" ;;
    dry-run) cmd_dry_run "${COMMAND_ARGS[@]}" ;;
    install) cmd_install "${COMMAND_ARGS[@]}" ;;
    setup-dry-run) cmd_setup_dry_run "${COMMAND_ARGS[@]}" ;;
    setup) cmd_setup "${COMMAND_ARGS[@]}" ;;
    verify) cmd_verify "${COMMAND_ARGS[@]}" ;;
    print-dns) cmd_option_script scripts/print-dns.sh true "${COMMAND_ARGS[@]}" ;;
    dns-state) cmd_option_script scripts/dns-state.sh false "${COMMAND_ARGS[@]}" ;;
    check-ssl) cmd_simple_script scripts/check-ssl.sh false "${COMMAND_ARGS[@]}" ;;
    service-state) cmd_simple_script scripts/service-state.sh false "${COMMAND_ARGS[@]}" ;;
    config-drift) cmd_simple_script scripts/config-drift.sh false "${COMMAND_ARGS[@]}" ;;
    e2e-delivery) cmd_option_script scripts/e2e-delivery-test.sh true "${COMMAND_ARGS[@]}" ;;
    tls-policy-state) cmd_option_script scripts/tls-policy-state.sh false "${COMMAND_ARGS[@]}" ;;
    rspamd-state) cmd_option_script scripts/rspamd-state.sh true "${COMMAND_ARGS[@]}" ;;
    apply-cloudflare-dns) cmd_option_script scripts/apply-cloudflare-dns.sh true "${COMMAND_ARGS[@]}" ;;
    list-domains) cmd_simple_script scripts/list-domains.sh true "${COMMAND_ARGS[@]}" ;;
    list-aliases) cmd_option_script scripts/list-aliases.sh true "${COMMAND_ARGS[@]}" ;;
    list-forwards) cmd_option_script scripts/list-forwards.sh true "${COMMAND_ARGS[@]}" ;;
    add-domain) cmd_option_script scripts/add-domain.sh true "${COMMAND_ARGS[@]}" ;;
    remove-domain) cmd_option_script scripts/remove-domain.sh true "${COMMAND_ARGS[@]}" ;;
    list-users) cmd_simple_script scripts/list-users.sh true "${COMMAND_ARGS[@]}" ;;
    setup-primary-mailbox) cmd_simple_script scripts/setup-primary-mailbox.sh true "${COMMAND_ARGS[@]}" ;;
    backup) cmd_simple_script scripts/backup.sh true "${COMMAND_ARGS[@]}" ;;
    restore) cmd_option_script scripts/restore.sh true "${COMMAND_ARGS[@]}" ;;
    install-backup-cron) cmd_simple_script scripts/install-backup-cron.sh true "${COMMAND_ARGS[@]}" ;;
    client-info) cmd_client_info "${COMMAND_ARGS[@]}" ;;
    add-user) cmd_user_arg scripts/add-user.sh "${COMMAND_ARGS[@]}" ;;
    remove-user) cmd_user_arg scripts/remove-user.sh "${COMMAND_ARGS[@]}" ;;
    change-password) cmd_user_arg scripts/change-password.sh "${COMMAND_ARGS[@]}" ;;
    add-alias|set-alias|add-forward) cmd_add_alias "${COMMAND_ARGS[@]}" ;;
    *)
      die "Unknown command: $COMMAND. Run mailserver help."
      ;;
  esac
}

if [[ "${MAILSERVER_SOURCE_ONLY:-false}" != "true" ]]; then
  main "$@"
fi
