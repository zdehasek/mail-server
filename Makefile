CONFIG ?= ./mail.env
USER ?=
SOURCE ?=
DEST ?=
HOST ?=
REMOTE_DIR ?= /tmp/mail-server

.PHONY: help init deploy doctor dry-run install verify print-dns add-user add-alias change-password

help:
	@printf '%s\n' \
	  'Mail server installer entrypoint' \
	  '' \
	  'Usage:' \
	  '  make init' \
	  '  make deploy HOST=app@server REMOTE_DIR=/tmp/mail-server' \
	  '  make doctor CONFIG=./mail.env' \
	  '  make dry-run CONFIG=./mail.env' \
	  '  sudo make install CONFIG=./mail.env' \
	  '  sudo make verify CONFIG=./mail.env' \
	  '  sudo make print-dns CONFIG=./mail.env' \
	  '  sudo make add-user CONFIG=./mail.env USER=user@example.com' \
	  '  sudo make add-alias CONFIG=./mail.env SOURCE=postmaster@example.com DEST=user@example.com' \
	  '  sudo make change-password CONFIG=./mail.env USER=user@example.com'

init:
	@test -f "$(CONFIG)" || cp config/example.env "$(CONFIG)"
	@printf 'Created %s. Edit it before install.\n' "$(CONFIG)"

deploy:
	@test -n "$(HOST)" || { printf 'Set HOST=user@server\n' >&2; exit 1; }
	ssh "$(HOST)" 'mkdir -p "$(REMOTE_DIR)"'
	rsync -az --delete \
	  --exclude '.git/' \
	  --exclude 'mail.env' \
	  --exclude '*.local.env' \
	  ./ "$(HOST):$(REMOTE_DIR)/"

doctor:
	./doctor.sh --config "$(CONFIG)"

dry-run:
	sudo ./install.sh --config "$(CONFIG)" --dry-run --assume-yes

install:
	./install.sh --config "$(CONFIG)" --assume-yes

verify:
	./verify.sh --config "$(CONFIG)"

print-dns:
	./scripts/print-dns.sh --config "$(CONFIG)"

add-user:
	@test -n "$(USER)" || { printf 'Set USER=user@example.com\n' >&2; exit 1; }
	./scripts/add-user.sh --config "$(CONFIG)" "$(USER)"

add-alias:
	@test -n "$(SOURCE)" || { printf 'Set SOURCE=source@example.com\n' >&2; exit 1; }
	@test -n "$(DEST)" || { printf 'Set DEST=dest@example.com\n' >&2; exit 1; }
	./scripts/add-alias.sh --config "$(CONFIG)" "$(SOURCE)" "$(DEST)"

change-password:
	@test -n "$(USER)" || { printf 'Set USER=user@example.com\n' >&2; exit 1; }
	./scripts/change-password.sh --config "$(CONFIG)" "$(USER)"
