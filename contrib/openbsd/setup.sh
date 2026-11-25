#!/bin/sh
# nsedit on OpenBSD: PowerDNS (sqlite) + the base httpd + php-fpm, both chrooted in /var/www.
# Run as root:  ssh ... 'PHPV=8.4 sh -s' < setup.sh        (PHPV: 8.3, 8.4 (default) or 8.5)
# Expects: /root/nsedit.tar (git archive of nsedit), /root/nsedit-admin-pw (admin password, mode 600).
# Running it again replaces the nsedit code and can switch the PHP version.
set -eu

PHPV=${PHPV:-8.4}
PHPN=$(echo "$PHPV" | tr -d .)          # 84
W=/var/www                              # chroot of httpd and php-fpm
log() { echo "== $*"; }

# --- packages ------------------------------------------------------------------------------------------------
log "packages (PHP $PHPV)"
old=$(pkg_info -q | grep -E '^php-(curl-|sqlite3-)?8\.[0-9]' | grep -v "8\.$((PHPN % 10))\." || true)
if [ -n "$old" ]; then
    for rc in /etc/rc.d/php[0-9]*_fpm; do
        [ -e "$rc" ] || continue
        svc=${rc##*/}; rcctl stop "$svc" >/dev/null 2>&1 || true; rcctl disable "$svc" >/dev/null 2>&1 || true
    done
    # shellcheck disable=SC2086 # package names without spaces
    pkg_delete -I $old >/dev/null
fi
pkg_add -I "php%$PHPV" "php-curl%$PHPV" "php-sqlite3%$PHPV" powerdns >/dev/null
for ext in curl sqlite3; do
    ln -sf "/etc/php-$PHPV.sample/$ext.ini" "/etc/php-$PHPV/$ext.ini"
done
for ext in curl sqlite3 session filter openssl; do
    "php-$PHPV" -m | grep -qx "$ext" || { echo "ERROR: PHP extension $ext missing"; exit 1; }
done

# --- PowerDNS on 127.0.0.1, API only from 127.0.0.1 -------------------------------------------------------------
[ -f /root/pdns-api-key ] || (umask 077; openssl rand -hex 24 > /root/pdns-api-key)
APIKEY=$(cat /root/pdns-api-key)
mkdir -p /var/db/pdns
if [ ! -s /var/db/pdns/pdns.sqlite3 ]; then
    sqlite3 /var/db/pdns/pdns.sqlite3 < /usr/local/share/doc/pdns/schema.sqlite3.sql
fi
chown -R _powerdns:_powerdns /var/db/pdns
(umask 027; cat > /etc/pdns/pdns.conf <<EOF
launch=gsqlite3
gsqlite3-database=/var/db/pdns/pdns.sqlite3
gsqlite3-dnssec=yes
local-address=127.0.0.1
api=yes
api-key=$APIKEY
webserver=yes
webserver-address=127.0.0.1
webserver-port=8081
webserver-allow-from=127.0.0.1/32
EOF
)
chgrp _powerdns /etc/pdns/pdns.conf

# --- nsedit in the chroot ----------------------------------------------------------------------------------------
log "nsedit code"
rm -rf $W/nsedit && mkdir -p $W/nsedit
tar -xf /root/nsedit.tar -C $W/nsedit
(cd $W/nsedit && rm -rf .github ci docker pdns tests contrib Dockerfile docker-compose.yml .env.example \
    .dockerignore .trivyignore.yaml .osv-ignore phpstan*.neon vendor/versions.json)
mkdir -p $W/nsedit-data $W/tmp && chown www:www $W/nsedit-data && chmod 750 $W/nsedit-data && chmod 1777 $W/tmp
: > $W/logs/php-nsedit.log && chown www $W/logs/php-nsedit.log

ADMINPW_PHP=$(sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g" /root/nsedit-admin-pw)
[ -f /root/nsedit-secret ] || (umask 077; openssl rand -hex 32 > /root/nsedit-secret)
# paths are seen from inside the chroot (/var/www = /)
(umask 027; cat > $W/nsedit/includes/config.inc.php <<EOF
<?php
\$apipass       = '$APIKEY';
\$apiip         = '127.0.0.1';
\$apiport       = '8081';
\$apiproto      = 'http';
\$apisslverify  = FALSE;
\$allowzoneadd  = FALSE;
\$logging       = TRUE;
\$allowclearlogs  = TRUE;
\$allowrotatelogs = FALSE;
\$logsdirectory   = '/nsedit-data';
\$authdb  = '/nsedit-data/pdns.users.sqlite3';
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
chgrp www $W/nsedit/includes/config.inc.php

cat > /etc/php-$PHPV/zz-nsedit.ini <<'EOF'
error_reporting = E_ALL
display_errors = Off
log_errors = On
error_log = /logs/php-nsedit.log
expose_php = Off
session.use_strict_mode = 1
session.save_path = /tmp
EOF

# --- httpd ---------------------------------------------------------------------------------------------------------
cat > /etc/httpd.conf <<'EOF'
server "default" {
    listen on * port 80
    root "/nsedit"
    directory index index.php
    location "/includes/*"     { block }
    location "/templates.d/*"  { block }
    location "/rotate-logs.php" { block }
    location "*.sql"           { block }
    location "*-dist"          { block }
    location "*.php" {
        fastcgi socket "/run/php-fpm.sock"
    }
}
EOF
httpd -n >/dev/null

# --- start ----------------------------------------------------------------------------------------------------------
log "services"
rcctl enable pdns_server httpd "php${PHPN}_fpm" >/dev/null
rcctl restart pdns_server >/dev/null
rcctl restart "php${PHPN}_fpm" >/dev/null
rcctl restart httpd >/dev/null
rcctl check pdns_server "php${PHPN}_fpm" httpd
