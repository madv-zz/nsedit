#!/bin/sh
# Builds two FreeBSD jails in the test VM: "pdns" (PowerDNS + sqlite) and "nsedit" (nginx + php-fpm + nsedit).
# Run as root in the VM:  ssh ... 'PHP=php85 sh -s' < setup-jails.sh   (PHP: php84 (default), php85 or php86)
# Expects: /root/nsedit.tar (git archive of nsedit), /root/nsedit-admin-pw (admin password, mode 600).
# Idempotent enough to run again after changing the nsedit code (it replaces /usr/local/www/nsedit).
set -eu

REL=$(freebsd-version | sed 's/-p[0-9]*$//')
PHP=${PHP:-php84}
PDNS_IP=10.53.0.2
NSEDIT_IP=10.53.0.3
J=/jails

log() { echo "== $*"; }

# --- host: loopback for the jails, pf redirect of port 8180 to nginx in the nsedit jail -------------------
sysrc -q cloned_interfaces="lo1" >/dev/null
ifconfig lo1 >/dev/null 2>&1 || ifconfig lo1 create
cat > /etc/pf.conf <<EOF
ext_if="vtnet0"
rdr pass on \$ext_if inet proto tcp from any to (\$ext_if) port 8180 -> $NSEDIT_IP port 80
pass all
EOF
sysrc -q pf_enable=YES >/dev/null
service pf status >/dev/null 2>&1 && pfctl -q -f /etc/pf.conf || service pf start >/dev/null

# --- base system for both jails ------------------------------------------------------------------------------
if [ ! -f /root/base.txz ]; then
    log "fetch base.txz $REL"
    fetch -q -o /root/base.txz "https://download.freebsd.org/releases/amd64/$REL/base.txz"
fi
for j in pdns nsedit; do
    if [ ! -f $J/$j/bin/sh ]; then
        log "extract base into $J/$j"
        mkdir -p $J/$j && tar -xf /root/base.txz -C $J/$j
    fi
    cp /etc/resolv.conf $J/$j/etc/
done

cat > /etc/jail.conf <<EOF
exec.start = "/bin/sh /etc/rc";
exec.stop = "/bin/sh /etc/rc.shutdown";
exec.clean;
mount.devfs;
path = "$J/\$name";
host.hostname = "\$name.jail";
pdns   { ip4.addr = "lo1|$PDNS_IP/32"; }
nsedit { ip4.addr = "lo1|$NSEDIT_IP/32"; }
EOF
sysrc -q jail_enable=YES jail_list="pdns nsedit" >/dev/null

# --- packages, installed from the host into the jail roots (the jails have no route to the internet) ----------
# dns/powerdns is missing from the FreeBSD 15 quarterly repository (2026-11-25); "latest" has 5.1.5.
log "packages"
env ASSUME_ALWAYS_YES=yes pkg -r $J/pdns install -q -r FreeBSD-latest powerdns sqlite3 >/dev/null
# another PHP version from an earlier run would conflict: remove it first
old=$(pkg -r $J/nsedit query -g '%n' 'php8*' 2>/dev/null | grep -v "^$PHP" || true)
[ -z "$old" ] || env ASSUME_ALWAYS_YES=yes pkg -r $J/nsedit delete -q $old >/dev/null
# PHP from ONE repository: with two enabled (quarterly + latest) pkg silently skipped an extension whose
# versions differed between them (php86-ctype, 2026-11-25)
env ASSUME_ALWAYS_YES=yes pkg -r $J/nsedit install -q -r FreeBSD-ports nginx $PHP $PHP-curl $PHP-sqlite3 $PHP-session $PHP-filter >/dev/null
for ext in curl sqlite3 session filter openssl; do
    chroot $J/nsedit /usr/local/bin/php -m | grep -qx "$ext" || { echo "ERROR: PHP extension $ext missing in the nsedit jail"; exit 1; }
done

# --- PowerDNS jail -------------------------------------------------------------------------------------------
[ -f /root/pdns-api-key ] || (umask 077; openssl rand -hex 24 > /root/pdns-api-key)
APIKEY=$(cat /root/pdns-api-key)
mkdir -p $J/pdns/var/db/powerdns
if [ ! -s $J/pdns/var/db/powerdns/pdns.sqlite3 ]; then
    SCHEMA=$(find $J/pdns/usr/local/share -name 'schema.sqlite3.sql' | head -1)
    chroot $J/pdns /usr/local/bin/sqlite3 /var/db/powerdns/pdns.sqlite3 < "$SCHEMA"
fi
chroot $J/pdns chown -R pdns:pdns /var/db/powerdns
(umask 027; cat > $J/pdns/usr/local/etc/pdns/pdns.conf <<EOF
setuid=pdns
setgid=pdns
launch=gsqlite3
gsqlite3-database=/var/db/powerdns/pdns.sqlite3
gsqlite3-dnssec=yes
local-address=$PDNS_IP
api=yes
api-key=$APIKEY
webserver=yes
webserver-address=$PDNS_IP
webserver-port=8081
webserver-allow-from=$NSEDIT_IP/32
EOF
)
chroot $J/pdns chgrp pdns /usr/local/etc/pdns/pdns.conf
sysrc -q -j pdns pdns_enable=YES >/dev/null 2>&1 || sysrc -q -R $J/pdns pdns_enable=YES >/dev/null

# --- nsedit jail ---------------------------------------------------------------------------------------------
log "nsedit code"
rm -rf $J/nsedit/usr/local/www/nsedit
mkdir -p $J/nsedit/usr/local/www/nsedit
tar -xf /root/nsedit.tar -C $J/nsedit/usr/local/www/nsedit
(cd $J/nsedit/usr/local/www/nsedit && rm -rf .github ci docker pdns tests Dockerfile docker-compose.yml .env.example \
    .dockerignore .trivyignore.yaml .osv-ignore phpstan*.neon vendor/versions.json)
mkdir -p $J/nsedit/var/db/nsedit
chroot $J/nsedit chown www:www /var/db/nsedit
chmod 750 $J/nsedit/var/db/nsedit

ADMINPW_PHP=$(sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g" /root/nsedit-admin-pw)
[ -f /root/nsedit-secret ] || (umask 077; openssl rand -hex 32 > /root/nsedit-secret)
(umask 027; cat > $J/nsedit/usr/local/www/nsedit/includes/config.inc.php <<EOF
<?php
\$apipass       = '$APIKEY';
\$apiip         = '$PDNS_IP';
\$apiport       = '8081';
\$apiproto      = 'http';
\$apisslverify  = FALSE;
\$allowzoneadd  = FALSE;
\$logging       = TRUE;
\$allowclearlogs  = TRUE;
\$allowrotatelogs = FALSE;
\$logsdirectory   = '/var/db/nsedit';
\$authdb  = '/var/db/nsedit/pdns.users.sqlite3';
\$default_admin_username = 'admin';
\$default_admin_password = '$ADMINPW_PHP';
\$secret = '$(cat /root/nsedit-secret)';
\$templates = array();
\$defaults['soa_edit']     = 'INCEPTION-INCREMENT';
\$defaults['soa_edit_api'] = 'DEFAULT';
\$defaults['defaulttype']  = 'Master';
\$defaults['ns'][0] = 'ns1.example.com.';
\$defaults['ns'][1] = 'ns2.example.com.';
\$defaults['ttl']   = 3600;
\$defaults['disabled'] = false;
\$menutype = 'horizontal';
\$logo = 'img/nsedit.svg';
EOF
)
chroot $J/nsedit chgrp www /usr/local/www/nsedit/includes/config.inc.php

cp $J/nsedit/usr/local/etc/php.ini-production $J/nsedit/usr/local/etc/php.ini
cat > $J/nsedit/usr/local/etc/php/zz-nsedit.ini <<'EOF'
error_reporting = E_ALL
display_errors = Off
log_errors = On
error_log = /var/log/php-nsedit.log
expose_php = Off
session.use_strict_mode = 1
EOF
: > $J/nsedit/var/log/php-nsedit.log && chroot $J/nsedit chown www /var/log/php-nsedit.log

cat > $J/nsedit/usr/local/etc/nginx/nginx.conf <<'EOF'
worker_processes 1;
events { worker_connections 256; }
http {
    include mime.types;
    server_tokens off;
    server {
        listen 80;
        root /usr/local/www/nsedit;
        index index.php;
        location ~ ^/(includes|templates\.d)/ { deny all; }
        location ~ (rotate-logs\.php|\.sql|-dist)$ { deny all; }
        location ~ \.php$ {
            try_files $uri =404;
            fastcgi_pass 127.0.0.1:9000;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            include fastcgi_params;
        }
    }
}
EOF
sysrc -q -R $J/nsedit nginx_enable=YES php_fpm_enable=YES >/dev/null

# --- start ----------------------------------------------------------------------------------------------------
log "jails"
for j in pdns nsedit; do
    if jls -j $j >/dev/null 2>&1; then service jail restart $j >/dev/null; else service jail start $j >/dev/null; fi
done
jls
