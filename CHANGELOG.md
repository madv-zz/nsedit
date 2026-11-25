# Changelog

What changed in this fork, from where it started to where it is now.

## v2.0.0 (2026-11-25)

First release of this fork of [tuxis-ie/nsedit](https://github.com/tuxis-ie/nsedit) (upstream's last release is
v1.1 from 2016). The details of every change are in the steps further down.

**What it brings**

- Runs on PHP 8.4, 8.5 and 8.6 and PowerDNS Authoritative 4.9, 5.0 and 5.1, without PHP warnings or
  deprecations; tested on Debian, FreeBSD 15.1 (jails, nginx + php-fpm) and OpenBSD 8.0 (httpd + php-fpm in
  a chroot), see *Tested versions*.
- PowerDNS 5: cloning zones works again, "Set PTR Record" is done by nsedit itself (PowerDNS removed `set-ptr`).
- Security: access check on every zone action, CSRF on the password form, escaped output, TLS verification
  for WeFact, passwords always hashed; jQuery 3.7.1 and jQuery UI 1.14.2 without known vulnerabilities.
- Tested reference setups for FreeBSD and OpenBSD in `contrib/`.

**Requirements**

- PHP 8.4 or newer with the extensions curl, sqlite3, session, filter and openssl (nsedit says which one is
  missing). On the BSDs session and filter are separate packages.
- PowerDNS Authoritative 4.4 or newer with the API enabled.

**Upgrading from upstream nsedit**

- Keep your `includes/config.inc.php` and the user database; their format did not change.
- If your config sets `$logo = 'img/nsedit.png'`, change it to `img/nsedit.svg` or your own logo: the Tuxis
  logo is no longer included.
- "Remember me" cookies of the old version are no longer valid; users log in once more.
- Errors for the web interface are always HTTP 200 with a JSON message (also under php-fpm); a wrong admin
  API key gives HTTP 403.

**Download and verify**

```sh
curl -LO https://github.com/madv-zz/nsedit/releases/download/v2.0.0/nsedit-2.0.0.tar.gz
curl -LO https://github.com/madv-zz/nsedit/releases/download/v2.0.0/nsedit-2.0.0.tar.gz.sha256
sha256sum -c nsedit-2.0.0.tar.gz.sha256          # FreeBSD/OpenBSD: sha256 -c or compare with sha256 -q
gh attestation verify nsedit-2.0.0.tar.gz -R madv-zz/nsedit   # built by this repository's release workflow
```

## Tested versions

| Operating system | Web server | PHP | PowerDNS Authoritative | How |
|---|---|---|---|---|
| Debian 13 (trixie), in Docker on Ubuntu 24.04 | Apache 2.4 + mod_php | 8.4, 8.5, 8.6 | 4.9.18, 5.0.8, 5.1.5 | CI on every pull request, every change on `master` and weekly: all 9 combinations |
| FreeBSD 15.1-RELEASE, in two jails | nginx 1.30.7 + php-fpm | 8.4.27, 8.5.12, 8.6.0RC3 | 5.1.5 | by hand, in a VM (`contrib/freebsd/vm.sh`) |
| OpenBSD 8.0, httpd + php-fpm chrooted in `/var/www` | httpd (base) + php-fpm | 8.3.37, 8.4.28, 8.5.13 | 5.1.5 | by hand, in a VM (`contrib/openbsd/vm.sh`) |
| NetBSD 11.1, pkgsrc 2026Q3 | nginx 1.30.7 + php-fpm | 8.4.28, 8.5.13 | 5.1.4 (PostgreSQL backend) | by hand, in a VM (`contrib/netbsd/vm.sh`) |

All run the same checks (`contrib/vm-checks.sh` for the VMs): `tests/smoke.py`, the browser test `tests/ui.py`, no
PHP warnings, DNS answers and that internal files are not served. On the BSDs one PowerDNS version is packaged
(5.1.5, NetBSD's pkgsrc 5.1.4); FreeBSD ships PHP 8.6 as a release candidate so far, OpenBSD 8.0 and pkgsrc not at all. Bundled in `vendor/`: jQuery 3.7.1, jQuery UI 1.14.2, jTable 2.6.0.

FreeBSD ships PHP 8.2 to 8.6 and PowerDNS 5.1.5 (in the
*latest* package repository; it was missing from *quarterly*). nsedit itself only needs PHP with curl,
sqlite3 and openssl, and the PowerDNS API.

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

## Step 9: the test plan of a pull request must be done

- New workflow `test-plan` (`ci/test-plan.py`): fails while the description of a pull request has an
  unticked checkbox, or has no test plan at all (bots such as Dependabot excepted). It runs again when the
  description is edited, without starting the whole CI again. Required for merging, next to `check`.

## Step 10: tested on FreeBSD in jails; HTTP status under php-fpm

- Tested in a FreeBSD 15.1 VM with two jails: PowerDNS 5.1.5 and nginx + php-fpm 8.4 + nsedit. Smoke test
  and browser test pass, no PHP warnings. The setup is in `contrib/freebsd/` (`setup-jails.sh` for the jails,
  `vm.sh` to create, start, deploy and test the VM on a Linux laptop with KVM).
- **Fixed, found on FreeBSD:** nsedit sent `Status: 403` / `Status: 400` headers before its JSON errors.
  mod_php (the Docker image) ignores such a header, php-fpm makes it the real HTTP status. jTable then only
  showed "An error occured while communicating to the server" instead of the message (for example "You don't
  have access to this zone"). JSON errors for jTable are now always HTTP 200 (as before under Apache), not
  logged in is a plain redirect, and a wrong admin API key is a real 403 (`http_response_code()`) everywhere.
- Found on FreeBSD too: nsedit needed the PHP `ctype` extension since step 1 (`ctype_digit()` for the TTL),
  a separate package there; replaced by a regular expression. nsedit now also refuses to log in with a clear
  message when the `session` or `filter` extension is missing (separate packages on BSD).
- `contrib/vm-checks.sh`: the checks of the CI tests job for a VM; tested with PHP 8.4, 8.5 and 8.6 on FreeBSD.
- **OpenBSD 8.0** (`contrib/openbsd/`): httpd and php-fpm from the base system chrooted in `/var/www`, PowerDNS
  5.1.5 with sqlite; installed with autoinstall(8) over the network in a VM, from an empty directory to all checks
  passed in 2.5 minutes; PHP 8.3, 8.4 and 8.5 pass without changes to nsedit.
- CI quality job: shellcheck on all shell scripts, ruff and bandit also on `contrib/`.
- Note for FreeBSD: `dns/powerdns` was missing from the quarterly package repository of FreeBSD 15; the
  latest repository has 5.1.5. Install PHP from one repository: with both enabled, pkg silently skipped an
  extension whose versions differed between them.

## Step 11: release v2.0.0

- `VERSION`, the `## v2.0.0` section at the top of this changelog (the release notes) and a release workflow:
  a tag `v<version>` builds `nsedit-<version>.tar.gz` without the development files (`.gitattributes`
  export-ignore), its SHA256 and a build provenance attestation, but only for a commit on which CI passed.
- Ruleset "release tags": tags `v*` cannot be deleted or moved, also not by admins.
- Pull request template: the test plan lists only what was checked by hand; no "CI green" item, CI is
  enforced by the required `check`.

## Step 12: tested on NetBSD

- **NetBSD 11.1** (`contrib/netbsd/`): nginx + php-fpm from pkgsrc, PowerDNS 5.1.4 with the PostgreSQL backend
  (pkgsrc has no sqlite backend for PowerDNS; `powerdns-pgsql` needs the PostgreSQL 16 client, so
  `postgresql16-server`). PHP 8.4.28 and 8.5.13 pass all checks without changes to nsedit.
- `vm.sh` installs NetBSD with anita 2.18 (NetBSD's install-test tool, tarball checked against a fixed SHA256)
  and runs the VM without IPv6 in QEMU's network (pkgsrc's CDN answers with IPv6 first and downloads hung).

## Step 15: PTR records by IP address

- A PTR record can be added or changed in a reverse zone by typing the IP address as name and the
  hostname as content, e.g. `185.69.204.123` and `mail.example.nl`, instead of `123.204.69.185.in-addr.arpa.`
  and `mail.example.nl.`. nsedit turns the address (IPv4 or IPv6) into its reverse name, refuses an
  address outside the zone, and adds the final dot to the hostname. Relative names (`123`) and full
  reverse names keep working as before.
- Tooltip on the **Label** field of the record form: in a reverse zone it names an address of that zone
  as example (e.g. `203.0.113.10`), in a forward zone it explains relative and absolute names.

## Where it is now

- Runs on PHP 8.4, 8.5 and 8.6 with PowerDNS Authoritative 4.9, 5.0 and 5.1: the smoke test and the
  browser test pass on every combination, without any PHP warning or deprecation in the log.
- Every change goes through a pull request with CI and a ticked test plan; `master` and release tags are
  protected; releases with a checked tarball from v2.0.0 on.
- Runs on FreeBSD in jails, OpenBSD in a chroot and NetBSD with pkgsrc; reference setups in `contrib/`.
- jQuery 3.7.1, jQuery UI 1.14.2 and jTable 2.6.0 without known vulnerabilities; jTable itself is
  unmaintained, the browser test guards it.
- Tested with PowerDNS 4.9, 5.0 and 5.1 (API enabled) on PHP 8.4, 8.5 and 8.6; see Tested versions.
- `docker compose up -d --build` starts PowerDNS and nsedit; see the README.
- No Tuxis branding; the GPLv2 license and the credits to the original authors are kept.
