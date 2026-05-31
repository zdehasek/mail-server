# DNS Records

Replace example values with `mail.env` values.

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
sudo ./scripts/print-dns.sh --config ./mail.env
```

Initial DMARC policy:

```text
_dmarc.example.com. TXT "v=DMARC1; p=none; rua=mailto:dmarc@example.com; adkim=s; aspf=s"
```

After successful delivery tests, move gradually to `p=quarantine`, then `p=reject`.

Provider-side PTR/rDNS must be:

```text
203.0.113.10 -> mail.example.com
```
