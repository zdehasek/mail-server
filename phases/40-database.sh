#!/usr/bin/env bash

up() {
  ensure_mail_db_password

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Would initialize PostgreSQL database $MAIL_DB_NAME and role $MAIL_DB_USER"
    info "Would apply PostgreSQL mail schema"
    info "Would migrate existing SQLite mail DB from $MAIL_DB_PATH if present"
    mark_done database
    return 0
  fi

  service_enable_now postgresql

  role_exists="$(sudo -u postgres psql -At -c "SELECT 1 FROM pg_roles WHERE rolname = '$MAIL_DB_USER';")"
  if [[ "$role_exists" != "1" ]]; then
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE ROLE \"$MAIL_DB_USER\" LOGIN PASSWORD '$MAIL_DB_PASSWORD';"
  else
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER ROLE \"$MAIL_DB_USER\" LOGIN PASSWORD '$MAIL_DB_PASSWORD';"
  fi

  db_exists="$(sudo -u postgres psql -At -c "SELECT 1 FROM pg_database WHERE datname = '$MAIL_DB_NAME';")"
  if [[ "$db_exists" != "1" ]]; then
    sudo -u postgres createdb -O "$MAIL_DB_USER" "$MAIL_DB_NAME"
  fi

  sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$MAIL_DB_NAME" -c "ALTER DATABASE \"$MAIL_DB_NAME\" OWNER TO \"$MAIL_DB_USER\";"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$MAIL_DB_NAME" -c "GRANT ALL ON SCHEMA public TO \"$MAIL_DB_USER\";"
  psql_mail -f "$ROOT_DIR/sql/schema.pgsql.sql"
  psql_mail -c "CREATE OR REPLACE VIEW sogo_users AS
  SELECT
    email AS c_uid,
    email AS c_name,
    email AS mail,
    full_name AS c_cn,
    password_hash AS c_password
  FROM users
  WHERE active = true;"

  if [[ -f "$MAIL_DB_PATH" ]]; then
    existing_users="$(psql_mail_scalar -c "SELECT COUNT(*) FROM users;")"
    if [[ "$existing_users" == "0" ]]; then
      info "Migrating existing SQLite mail DB from $MAIL_DB_PATH"
      tmp_dir="$(mktemp -d)"
      trap 'rm -rf "$tmp_dir"' RETURN
      sudo sqlite3 -header -csv "$MAIL_DB_PATH" "SELECT name, CASE active WHEN 1 THEN 'true' ELSE 'false' END AS active FROM domains;" > "$tmp_dir/domains.csv"
      sudo sqlite3 -header -csv "$MAIL_DB_PATH" "SELECT email, username, full_name, password_hash, home, maildir, CASE active WHEN 1 THEN 'true' ELSE 'false' END AS active, created_at FROM users;" > "$tmp_dir/users.csv"
      sudo sqlite3 -header -csv "$MAIL_DB_PATH" "SELECT source, destination, CASE active WHEN 1 THEN 'true' ELSE 'false' END AS active FROM aliases;" > "$tmp_dir/aliases.csv"
      chmod 0600 "$tmp_dir"/*.csv

      psql_mail <<SQL
CREATE TEMP TABLE import_domains (
  name text, active boolean
);
\copy import_domains(name, active) FROM '$tmp_dir/domains.csv' WITH (FORMAT csv, HEADER true)
CREATE TEMP TABLE import_users (
  email text, username text, full_name text, password_hash text, home text, maildir text, active boolean, created_at timestamptz
);
CREATE TEMP TABLE import_aliases (
  source text, destination text, active boolean
);
\copy import_users(email, username, full_name, password_hash, home, maildir, active, created_at) FROM '$tmp_dir/users.csv' WITH (FORMAT csv, HEADER true)
\copy import_aliases(source, destination, active) FROM '$tmp_dir/aliases.csv' WITH (FORMAT csv, HEADER true)
INSERT INTO domains(name, active)
SELECT lower(name), active FROM import_domains
ON CONFLICT(name) DO UPDATE SET active=excluded.active;
INSERT INTO users(domain_id, email, username, full_name, password_hash, home, maildir, active, created_at)
SELECT domains.id, lower(import_users.email), import_users.username, import_users.full_name, import_users.password_hash, import_users.home, import_users.maildir, import_users.active, import_users.created_at
FROM import_users
JOIN domains ON domains.name = split_part(lower(import_users.email), '@', 2)
ON CONFLICT(email) DO UPDATE SET
  username=excluded.username,
  full_name=excluded.full_name,
  password_hash=excluded.password_hash,
  home=excluded.home,
  maildir=excluded.maildir,
  active=excluded.active;
INSERT INTO aliases(domain_id, source, destination, active)
SELECT domains.id, lower(import_aliases.source), lower(import_aliases.destination), import_aliases.active
FROM import_aliases
JOIN domains ON domains.name = split_part(lower(import_aliases.source), '@', 2)
ON CONFLICT(source, destination) DO UPDATE SET
  domain_id=excluded.domain_id,
  active=excluded.active;
SQL
    fi
  fi

  sync_configured_domains

  mark_done database
}

down() {
  drop_mail_database
}
