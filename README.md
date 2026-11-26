About this fork
===============

This is a maintained fork of [tuxis-ie/nsedit](https://github.com/tuxis-ie/nsedit),
made to run on **PHP 8.4 and newer** (tested with 8.4, 8.5 and 8.6) and **PowerDNS
Authoritative 4.9, 5.0 and 5.1**. It is not affiliated with or endorsed by Tuxis; all credits for
the original work go to its authors (see [Credits](#credits)).

Main changes compared to upstream (details in [CHANGELOG.md](CHANGELOG.md)):

* Works on PHP 8.4, 8.5 and 8.6 (mcrypt replaced by openssl, no deprecations or warnings).
* Works with PowerDNS 4.9, 5.0 and 5.1: cloning zones and "Set PTR Record" fixed.
* Security fixes: access check on every zone action, CSRF on the password form, escaping; current jQuery and jQuery UI.
* Reverse DNS helpers: add the reverse zones for a prefix in one go, move records when a zone is split off,
  and add PTR records by IP address (see [Features](#features)).
* Light and dark theme.
* Tested on FreeBSD, OpenBSD and NetBSD, with reference setups in `contrib/` (see [below](#freebsd-openbsd-and-netbsd)).
* Docker Compose stack (PowerDNS + nsedit), a smoke test and a browser test.
* Tuxis branding (logo and screenshots) removed.
* CI on every pull request and weekly: secrets, vulnerabilities, PHP lint and static analysis, the Docker stack on
  PHP 8.4, 8.5 and 8.6 with PowerDNS 4.9, 5.0 and 5.1. See [Development](#development).
* Releases with a SHA256 checksum and a build provenance attestation, see [Installing](#installing).

Running with Docker
===================

```sh
cp .env.example .env     # fill in PDNS_API_KEY, NSEDIT_ADMIN_PASSWORD (and NSEDIT_SECRET)
chmod 600 .env
docker compose up -d --build
```

nsedit is then available on http://127.0.0.1:8080 and PowerDNS answers DNS
queries on 127.0.0.1:1053 (change `WEB_BIND`, `WEB_PORT`, `DNS_BIND` and
`DNS_PORT` in `.env`). The PowerDNS API is only reachable on the internal Docker
network. Log in with `NSEDIT_ADMIN_USER` / `NSEDIT_ADMIN_PASSWORD`; these are only
used on the first start, after that the users live in the `nsedit-data` volume.

Choose another PHP version with `PHP_VERSION=8.6` and another PowerDNS version with
`PDNS_IMAGE=powerdns/pdns-auth-49:4.9.18` in `.env` (remove the `pdns-data` volume when you go back to an
older PowerDNS: `docker compose down -v`).

Test a running instance with `python3 tests/smoke.py` (it creates and removes
`*.example.` test zones, so don't run it against production). PHP warnings and
deprecations end up in `docker compose logs nsedit`.

What is nsedit?
===============

nsedit is a DNS editor for [PowerDNS](https://www.powerdns.com/). It is created
to finally replace poweradmin and take DNS editing to what we're used at in
2014. It uses the PowerDNS API to make changes in your zones, so you can use
the backend that you want, no matter what.

Features
========
* Import BIND- or AXFR-style dumps of your existing zones
* Add/remove zones and records
* Clone zones
* Add all reverse zones for an IPv4/IPv6 prefix in one go (e.g. 192.0.2.0/22 gives four /24 zones)
* When a zone is split off (e.g. a customer's /56 inside a /32), move its records out of the parent zone
* Add a PTR record by typing the IP address and the hostname (no in-addr.arpa/ip6.arpa name needed)
* Show the DNSsec details of a zone
* Multiple user support
* Allow logging of all actions in NSEdit, including exporting the log in JSON-format
* Light and dark theme: follows the system setting, or chosen by hand with the Theme button (per browser)
* [experimental] nsedit API, to create zones from another system

User support
============
Multiple users are supported. A user can be an admin or a normal user. You can
configure whether or not a normal user is allowed to add new zones.

WeFact Login support
====================
[WeFact](https://www.wefact.com/wefact-hosting/) is _A hosting billing
product_. nsedit can authenticate against the WeFact API, which allows your
customers to login on nsedit with their WeFact credentials. It will
automatically show their domains and allow them to edit them.

Development
===========

Releases: set the version in `VERSION`, add a `## v<version> (date)` section at the top of `CHANGELOG.md` (it is
used as the release notes) and merge that. When CI is green on `master`, push the tag `v<version>`: the
release workflow builds the tarball, its SHA256 and a build provenance attestation and publishes the release.
Tags `v*` cannot be deleted or moved.

`master` is protected: changes go through a pull request, and merging needs a green `check`
(the CI in `.github/workflows/ci.yml`) and a green `test-plan` (`.github/workflows/test-plan.yml`: every
checkbox in the pull request description is ticked, see `ci/test-plan.py`; it runs again when the
description is edited). Force pushes and deleting `master` are blocked, also for admins.
CI runs on every pull request, on `master` and weekly, each check as its own job:

| Job | What |
|---|---|
| `gitleaks` | secrets in the whole git history |
| `dependencies` | trivy fs, and the bundled JavaScript libraries in `vendor/` against OSV (`ci/vendored-js.py`) |
| `lint` | `php -l` on PHP 8.4, 8.5 and 8.6 |
| `quality` | PHPStan level 5 (existing findings in `phpstan-baseline.neon`), ruff on the Python scripts |
| `bandit` | unsafe code in the Python scripts |
| `docker-config` | trivy config on the Dockerfiles and compose file |
| `tests` | Docker stack on PHP 8.4, 8.5 and 8.6 × PowerDNS 4.9, 5.0 and 5.1: `tests/smoke.py`, browser test `tests/ui.py` (Playwright/Chromium, fails on any JavaScript error or console warning), no PHP warnings, DNS answers, internal files not served |
| `docker-images` | trivy image (CRITICAL) on the built images |
| `check` | sums up the jobs above; required for merging |

Accepted findings always have a reason and an expiry date: `.trivyignore.yaml` (trivy) and `.osv-ignore`
(bundled JavaScript).

The browser libraries are bundled in `vendor/`: jQuery 3.7.1, jQuery UI 1.14.2 and jTable 2.6.0. Their
versions, npm checksums and the small patches to jTable are in `vendor/versions.json`; fixes for jTable
with the current jQuery are in `js/jtable-fixes.js`. jTable is unmaintained since 2018: after replacing
a library, run `tests/ui.py` (CI does). Dependabot does not see these files. Dependabot opens update pull requests for GitHub Actions and Docker
images after a cooldown of 14 days. Security issues: see [SECURITY.md](SECURITY.md).

FreeBSD, OpenBSD and NetBSD
===========================

nsedit is tested on **FreeBSD 15.1** in jails (PowerDNS in one jail, nginx + php-fpm + nsedit in another) and
on **OpenBSD 8.0** with httpd and php-fpm chrooted in `/var/www`, and on **NetBSD 11.1** with nginx, php-fpm and
PowerDNS with PostgreSQL from pkgsrc. Reference configurations and scripts to run them in a VM on a Linux laptop
are in [contrib/freebsd/](contrib/freebsd/README.md), [contrib/openbsd/](contrib/openbsd/README.md) and
[contrib/netbsd/](contrib/netbsd/README.md); `contrib/vm-checks.sh` runs the same checks as CI against them.

Requirements
============
* A webserver running PHP 8.4 or newer (tested with 8.4, 8.5 and 8.6)
* PHP extensions curl, sqlite3, session, filter and openssl (on the BSDs session and filter are separate
  packages, e.g. `php84-session` and `php84-filter`; nsedit tells you which one is missing)
* PowerDNS Authoritative with the JSON-api enabled, version 4.4.0 or greater (tested with 4.9, 5.0 and 5.1; see [CHANGELOG.md](CHANGELOG.md#tested-versions))

Installing
==========

* From a release (recommended): download `nsedit-<version>.tar.gz` and its `.sha256` from
  [Releases](https://github.com/madv-zz/nsedit/releases), check it (`sha256sum -c`, and optionally
  `gh attestation verify nsedit-<version>.tar.gz -R madv-zz/nsedit`) and unpack it where nsedit will run.
  The tarball holds nsedit and the BSD reference setups in `contrib/`, without the development and CI files.
* Via Git: run `git clone https://github.com/madv-zz/nsedit.git` in the directory where you want to run
  nsedit from (`master` is the development branch; check out a tag such as `v2.2.0` for a release).

* Copy ```includes/config.inc.php-dist``` to ```includes/config.inc.php``` and edit config.inc.php to your needs.

* By default, nsedit writes its user database to ../etc/pdns.users.sqlite3. Be sure that your webserver can create that directory and write to it. **Make sure the Webserver doesn't serve this file/folder to the public!**

* Visit http(s)://<url>/nsedit/ and login with admin/admin (Don't forget to update your password!)

Have fun ;)

Configuring PowerDNS
====================
Minimal configuration of PowerDNS for supporting nsedit has to include 3 directives:
```
webserver=yes
api=yes
api-key=SomeRandomString
```

nsedit needs PowerDNS 4.4 or newer. If your distribution ships an older version, use the PowerDNS
repositories: https://repo.powerdns.com/


Credits
=======

nsedit was created by [Tuxis](https://www.tuxis.nl/) and its contributors, see the
[upstream repository](https://github.com/tuxis-ie/nsedit). It is licensed under the
GNU General Public License version 2, see [LICENSE](LICENSE); this fork keeps that
license.
