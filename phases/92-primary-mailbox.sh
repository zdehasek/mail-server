#!/usr/bin/env bash

up() {
  primary_mailbox_args=(--config "$CONFIG_FILE")
  [[ "$DRY_RUN" == "true" ]] && primary_mailbox_args+=(--dry-run)
  bash "$ROOT_DIR/scripts/setup-primary-mailbox.sh" "${primary_mailbox_args[@]}"
  mark_done primary-mailbox
}

down() {
  info "Primary mailbox data is removed with the database and vmail data phases"
}
