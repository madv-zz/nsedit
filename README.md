About this fork
===============

This is a maintained fork of [tuxis-ie/nsedit](https://github.com/tuxis-ie/nsedit),
made to run on **PHP 8.4 and newer** (tested with 8.4, 8.5 and 8.6) and **PowerDNS
Authoritative 5.0**. It is not affiliated with or endorsed by Tuxis; all credits for
the original work go to its authors (see [Credits](#credits)).

Changes compared to upstream:

* PHP 8: mcrypt (removed in PHP 7.2) replaced by openssl for the auto-login cookie,
  no `null` arguments to internal functions, no dynamic properties, no warnings for
  missing form fields, parse error in `rotate-logs.php` fixed.
* PowerDNS 5: cloning zones works again (duplicate rrsets are rejected by PowerDNS 5),
  and "Set PTR Record" is done by nsedit itself, because PowerDNS removed `set-ptr`
  from its API in 4.4.
* Security: access check on every zone action (a normal user could read and change
  any zone by its name), CSRF token on the change password form, escaped output,
  prepared statement for the initial admin user, constant time comparisons.
* API client: Content-Type header is sent, https certificate verification works,
  clear errors and timeouts when PowerDNS cannot be reached.
* A Docker Compose stack (PowerDNS + nsedit) and a smoke test, see
  [Running with Docker](#running-with-docker).
* The Tuxis logo is replaced by a neutral NSEDIT logo.

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

Choose another PHP version with `PHP_VERSION=8.6` in `.env`.

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

Requirements
============
* A webserver running PHP 8.4 or newer (tested with 8.4, 8.5 and 8.6)
* php sqlite3
* php curl
* php with openssl support
* PowerDNS with the JSON-api enabled. Version 4.4.0 or greater (tested with 5.0)

Installing
==========

* Via Git
    -  Run git clone in the directory where you want to run nsedit from
    : ```git clone https://github.com/madv-zz/nsedit.git```

* Copy ```includes/config.inc.php-dist``` to ```includes/config.inc.php``` and edit config.inc.php to your needs.

* By default, nsedit writes its user database to ../etc/pdns.users.sqlite3. Be sure that your webserver can create that directory and write to it. **Make sure the Webserver doesn't serve this file/folder to the public!**

* Visit http(s)://<url>/nsedit/ and login with admin/admin (Don't forget to update your password!)

Have fun ;)

Other methods of installation (Unsupported)
===========================================

* Baji Zsolt created a Suse image: https://susestudio.com/a/vvnMqa/powerdns-with-nsedit
* Yury Evtikhov created the original Docker file (replaced in this fork by the Docker Compose stack)

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


Screenshots
===========

![The login screen](screenshots/login.png)
![Master zones](screenshots/master-import-zones.png)
![Slave zones](screenshots/slavezones.png)



Credits
=======

nsedit was created by [Tuxis](https://www.tuxis.nl/) and its contributors, see the
[upstream repository](https://github.com/tuxis-ie/nsedit). It is licensed under the
GNU General Public License version 2, see [LICENSE](LICENSE); this fork keeps that
license.
