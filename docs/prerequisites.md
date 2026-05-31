# Prerequisites

Use a fresh Ubuntu 26.04 LTS server with root or sudo access.

Required before production install:

- Static public IPv4 address.
- DNS control for `PRIMARY_DOMAIN`.
- Provider permits inbound and outbound SMTP on TCP/25.
- PTR/rDNS configured by the provider: server IP to `MAIL_HOSTNAME`.
- Ports reachable from the internet: `25`, `80`, `443`, `587`, `993`.
- Hostname set to `MAIL_HOSTNAME`.
- A non-root SSH user with key-based login if `ENABLE_SSH_HARDENING=true`.

Recommended resources:

- 1 GB RAM minimum for Roundcube, Radicale, and Rspamd.
- 4 GB RAM if ClamAV is enabled.
- 20 GB disk minimum.

The installer is designed for a fresh host. It backs up managed config files but does not migrate existing mail systems.

## Network Exposure

When `ENABLE_UFW=true`, the installer sets the firewall to deny incoming traffic by default and allows only:

- `SSH_PORT` TCP, default `22`, for administration.
- `25/tcp` for inbound SMTP.
- `80/tcp` for Let's Encrypt HTTP validation and redirects.
- `443/tcp` for Roundcube and Radicale over HTTPS.
- `587/tcp` for authenticated mail submission.
- `993/tcp` for IMAPS.

Other listening services are not exposed through UFW by default. `UFW_RESET_RULES=true` is the default, so existing UFW rules are reset before the mail server allowlist is applied. This is intentional for fresh hosts and prevents stale allow rules from leaving unneeded ports open.

## SSH Hardening

When `ENABLE_SSH_HARDENING=true`, the installer writes `/etc/ssh/sshd_config.d/99-mailserver-hardening.conf` with root login and password login disabled. Set `SSH_ALLOW_USERS` in `.env` to the SSH user that should remain allowed, for example:

```bash
SSH_ALLOW_USERS="app"
```

If `SSH_ALLOW_USERS` is empty, the installer uses the sudo user when available. If it cannot identify a key-enabled user, it skips SSH hardening instead of risking lockout.
