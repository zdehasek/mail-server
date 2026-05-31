# Prerequisites

Use a fresh Ubuntu 26.04 LTS server with root or sudo access.

Required before production install:

- Static public IPv4 address.
- DNS control for `PRIMARY_DOMAIN`.
- Provider permits inbound and outbound SMTP on TCP/25.
- PTR/rDNS configured by the provider: server IP to `MAIL_HOSTNAME`.
- Ports reachable from the internet: `25`, `80`, `443`, `587`, `993`.
- Hostname set to `MAIL_HOSTNAME`.

Recommended resources:

- 1 GB RAM minimum for Roundcube, Radicale, and Rspamd.
- 4 GB RAM if ClamAV is enabled.
- 20 GB disk minimum.

The installer is designed for a fresh host. It backs up managed config files but does not migrate existing mail systems.
