# Changelog

All notable changes of this fork are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Upstream ([tuxis-ie/nsedit](https://github.com/tuxis-ie/nsedit)) has no changelog; its
last release is v1.1 (2016-08-08). This fork starts from upstream `master` at commit
`7a18c00` (2025-03-11).

## [Unreleased]

### Requirements
- PHP 8.4 or newer (tested with 8.4, 8.5 and 8.6) with curl, sqlite3 and openssl.
- PowerDNS Authoritative 4.4 or newer with the API enabled (tested with 5.0).

### Added
- Docker Compose stack with PowerDNS Authoritative 5.0 (sqlite backend) and nsedit on
  `php:<version>-apache`; the PHP version is chosen with `PHP_VERSION`. Configuration and
  secrets come from `.env` (see `.env.example`).
- Apache configuration that keeps `includes/`, `templates.d/` and `rotate-logs.php` out of
  reach of the web.
- `tests/smoke.py`: smoke test that runs every action through HTTP, including the access
  checks for normal users, CSRF, PTR creation, cloning and auto-login.
- nsedit creates PTR records itself for A/AAAA records with "Set PTR Record", in the most
  specific reverse zone the user has access to. PowerDNS removed the `set-ptr` option
  from its API in 4.4, so this option silently did nothing.
- TTL validation: a TTL that is not a positive number is refused.

### Changed
- Auto-login cookie ("remember me") is encrypted with openssl AES-256-CBC instead of
  mcrypt. Existing auto-login cookies are no longer valid; users log in once again.
- Session and auto-login cookies are `HttpOnly` and `SameSite=Lax`.
- Passwords, API keys and HMACs are compared in constant time (`hash_equals`).
- The API client uses timeouts and gives a clear error when PowerDNS cannot be reached.
- The old `Dockerfile` (which cloned the unpatched upstream code and used `php -S`) and
  `docker-entrypoint.sh` are replaced by the Docker Compose stack.
- Requirement in the README raised to PHP 8.4+ and PowerDNS 4.4+.

### Fixed
- PHP 8: fatal error on auto-login because mcrypt no longer exists (removed in PHP 7.2).
- PHP 8.1+: deprecations for `null` arguments to `session_set_cookie_params()`,
  `setcookie()` and `preg_split()`.
- PHP 8.2+: deprecation for a dynamic property in the WeFact client.
- PHP 8: warnings for missing form fields (`disabled`, `ttl`, `setptr`, `nameserver`,
  `template`, ...) and missing API fields, which could break the JSON responses.
- PHP 8: warning for reading a property of an array in the zone list for forms, which
  made non-admin users see no zones there.
- Parse error in `rotate-logs.php`.
- Cloning a zone failed on PowerDNS 5 ("Duplicate RRset ... with changetype: REPLACE"):
  the rrsets of the new zone were sent together with those of the source zone.
- The API client never sent the `Content-Type` header, and certificate verification for
  `https` was only applied when *not* using https.
- Log lines for SOA-EDIT-API changes put the zone name in the user column.
- Edit/delete of a record that no longer exists gave a fatal error instead of a message.

### Security
- Normal users could read, change, export, clone and delete any zone by passing its
  name; every zone action now checks that the user owns the zone.
- Cloning a zone was possible for normal users even when adding zones is not allowed.
- The change password form had no CSRF protection.
- SQL injection in the creation of the initial admin user (now a prepared statement).
- Unescaped output (user name, nameservers from templates) in HTML.
- Check whether the user database is inside the document root works with real paths
  instead of a regular expression built from the document root.

### Removed
- Tuxis branding: the "NSEDIT by Tuxis Internet Engineering" logo (replaced by a neutral
  `img/nsedit.svg`, also used as fallback instead of loading an image from tuxis.nl), the
  screenshots and the Tuxis example in `config.inc.php-dist`. This fork is not affiliated
  with Tuxis; credits for the original work are in the README.
