# DNS Records

Replace example values with `~/.email-server/config.env` values.

```text
example.com.          MX   10 mail.example.com.
mail.example.com.     A    203.0.113.10
dav.example.com.      A    203.0.113.10
webmail.example.com.  A    203.0.113.10
example.com.          TXT  "v=spf1 mx -all"
```

If IPv6 is configured:

```text
mail.example.com.     AAAA 2001:db8::10
dav.example.com.      AAAA 2001:db8::10
webmail.example.com.  AAAA 2001:db8::10
```

DKIM is generated during install. Print it with:

```bash
sudo mailserver print-dns
```

For an additional domain, activate the domain first, then print domain-specific
records:

```bash
sudo mailserver add-domain --domain example.net
sudo mailserver print-dns --domain example.net
```

`add-domain` creates `postmaster`, `abuse`, and `dmarc` aliases for the domain
by default so DMARC aggregate reports have a destination.

After publishing the records, check current DNS state against
`~/.email-server/config.env` with:

```bash
mailserver dns-state
```

For an additional domain:

```bash
mailserver dns-state --domain example.net
```

The DNS check uses `1.1.1.1` by default so local resolver aliases, caches, and
server-hostname synthetic records do not look like public DNS records. Override
it when needed:

```bash
DNS_RESOLVER=8.8.8.8 mailserver dns-state
```

To also check SSL/TLS certificates and service ports, run:

```bash
mailserver check
```

Initial DMARC policy:

```text
_dmarc.example.com. TXT "v=DMARC1; p=none; rua=mailto:dmarc@example.com; adkim=s; aspf=s"
```

After successful delivery tests, move gradually to `p=quarantine`, then `p=reject`.

Provider-side PTR/rDNS must be set at the provider that owns the server IP
address. This is not a normal DNS-zone record and is not configured in
Cloudflare DNS. For Hetzner, open the server in Hetzner Cloud Console, go to
`Networking`, find the public IPv4 address, edit `Reverse DNS` / `rDNS`, and set
it to `MAIL_HOSTNAME`.

Expected reverse mapping:

```text
203.0.113.10 -> mail.example.com
```
