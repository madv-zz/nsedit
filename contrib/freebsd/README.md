# FreeBSD reference setup (tested)

A tested example of nsedit on FreeBSD with **jails**: PowerDNS in jail `pdns` (10.53.0.2) and nginx + php-fpm +
nsedit in jail `nsedit` (10.53.0.3). The PowerDNS API only accepts the nsedit jail. It is a reference for
the configuration, not an installer for production: adapt addresses, keys and paths to your own setup.

Tested on FreeBSD 15.1-RELEASE with PHP 8.4.27 (php-fpm), nginx 1.30 and PowerDNS 5.1.5 (2026-11-25):
`tests/smoke.py` 0 failures, `tests/ui.py` 16 steps without problems, no PHP warnings in the log.

What matters for nsedit:

- **PowerDNS package**: `dns/powerdns` was missing from the FreeBSD 15 *quarterly* package repository
  (2026-11-25); the *latest* repository has 5.1.5 (with sqlite3, MySQL, PostgreSQL and LMDB backends).
- **PHP packages**: `php84 php84-curl php84-sqlite3 php84-session php84-filter` (openssl and json are built
  in); the same for `php85-*` and `php86-*`. nsedit refuses to log in and says which extension is missing.
  Install them from one package repository: with quarterly and latest both enabled, pkg silently skipped an
  extension whose versions differed between the two.
- **API from another jail**: in `pdns.conf` set `webserver-address` to the jail address and
  `webserver-allow-from` to the address of the nsedit jail; in nsedit's `includes/config.inc.php` set
  `$apiip` to the PowerDNS jail address.
- **User database** outside the web root, writable for `www` (here `/var/db/nsedit`).
- **nginx**: deny `includes/`, `templates.d/`, `rotate-logs.php`, `*.sql` and `*-dist` (see `setup-jails.sh`).

## Run it in a VM on a Linux laptop

Needs KVM (`/dev/kvm`, your user in group `kvm`), `qemu-system-x86_64`, Docker (for the seed ISO and the
browser test) and a `.env` in the repository root with `NSEDIT_ADMIN_PASSWORD`.

```sh
contrib/freebsd/vm.sh ~/vms/nsedit-freebsd create   # download FreeBSD 15.1 (checksum checked), disk, seed ISO
contrib/freebsd/vm.sh ~/vms/nsedit-freebsd start    # boot; ssh on 127.0.0.1:2222, nsedit on 127.0.0.1:8180
contrib/freebsd/vm.sh ~/vms/nsedit-freebsd deploy   # this checkout (last commit) into the jails
contrib/freebsd/vm.sh ~/vms/nsedit-freebsd test     # smoke test and browser test against the jail
contrib/freebsd/vm.sh ~/vms/nsedit-freebsd stop
```

`deploy` takes the last commit (`git archive HEAD`), not uncommitted changes. From an empty directory,
`create`, `start` and `deploy` take about 3.5 minutes.
