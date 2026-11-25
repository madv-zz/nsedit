# Changelog

What changed in this fork, from where it started to where it is now.

## Starting point: upstream `master` at `7a18c00` (2025-03-11)

The fork starts from [tuxis-ie/nsedit](https://github.com/tuxis-ie/nsedit) `master`
(last upstream release: v1.1, 2016-08-08; upstream has no changelog). On PHP 8.4+ with
PowerDNS 5 that code had these problems:

- **Broken on PHP 8:** auto-login ("remember me") used mcrypt, which was removed in
  PHP 7.2, so it ended in a fatal error. `rotate-logs.php` had a parse error.
- **Deprecations and warnings on PHP 8.1+ / 8.2+:** `null` arguments to
  `session_set_cookie_params()`, `setcookie()` and `preg_split()`; a dynamic property in
  the WeFact client; warnings for missing form fields and API fields, which could end up
  in the JSON answers and break the tables. Non-admin users saw no zones in the zone
  list for forms (property read on an array).
- **Broken with PowerDNS 5:** cloning a zone failed ("Duplicate RRset ... with
  changetype: REPLACE"). "Set PTR Record" silently did nothing, because PowerDNS removed
  the `set-ptr` API option in 4.4.
- **Bugs in the API client:** the `Content-Type` header was never sent, and certificate
  verification for `https` was only applied when *not* using https.
- **Security:** a normal user could read, change, export, clone and delete any zone by
  passing its name; the change password form had no CSRF protection; SQL injection in
  the creation of the initial admin; unescaped output.
- **Docker:** the `Dockerfile` cloned the unpatched code from GitHub and ran `php -S`.
- **Branding:** "NSEDIT by Tuxis Internet Engineering" logo and screenshots.

## Step 1: `d3f7a31` Make nsedit work on PHP 8.4+ and PowerDNS 5

- `includes/session.inc.php`: auto-login cookie encrypted with openssl AES-256-CBC
  instead of mcrypt (existing auto-login cookies become invalid, users log in once
  again); array form of the cookie functions without `null`; cookies `HttpOnly` and
  `SameSite=Lax`; constant time comparisons (`hash_equals`).
- `includes/class/ApiHandler.php`: `Content-Type` header is sent, https verification
  fixed, clear error and timeouts when PowerDNS cannot be reached, own curl handle per
  request.
- `includes/class/Zone.php`: missing API fields tolerated, arrays initialised, the
  removed `set-ptr` option is no longer sent.
- `zones.php`:
  - nsedit creates the PTR record itself (A and AAAA), in the most specific reverse zone
    the user has access to;
  - cloning works on PowerDNS 5;
  - access check on every zone action;
  - defaults for missing form fields, TTL validation, `preg_split()` limit `-1`;
  - SOA-EDIT-API log lines fixed.
- `includes/misc.inc.php`: prepared statement for the initial admin, integer paging.
- `includes/wefactauth.inc.php`: no dynamic property.
- `index.php`: CSRF token in the change password form, escaped output, robust check
  whether the user database is inside the document root.
- `rotate-logs.php`: parse error fixed.
- README: requirement PHP 8.4 or newer.

## Step 2: `7765a9e` Docker Compose stack, smoke test, README for the fork

- Old `Dockerfile` and `docker-entrypoint.sh` replaced by a `Dockerfile` on
  `php:<version>-apache` (PHP version via `PHP_VERSION`, default 8.4) that uses the code
  of this checkout.
- `docker-compose.yml` with PowerDNS Authoritative 5.0 (sqlite) and nsedit; settings and
  secrets from `.env` (`.env.example`, `.env` is ignored by git). The PowerDNS API is
  only reachable on the internal Docker network.
- `docker/apache-nsedit.conf`: `includes/`, `templates.d/` and `rotate-logs.php` are not
  served.
- `tests/smoke.py`: runs every action through HTTP (zones, records, PTR, clone, slaves,
  users, logs, rights of a normal user, CSRF, change password, auto-login).
- README: section about this fork and about running it with Docker.

## Step 3: `ed83cc0` Replace the Tuxis logo by a neutral NSEDIT logo

- `img/nsedit.png` removed, new `img/nsedit.svg`; it is also the fallback instead of an
  image from tuxis.nl.
- Example template in `config.inc.php-dist` uses example.com.

## Step 4: Remove the screenshots, add this changelog

- `screenshots/` removed (they showed the Tuxis logo) and the README section about them.
- This changelog.
- README: the section "Other methods of installation (Unsupported)" removed. The SUSE
  Studio image no longer exists (SUSE Studio was shut down in 2017) and the original
  Docker file by Yury Evtikhov was replaced in step 2.

## Where it is now

- Runs on PHP 8.4, 8.5 and 8.6 with PowerDNS Authoritative 5.0: the smoke test passes
  all checks on all three versions, without any PHP warning or deprecation in the log.
- Requires PowerDNS 4.4 or newer with the API enabled.
- `docker compose up -d --build` starts PowerDNS and nsedit; see the README.
- No Tuxis branding; the GPLv2 license and the credits to the original authors are kept.
