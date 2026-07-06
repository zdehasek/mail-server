CREATE TABLE IF NOT EXISTS domains (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  domain_id BIGINT REFERENCES domains(id),
  email TEXT NOT NULL UNIQUE,
  username TEXT NOT NULL,
  full_name TEXT NOT NULL DEFAULT '',
  password_hash TEXT NOT NULL,
  home TEXT NOT NULL,
  maildir TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS aliases (
  id BIGSERIAL PRIMARY KEY,
  domain_id BIGINT REFERENCES domains(id),
  source TEXT NOT NULL,
  destination TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT true,
  UNIQUE(source, destination)
);

CREATE INDEX IF NOT EXISTS users_email_active_idx ON users(email, active);
CREATE INDEX IF NOT EXISTS aliases_source_active_idx ON aliases(source, active);
