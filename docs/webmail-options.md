# Webmail And DAV Options

## Default: Roundcube + Radicale

The default is stable and composable:

- Email transport/storage: Postfix and Dovecot.
- Webmail: pinned upstream Roundcube release.
- Contacts/calendar sync: Radicale.

This avoids a heavy groupware suite while using mature components.

## Roundcube

Roundcube is mature and widely deployed. This installer uses a pinned upstream Roundcube release instead of the Ubuntu 26.04 package because the packaged Roundcube 1.6.x build is not currently compatible with PHP 8.5. The pinned upstream release keeps the install reproducible while avoiding that runtime breakage.

Roundcube provides reliable browser-based IMAP/SMTP webmail and a built-in address book. This installer does not enable a Roundcube calendar plugin.

## Radicale

Radicale is a minimal CalDAV/CardDAV server. It stores data as flat files, has a small Python footprint, and works with standard clients such as Apple Calendar/Contacts, Thunderbird, and DAVx5 on Android.

## Calendar UI Recommendation

The recommended default is Roundcube plus Radicale:

- Use Roundcube for webmail.
- Use Radicale for the actual CalDAV/CardDAV storage and sync.
- Use native clients such as iPhone Calendar, macOS Calendar, Thunderbird Calendar, or DAVx5 with an Android calendar app against the same Radicale endpoint.

There is no bundled browser calendar UI. If browser calendar access becomes necessary, add it as a separate CalDAV web client instead of coupling it to Roundcube.

## SnappyMail

SnappyMail is lighter and more modern than Roundcube, but it is not packaged by Ubuntu and would require maintaining another pinned upstream web application. Roundcube is preferred here because it is more widely deployed and conservative.

## SOGo

SOGo provides webmail, contacts, calendars, CalDAV/CardDAV, sharing, and optional ActiveSync in one app. It is useful for larger groupware needs, but it requires more moving parts and is overbuilt for this minimal installer.
