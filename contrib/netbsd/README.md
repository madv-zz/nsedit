# NetBSD reference setup (tested)

A tested example of nsedit on NetBSD with pkgsrc packages: **nginx** and **php-fpm**, and PowerDNS with the
**PostgreSQL** backend, its API only on 127.0.0.1. A reference for the configuration, not an installer for
production: adapt addresses, keys and paths to your own setup.

Tested on NetBSD 11.1 with PHP 8.4.28 and 8.5.13 (php-fpm), nginx 1.30.7, PowerDNS 5.1.4 and PostgreSQL 16
(pkgsrc 2026Q3, 2026-11-25): the same checks as CI (`contrib/vm-checks.sh`) pass. pkgsrc has no PHP 8.6 yet.

What matters for nsedit:

- **No sqlite backend for PowerDNS in pkgsrc**: the backends are separate packages (`powerdns-pgsql`,
  `powerdns-mysql`, `-ldap`, `-odbc`, `-geoip`); the base package only has bind, pipe and remote. This setup
  uses PostgreSQL. `powerdns-pgsql` is built against the PostgreSQL **16** client, so use `postgresql16-server`.
  nsedit only talks to the PowerDNS API and does not care which backend PowerDNS uses.
- **Packages**: `pkgin install php84 php84-curl php84-sqlite3 php84-fpm nginx powerdns powerdns-pgsql
  postgresql16-server`. pkgsrc enables the PHP extensions itself (`/usr/pkg/etc/php/8.4/php.d/`); session,
  filter and openssl are built in. Several PHP versions can be installed side by side (`php84`, `php85`).
- **rc.d scripts** come as examples: copy them from `/usr/pkg/share/examples/rc.d/` to `/etc/rc.d/` and enable
  them in `/etc/rc.conf`. The PostgreSQL rc script writes its error log to `/usr/pkg/pgsql`, which must belong
  to `pgsql`.
- **php-fpm** runs as `fpm:www`; `setup.sh` lets it listen on 127.0.0.1:9000 for nginx.
- **Downloads**: use `cdn.netbsd.org`; `ftp.netbsd.org` was very slow (about 30 kB/s, 2026-11-25).

## Run it in a VM on a Linux laptop

Needs KVM (`/dev/kvm`, your user in group `kvm`), `qemu-system-x86_64`, python3, Docker and a `.env` in the
repository root with `NSEDIT_ADMIN_PASSWORD`.

```sh
contrib/netbsd/vm.sh ~/vms/nsedit-netbsd create           # anita installs NetBSD 11.1 (sets ~500 MB)
contrib/netbsd/vm.sh ~/vms/nsedit-netbsd start            # ssh on 127.0.0.1:2224, nsedit on 127.0.0.1:8182
PHPV=8.4 contrib/netbsd/vm.sh ~/vms/nsedit-netbsd deploy  # this checkout (last commit); PHPV 8.4 or 8.5
contrib/netbsd/vm.sh ~/vms/nsedit-netbsd test             # the checks of the CI tests job
```

NetBSD's installer is menu driven; `create` uses [anita](https://www.gson.org/netbsd/anita/), NetBSD's own tool
for automated install tests, version 2.18 in a virtualenv, its tarball checked against a fixed SHA256 (the same
code as tag `v2_18` on GitHub). anita needs `mkisofs`; `vm.sh` provides it as xorriso in a container. The VM runs
without IPv6 in QEMU's network: pkgsrc's CDN answers with IPv6 addresses first, QEMU's NAT does not route IPv6,
and downloads then hung.
