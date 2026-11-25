# Changelog

What changed in this fork, from where it started to where it is now.

## Tested versions

Every pull request, every change on `master` and a weekly run test nsedit (`tests/smoke.py` and the browser
test `tests/ui.py`) on every combination of:

| Component | Versions | Note |
|---|---|---|
| PHP | 8.4, 8.5, 8.6 | FreeBSD, OpenBSD and pkgsrc ship all three (2026-11-25) |
| PowerDNS Authoritative | 4.9.18, 5.0.8, 5.1.5 | FreeBSD and OpenBSD ship 5.1.5, pkgsrc 5.1.2 to 5.1.5 (2026-11-25) |
| jQuery / jQuery UI / jTable | 3.7.1 / 1.14.2 / 2.6.0 | bundled in `vendor/` |

The tests run in Docker on Linux (the `php:<version>-apache` and `powerdns/pdns-auth-*` images). Also tested,
by hand, on **FreeBSD 15.1** in jails with nginx + php-fpm 8.4 and PowerDNS 5.1.5 (`contrib/freebsd/`).
nsedit itself only needs PHP with curl, sqlite3 and openssl, and the PowerDNS API.

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

## Step 5: CI, repository protection and hardening

- `.github/workflows/ci.yml`: the checks of the Forgejo setup as separate jobs (gitleaks, dependencies,
  lint, quality, bandit, docker-config, tests, docker-images) and a required summary job `check`; runs on
  every pull request, on `master` and weekly. Actions pinned on commit SHA, tool versions pinned.
- `ci/vendored-js.py`: checks the bundled jQuery, jQuery UI and jTable against OSV. It found 8 known XSS
  vulnerabilities in jQuery 1.10.2 and jQuery UI 1.11.x; they are accepted in `.osv-ignore` until
  2027-01-31, the upgrade is issue #2.
- PHPStan level 5 with a baseline of the existing findings (global configuration variables); two real type
  errors fixed (`curl_setopt()` and `json_decode()` got an int instead of a bool), unused property removed.
- nsedit container runs as `www-data` instead of root (Apache on port 8080) and has a health check.
- PowerDNS runs from an own image (`pdns/Dockerfile`) that installs the Debian security updates the
  official image does not have yet (8 CRITICAL vulnerabilities fixed); the nsedit image does the same.
  Remaining findings without a fix are accepted in `.trivyignore.yaml` until 2027-02-25.
- Build tooling of the bundled jQuery UI removed (`jquery-ui/package.json`, `Gruntfile.js`, `build/`): nsedit
  only loads the JavaScript files, and Dependabot reported vulnerabilities in that unused tooling (grunt).
  The version is kept in `jquery-ui/VERSION` for `ci/vendored-js.py`.
- Dependabot for GitHub Actions and Docker images (14 days cooldown), `SECURITY.md` with private
  vulnerability reporting.
- GitHub settings (not in git): ruleset on `master` (pull request and green `check` required, no force
  push or deletion, also not for admins), secret scanning with push protection, Dependabot alerts and
  security updates, private vulnerability reporting, issues enabled.

## Step 6: current jQuery and jQuery UI, browser test (closes #2)

- jQuery 1.10.2 → **3.7.1**, jQuery UI 1.11.5-pre (unbuilt source checkout of 2014) → **1.14.2**, jTable
  2.4.0 → **2.6.0**; taken from npm with checked checksums, bundled in `vendor/` with `vendor/versions.json`.
  jQuery 3.7.1 instead of 4.0, because jTable uses `$.isFunction`, `$.type` and `$.trim`, which jQuery 4
  removed. No known vulnerabilities left; `.osv-ignore` is empty. The old `jquery-ui/` (629 files: demos,
  tests, 23 old jQuery copies) and `jtable/` are removed.
- Regression found by the new browser test and fixed in `js/jtable-fixes.js`: a record that was created or
  changed less than 5 seconds before was deleted on the server but stayed in the table (jTable waited for an
  animation that does not finish with jQuery UI 1.14).
- jTable: the `unload` handler is removed (Chrome blocks it, a console error on every page, also before this
  change) and the theme no longer loads the Open Sans font from Google (a dead URL that also sent the
  visitor's IP address to Google); only the blue metro theme is kept.
- `tests/ui.py`: browser test with Playwright/Chromium in CI on PHP 8.4, 8.5 and 8.6: login, zones, records
  (add, edit, delete, search), export download, clone dialog, users, logs, logout. Fails on any JavaScript
  error, console warning, failed request or error answer of nsedit.

## Step 7: fixes from the code review

A review of the work above found these problems; each now has a test in `tests/smoke.py` that fails
without the fix (except the SOA serial of reverse zones, see below).

- **Set PTR Record** (`zones.php`):
  - a customer whose reverse zone belongs to the admin (the usual case) got "You don't have access to
    this zone" after the A/AAAA record was already saved; nsedit now only uses reverse zones the user may
    change and otherwise just skips the PTR (logged);
  - a failing PTR (for example a CNAME at that name) was reported as a failed save although the forward
    record was saved; the PTR is now planned before saving and a failure afterwards is logged;
  - an invalid address gives an error before anything is saved;
  - changing the address of a record with "Set PTR" left the old PTR; it is now removed when it still
    points to the record's name;
  - the reverse zone gets SOA-EDIT-API like the forward zone, so its serial goes up and secondaries
    transfer the PTR (only matters for reverse zones created outside nsedit; not covered by the test).
- **Clone**: the new zone keeps its own SOA instead of the source's (whose SOA named the source zone).
- **Password change**: redirect after the change (POST-redirect-GET); with `NSEDIT_SECRET` the page
  otherwise kept a CSRF token of the old password and every action failed until a reload.
- **Passwords starting with `$6$`** were stored unhashed (the user could not log in any more, and anyone
  could set a crypt hash as password); passwords from forms are now always hashed.
- **WeFact login**: TLS certificate verification turned on (it was off, so the API key and the login
  answer could be intercepted).
- **`.dockerignore`**: a local `includes/config.inc.php` (API key, passwords) and `etc/` (user database)
  no longer end up in an image layer.
- Smoke test checks that the export really contains the zone with its SOA (it only checked `Result`).

## Step 8: tested against PowerDNS 4.9, 5.0 and 5.1

- The PowerDNS version of the test stack is a setting (`PDNS_IMAGE` in `.env`, build argument of
  `pdns/Dockerfile`); the default is now 5.1.5, the version FreeBSD and OpenBSD ship.
- CI tests every combination of PHP 8.4/8.5/8.6 and PowerDNS 4.9.18/5.0.8/5.1.5 (9 jobs) and checks that
  the intended PowerDNS version really runs. All passed without changes to nsedit.
- "Tested versions" table at the top of this changelog.

## Step 9: tested on FreeBSD in jails; HTTP status under php-fpm

- Tested in a FreeBSD 15.1 VM with two jails: PowerDNS 5.1.5 and nginx + php-fpm 8.4 + nsedit. Smoke test
  and browser test pass, no PHP warnings. The setup is in `contrib/freebsd/` (`setup-jails.sh` for the jails,
  `vm.sh` to create, start, deploy and test the VM on a Linux laptop with KVM).
- **Fixed, found on FreeBSD:** nsedit sent `Status: 403` / `Status: 400` headers before its JSON errors.
  mod_php (the Docker image) ignores such a header, php-fpm makes it the real HTTP status. jTable then only
  showed "An error occured while communicating to the server" instead of the message (for example "You don't
  have access to this zone"). JSON errors for jTable are now always HTTP 200 (as before under Apache), not
  logged in is a plain redirect, and a wrong admin API key is a real 403 (`http_response_code()`) everywhere.
- Note for FreeBSD: `dns/powerdns` was missing from the quarterly package repository of FreeBSD 15; the
  latest repository has 5.1.5.

## Where it is now

- Runs on PHP 8.4, 8.5 and 8.6 with PowerDNS Authoritative 5.0: the smoke test passes
  all checks on all three versions, without any PHP warning or deprecation in the log.
- Every change goes through a pull request with CI; `master` is protected.
- Runs on FreeBSD in jails (nginx + php-fpm); reference setup in `contrib/freebsd/`.
- jQuery 3.7.1, jQuery UI 1.14.2 and jTable 2.6.0 without known vulnerabilities; jTable itself is
  unmaintained, the browser test guards it.
- Tested with PowerDNS 4.9, 5.0 and 5.1 (API enabled) on PHP 8.4, 8.5 and 8.6; see Tested versions.
- `docker compose up -d --build` starts PowerDNS and nsedit; see the README.
- No Tuxis branding; the GPLv2 license and the credits to the original authors are kept.
