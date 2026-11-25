About this fork
===============

This is a maintained fork of [tuxis-ie/nsedit](https://github.com/tuxis-ie/nsedit),
made to run on **PHP 8.4 and newer** (tested with 8.4, 8.5 and 8.6) and **PowerDNS
Authoritative 4.9, 5.0 and 5.1**. It is not affiliated with or endorsed by Tuxis; all credits for
the original work go to its authors (see [Credits](#credits)).

Main changes compared to upstream (details in [CHANGELOG.md](CHANGELOG.md)):

* Works on PHP 8.4, 8.5 and 8.6 (mcrypt replaced by openssl, no deprecations or warnings).
* Works with PowerDNS 4.9, 5.0 and 5.1: cloning zones and "Set PTR Record" fixed.
* Security fixes: access check on every zone action, CSRF on the password form, escaping.
* Docker Compose stack (PowerDNS + nsedit) and a smoke test.
* Tuxis branding (logo and screenshots) removed.
* CI on every pull request and weekly: secrets, vulnerabilities, PHP lint and static analysis, the Docker stack on PHP 8.4, 8.5 and 8.6. See [Development](#development).

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
* Show the DNSsec details of a zone
* Multiple user support
* Allow logging of all actions in NSEdit, including exporting the log in JSON-format
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

`master` is protected: changes go through a pull request, and merging needs a green `check`
(the CI in `.github/workflows/ci.yml`; force pushes and deleting `master` are blocked, also for admins).
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

Requirements
============
* A webserver running PHP 8.4 or newer (tested with 8.4, 8.5 and 8.6)
* php sqlite3
* php curl
* php with openssl support
* PowerDNS Authoritative with the JSON-api enabled, version 4.4.0 or greater (tested with 4.9, 5.0 and 5.1; see [CHANGELOG.md](CHANGELOG.md#tested-versions))

Installing
==========

* Via Git
    -  Run git clone in the directory where you want to run nsedit from
    : ```git clone https://github.com/madv-zz/nsedit.git```

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

Special note for Ubuntu Xenial Xerus 16.04 users:
Default `pdns` package included in Ubuntu repositories has the version of 4.0.0-alpha2 and *nsedit v1.0* doesn't work with it due to API incompatibility.

If your PowerDNS version is not the latest one, please consider adding PowerDNS repository to your system.

Detailed instructions for adding repository are available at http://repo.powerdns.com/


Credits
=======

nsedit was created by [Tuxis](https://www.tuxis.nl/) and its contributors, see the
[upstream repository](https://github.com/tuxis-ie/nsedit). It is licensed under the
GNU General Public License version 2, see [LICENSE](LICENSE); this fork keeps that
license.
