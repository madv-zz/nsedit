# OpenBSD reference setup (tested)

A tested example of nsedit on OpenBSD with the base system's own tools: **httpd** and **php-fpm**, both
chrooted in `/var/www`, and PowerDNS with its sqlite backend, its API only on 127.0.0.1. OpenBSD has no
jails; the chroot is what separates the web part. A reference for the configuration, not an installer for
production: adapt addresses, keys and paths to your own setup.

Tested on OpenBSD 8.0 with PHP 8.3.37, 8.4.28 and 8.5.13 (php-fpm) and PowerDNS 5.1.5 (2026-11-25): the same
checks as CI (`contrib/vm-checks.sh`) pass. OpenBSD 8.0 has no PHP 8.6 package yet.

What matters for nsedit:

- **Packages**: `pkg_add php%8.4 php-curl%8.4 php-sqlite3%8.4 powerdns`, then enable the extensions:
  `ln -s /etc/php-8.4.sample/curl.ini /etc/php-8.4/` (and the same for `sqlite3.ini`). session, filter and
  openssl are built in. The sqlite backend is part of the `powerdns` package.
- **Paths inside the chroot**: in `includes/config.inc.php` the user database is `/nsedit-data/...`, which is
  `/var/www/nsedit-data` outside the chroot; PHP's `session.save_path` is `/tmp` = `/var/www/tmp`.
- **API**: PowerDNS listens on 127.0.0.1:8081 and only accepts 127.0.0.1; the chrooted php-fpm can still
  connect to it (no DNS lookup is needed for an IP address).
- **httpd**: block `includes/`, `templates.d/`, `rotate-logs.php`, `*.sql` and `*-dist` before the `*.php`
  location (see `setup.sh`).

## Run it in a VM on a Linux laptop

Needs KVM (`/dev/kvm`, your user in group `kvm`), `qemu-system-x86_64`, Docker (browser test) and a `.env` in
the repository root with `NSEDIT_ADMIN_PASSWORD`.

```sh
contrib/openbsd/vm.sh ~/vms/nsedit-openbsd create          # autoinstall(8) over the network, about 1.5 minutes
PHPV=8.4 contrib/openbsd/vm.sh ~/vms/nsedit-openbsd deploy # this checkout (last commit); PHPV 8.3, 8.4 or 8.5
contrib/openbsd/vm.sh ~/vms/nsedit-openbsd test            # the checks of the CI tests job
contrib/openbsd/vm.sh ~/vms/nsedit-openbsd stop            # later: start
```

`create` checks `pxeboot` and `bsd.rd` against the release's SHA256 list and the installer verifies the sets
with signify. The answers come from a response file that is served on 127.0.0.1:8099 only during the install
and removed afterwards; the root password in it is random and not kept (root logs in with the SSH key).
