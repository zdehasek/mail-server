ENV_FILE ?= ./.env
ifneq (,$(wildcard $(ENV_FILE)))
include $(ENV_FILE)
export
endif

DEFAULT_CONFIG := $(if $(wildcard $(ENV_FILE)),$(ENV_FILE),$(if $(wildcard ./mail.env),./mail.env,$(ENV_FILE)))
CONFIG ?= $(DEFAULT_CONFIG)
MAIL_USER ?= $(if $(filter command line,$(origin USER)),$(USER),)
SOURCE ?=
DEST ?=
HOST ?=
REMOTE_DIR ?= /tmp/mail-server
RSYNC ?= rsync
SSH ?= ssh
RSYNC_FLAGS ?= -az --delete --human-readable --info=progress2
RSYNC_EXCLUDES ?= --exclude .git/

.PHONY: help init deploy setup-dry-run setup doctor dry-run install verify check print-dns dns-state check-ssl service-state add-user setup-primary-mailbox add-alias change-password backup install-backup-cron

help:
	@printf '%s\n' \
	  'Mail server installer' \
	  '' \
	  'Setup flow:' \
	  '  make init                    Create .env from .env.example' \
	  '  make setup-dry-run           Validate config and show planned changes' \
	  '  sudo make setup              Install and verify on the target server' \
	  '' \
	  'Health checks:' \
	  '  make check                   Run DNS, SSL/TLS, and service checks' \
	  '  make dns-state               Check A/AAAA, MX, SPF, DMARC, PTR, DKIM' \
	  '                               Uses DNS_RESOLVER=1.1.1.1 by default' \
	  '  make check-ssl               Check HTTPS, IMAPS, and SMTP TLS certs' \
	  '  make service-state           Check services, ports, and web endpoints' \
	  '  sudo make verify             Check local configs and active services' \
	  '  sudo make print-dns          Print DNS records, including generated DKIM' \
	  '' \
	  'Mailbox operations:' \
	  '  sudo make add-user USER=user@example.com' \
	  '  sudo make setup-primary-mailbox' \
	  '  sudo make add-alias SOURCE=postmaster@example.com DEST=user@example.com' \
	  '  sudo make change-password USER=user@example.com' \
	  '' \
	  'Backup:' \
	  '  sudo make backup' \
	  '  sudo make install-backup-cron' \
	  '' \
	  'Remote copy:' \
	  '  make deploy                  Copy this repository with SSH/rsync' \
	  '' \
	  'Defaults are loaded from ./.env when present. Override with CONFIG=./mail.env or ENV_FILE=path.' \
	  'Local setup uses the same commands after the repository is copied to the target server.'

init:
	@test -f "$(CONFIG)" || cp .env.example "$(CONFIG)"
	@printf 'Created %s. Edit it before install.\n' "$(CONFIG)"

deploy:
	@test -n "$(HOST)" || { printf 'Set HOST=user@server\n' >&2; exit 1; }
	@command -v "$(RSYNC)" >/dev/null || { printf 'rsync is required locally\n' >&2; exit 1; }
	$(SSH) "$(HOST)" 'mkdir -p "$(REMOTE_DIR)"'
	$(RSYNC) $(RSYNC_FLAGS) $(RSYNC_EXCLUDES) ./ "$(HOST):$(REMOTE_DIR)/"

setup-dry-run:
	./doctor.sh --config "$(CONFIG)"
	sudo ./install.sh --config "$(CONFIG)" --dry-run --assume-yes
	./scripts/print-dns.sh --config "$(CONFIG)"

setup:
	./doctor.sh --config "$(CONFIG)"
	./install.sh --config "$(CONFIG)" --assume-yes
	./verify.sh --config "$(CONFIG)"
	./scripts/print-dns.sh --config "$(CONFIG)"

doctor:
	./doctor.sh --config "$(CONFIG)"

dry-run:
	sudo ./install.sh --config "$(CONFIG)" --dry-run --assume-yes

install:
	./install.sh --config "$(CONFIG)" --assume-yes

verify:
	./verify.sh --config "$(CONFIG)"

check:
	@status=0; \
	./scripts/dns-state.sh --config "$(CONFIG)" || status=$$?; \
	printf '\n'; \
	./scripts/check-ssl.sh --config "$(CONFIG)" || status=$$?; \
	printf '\n'; \
	./scripts/service-state.sh --config "$(CONFIG)" || status=$$?; \
	exit $$status

print-dns:
	./scripts/print-dns.sh --config "$(CONFIG)"

dns-state:
	./scripts/dns-state.sh --config "$(CONFIG)"

check-ssl:
	./scripts/check-ssl.sh --config "$(CONFIG)"

service-state:
	./scripts/service-state.sh --config "$(CONFIG)"

add-user:
	@test -n "$(MAIL_USER)" || { printf 'Set USER=user@example.com\n' >&2; exit 1; }
	./scripts/add-user.sh --config "$(CONFIG)" "$(MAIL_USER)"

setup-primary-mailbox:
	./scripts/setup-primary-mailbox.sh --config "$(CONFIG)"

add-alias:
	@test -n "$(SOURCE)" || { printf 'Set SOURCE=source@example.com\n' >&2; exit 1; }
	@test -n "$(DEST)" || { printf 'Set DEST=dest@example.com\n' >&2; exit 1; }
	./scripts/add-alias.sh --config "$(CONFIG)" "$(SOURCE)" "$(DEST)"

change-password:
	@test -n "$(MAIL_USER)" || { printf 'Set USER=user@example.com\n' >&2; exit 1; }
	./scripts/change-password.sh --config "$(CONFIG)" "$(MAIL_USER)"

backup:
	./scripts/backup.sh --config "$(CONFIG)"

install-backup-cron:
	./scripts/install-backup-cron.sh --config "$(CONFIG)"
