#!/usr/bin/env bash

up() {
  # shellcheck source=../lib/preflight.sh
  source "$ROOT_DIR/lib/preflight.sh"
  run_preflight
  mark_done preflight
}

down() {
  info "Preflight made no persistent changes"
}
