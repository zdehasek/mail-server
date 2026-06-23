#!/usr/bin/env bash

run mkdir -p "$(dirname "$MAIL_DB_PATH")"
if [[ "$DRY_RUN" == "true" ]]; then
  info "Would initialize SQLite mail DB at $MAIL_DB_PATH"
else
  sqlite3 "$MAIL_DB_PATH" < "$ROOT_DIR/sql/schema.sql"
  chown root:dovecot "$MAIL_DB_PATH"
  chmod 0640 "$MAIL_DB_PATH"
  sync_configured_domains
fi

mark_done database
