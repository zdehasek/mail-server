# DNS Records

Replace example values with `.env` values.

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
sudo make print-dns
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
