PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS domains (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY,
  domain_id INTEGER NOT NULL,
  email TEXT NOT NULL UNIQUE,
  username TEXT NOT NULL,
  full_name TEXT NOT NULL DEFAULT '',
  password_hash TEXT NOT NULL,
  home TEXT NOT NULL,
  maildir TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(domain_id) REFERENCES domains(id)
);

CREATE TABLE IF NOT EXISTS aliases (
  id INTEGER PRIMARY KEY,
  domain_id INTEGER NOT NULL,
  source TEXT NOT NULL,
  destination TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY(domain_id) REFERENCES domains(id),
  UNIQUE(source, destination)
);

CREATE INDEX IF NOT EXISTS users_email_active_idx ON users(email, active);
CREATE INDEX IF NOT EXISTS aliases_source_active_idx ON aliases(source, active);
