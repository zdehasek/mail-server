#!/usr/bin/env bash

run postfix check
run doveconf -n >/dev/null
run nginx -t
if [[ "${ENABLE_RSPAMD:-true}" == "true" ]]; then
  run rspamadm configtest
fi
mark_done verify
