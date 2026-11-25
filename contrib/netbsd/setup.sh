#!/bin/sh
# nsedit on NetBSD with pkgsrc: nginx + php-fpm, PowerDNS with the PostgreSQL backend (pkgsrc has no sqlite
# backend for PowerDNS), API only on 127.0.0.1.
# Run as root:  ssh ... 'PHPV=8.4 sh -s' < setup.sh        (PHPV: 8.4 (default) or 8.5)
# Expects: /root/nsedit.tar (git archive of nsedit), /root/nsedit-admin-pw (admin password, mode 600).
# Running it again replaces the nsedit code and can switch the PHP version.
set -eu
export PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/pkg/sbin:/usr/pkg/bin

PHPV=${PHPV:-8.4}
PHPN=$(echo "$PHPV" | tr -d .)          # 84
PG=16                                   # the PostgreSQL client powerdns-pgsql is built against
REPO=${PKGSRC_REPO:-https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/$(uname -m)/$(uname -r | cut -d_ -f1)/All}
log() { echo "== $*"; }

# --- packages ------------------------------------------------------------------------------------------------
log "packages (PHP $PHPV)"
if ! command -v pkgin >/dev/null; then PKG_PATH=$REPO pkg_add pkgin; fi
mkdir -p /usr/pkg/etc/pkgin && echo "$REPO" > /usr/pkg/etc/pkgin/repositories.conf
pkgin -y update >/dev/null
pkgin -y install "php$PHPN" "php$PHPN-curl" "php$PHPN-sqlite3" "php$PHPN-fpm" nginx powerdns powerdns-pgsql \
    "postgresql$PG-server" >/dev/null
for ext in curl sqlite3 session filter openssl; do
    "php$PHPN" -m | grep -qx "$ext" || { echo "ERROR: PHP extension $ext missing"; exit 1; }
done
for svc in nginx pdns pgsql "php_fpm$PHPN"; do
    cp "/usr/pkg/share/examples/rc.d/$svc" /etc/rc.d/
done
# only one php-fpm version at a time
for rc in /etc/rc.d/php_fpm[0-9]*; do
    svc=${rc##*/}; [ "$svc" = "php_fpm$PHPN" ] && continue
    "$rc" onestop >/dev/null 2>&1 || true
    sed -i "/^$svc=/d" /etc/rc.conf
done
for svc in pgsql nginx pdns "php_fpm$PHPN"; do
    grep -q "^$svc=" /etc/rc.conf || echo "$svc=YES" >> /etc/rc.conf
done

# --- PostgreSQL: unix socket with peer auth, TCP with a password -------------------------------------------------
mkdir -p /usr/pkg/pgsql && chown pgsql:pgsql /usr/pkg/pgsql   # home of pgsql; the rc script writes its errlog there
if [ ! -f /usr/pkg/pgsql/data/PG_VERSION ]; then
    log "PostgreSQL initdb"
    mkdir -p /usr/pkg/pgsql/data && chown pgsql:pgsql /usr/pkg/pgsql/data
    su -m pgsql -c "initdb -D /usr/pkg/pgsql/data -E UTF8 --auth-local=peer --auth-host=scram-sha-256" >/dev/null
fi
/etc/rc.d/pgsql status >/dev/null 2>&1 || /etc/rc.d/pgsql start >/dev/null
[ -f /root/pdns-db-pw ] || (umask 077; openssl rand -hex 24 > /root/pdns-db-pw)
if ! su -m pgsql -c "psql -d postgres -tAc \"SELECT 1 FROM pg_roles WHERE rolname='pdns'\"" | grep -q 1; then
    log "PowerDNS database"
    (umask 077; printf "CREATE ROLE pdns LOGIN PASSWORD '%s';\nCREATE DATABASE pdns OWNER pdns;\n" "$(cat /root/pdns-db-pw)" \
        > /root/pdns-db.sql)
    su -m pgsql -c "psql -d postgres" < /root/pdns-db.sql >/dev/null
    rm -f /root/pdns-db.sql
    { echo "SET ROLE pdns;"; cat /usr/pkg/share/doc/pdns/schema.pgsql.sql; } | su -m pgsql -c "psql -q -d pdns" >/dev/null
fi

# --- PowerDNS on 127.0.0.1, API only from 127.0.0.1 ---------------------------------------------------------------
[ -f /root/pdns-api-key ] || (umask 077; openssl rand -hex 24 > /root/pdns-api-key)
APIKEY=$(cat /root/pdns-api-key)
(umask 077; cat > /usr/pkg/etc/pdns.conf <<EOF
setuid=nobody
setgid=nobody
launch=gpgsql
gpgsql-host=127.0.0.1
gpgsql-dbname=pdns
gpgsql-user=pdns
gpgsql-password=$(cat /root/pdns-db-pw)
gpgsql-dnssec=yes
local-address=127.0.0.1
api=yes
api-key=$APIKEY
webserver=yes
webserver-address=127.0.0.1
webserver-port=8081
webserver-allow-from=127.0.0.1/32
EOF
)
mkdir -p /var/run/pdns

# --- nsedit ----------------------------------------------------------------------------------------------------------
log "nsedit code"
W=/usr/pkg/share/nsedit
rm -rf $W && mkdir -p $W
tar -xf /root/nsedit.tar -C $W
(cd $W && rm -rf .github ci docker pdns tests contrib Dockerfile docker-compose.yml .env.example \
    .dockerignore .trivyignore.yaml .osv-ignore phpstan*.neon vendor/versions.json)
mkdir -p /var/db/nsedit && chown fpm:www /var/db/nsedit && chmod 750 /var/db/nsedit
: > /var/log/php-nsedit.log && chown fpm /var/log/php-nsedit.log

ADMINPW_PHP=$(sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g" /root/nsedit-admin-pw)
[ -f /root/nsedit-secret ] || (umask 077; openssl rand -hex 32 > /root/nsedit-secret)
(umask 027; cat > $W/includes/config.inc.php <<EOF
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
chgrp www $W/includes/config.inc.php

cat > "/usr/pkg/etc/php/$PHPV/php.d/zz-nsedit.ini" <<'EOF'
error_reporting = E_ALL
display_errors = Off
log_errors = On
error_log = /var/log/php-nsedit.log
expose_php = Off
session.use_strict_mode = 1
EOF
sed -i 's|^listen = .*|listen = 127.0.0.1:9000|' "/usr/pkg/etc/php/$PHPV/php-fpm.d/www.conf"

cat > /usr/pkg/etc/nginx/nginx.conf <<EOF
user nginx nginx;
worker_processes 1;
events { worker_connections 256; }
http {
    include /usr/pkg/etc/nginx/mime.types;
    server_tokens off;
    server {
        listen 80;
        root $W;
        index index.php;
        location ~ ^/(includes|templates\\.d)/ { deny all; }
        location ~ (rotate-logs\\.php|\\.sql|-dist)\$ { deny all; }
        location ~ \\.php\$ {
            try_files \$uri =404;
            fastcgi_pass 127.0.0.1:9000;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include /usr/pkg/etc/nginx/fastcgi_params;
        }
    }
}
EOF
nginx -t -q

# --- start -------------------------------------------------------------------------------------------------------------
log "services"
for svc in pdns "php_fpm$PHPN" nginx; do
    "/etc/rc.d/$svc" restart >/dev/null 2>&1 || "/etc/rc.d/$svc" start >/dev/null
done
for svc in pgsql pdns "php_fpm$PHPN" nginx; do
    "/etc/rc.d/$svc" status >/dev/null 2>&1 && echo "$svc running" || { echo "ERROR: $svc not running"; exit 1; }
done
