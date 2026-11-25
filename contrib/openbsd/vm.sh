#!/bin/sh
# OpenBSD test VM on a Linux laptop with KVM (no root needed: user in group kvm, qemu-system-x86 installed).
# Usage: contrib/openbsd/vm.sh <dir> {create|start|stop|ssh|deploy|test}
#   create  download pxeboot + bsd.rd of OpenBSD $OPENBSD (SHA256 checked) and install with autoinstall(8):
#           network boot over QEMU's TFTP, the answers come from a response file served on 127.0.0.1:8099 for the
#           duration of the install; the sets are fetched and signify-verified by the installer itself
#   start   boot the installed VM: ssh on 127.0.0.1:2223, nsedit on 127.0.0.1:8181
#   deploy  this checkout (git archive HEAD) + the admin password from .env, then setup.sh (PHPV=8.3|8.4|8.5)
#   test    the checks of the CI tests job (contrib/vm-checks.sh)
set -eu
DIR=${1:?usage: $0 <dir> create|start|stop|ssh|deploy|test}; CMD=${2:?}; shift 2
OPENBSD=${OPENBSD:-8.0}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
HERE=$REPO/contrib/openbsd
mkdir -p "$DIR"; DIR=$(cd "$DIR" && pwd)

vssh() {
    ssh -q -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile="$DIR/known_hosts" \
        -o ConnectTimeout=5 -i "$DIR/id_ed25519" -p 2223 root@127.0.0.1 "$@"
}
qemu() {
    qemu-system-x86_64 -name nsedit-openbsd -machine q35,accel=kvm -cpu host -smp 4 -m 4096 "$@" \
        -drive file="$DIR/disk.qcow2",if=virtio,format=qcow2 -device virtio-net-pci,netdev=n0 \
        -display none -serial unix:"$DIR/console.sock",server,nowait -daemonize -pidfile "$DIR/qemu.pid"
}
fwd=hostfwd=tcp:127.0.0.1:2223-:22,hostfwd=tcp:127.0.0.1:8181-:80

case "$CMD" in
create)
    base=https://cdn.openbsd.org/pub/OpenBSD/$OPENBSD/amd64
    mkdir -p "$DIR/tftp/etc" "$DIR/http"
    curl -fsS -o "$DIR/SHA256" "$base/SHA256"
    curl -fsS -o "$DIR/tftp/auto_install" "$base/pxeboot"
    curl -fsS -o "$DIR/tftp/bsd.rd" "$base/bsd.rd"
    (cd "$DIR/tftp" && grep -E '\((pxeboot|bsd\.rd)\)' ../SHA256 | sed 's/(pxeboot)/(auto_install)/' | sha256sum -c -)
    printf 'stty com0 115200\nset tty com0\nboot tftp:/bsd.rd\n' > "$DIR/tftp/etc/boot.conf"
    [ -f "$DIR/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C nsedit-bsd-vm -f "$DIR/id_ed25519"
    (umask 077; cat > "$DIR/http/install.conf" <<EOT
System hostname = nsedit-openbsd
Which network interface do you wish to configure = vio0
IPv4 address for vio0 = autoconf
IPv6 address for vio0 = none
Password for root account = $(openssl rand -hex 24)
Public ssh key for root account = $(cat "$DIR/id_ed25519.pub")
Start sshd(8) by default = yes
Allow root ssh login = prohibit-password
Change the default console to com0 = yes
Which speed should com0 use = 115200
Do you expect to run the X Window System = no
Setup a user = no
What timezone are you in = UTC
Which disk is the root disk = sd0
Use (W)hole disk MBR, whole disk (G)PT or (E)dit = G
Use (A)uto layout, (E)dit auto layout, or create (C)ustom layout = a
Location of sets = http
HTTP proxy URL = none
HTTP Server = cdn.openbsd.org
Server directory = pub/OpenBSD/$OPENBSD/amd64
Set name(s) = -x* -game*
Location of sets = done
Exit to (S)hell, (H)alt or (R)eboot = R
EOT
    )
    chmod 644 "$DIR/http/install.conf"   # readable for the http server; the root password is random and unused
    qemu-img create -q -f qcow2 "$DIR/disk.qcow2" 30G
    python3 -m http.server --bind 127.0.0.1 8099 --directory "$DIR/http" > "$DIR/http.log" 2>&1 &
    httpd=$!
    qemu -boot once=n -netdev user,id=n0,tftp="$DIR/tftp",bootfile=auto_install,$fwd
    rc=0; python3 -I "$HERE/console-driver.py" "$DIR/console.sock" "$DIR/console.log" http://10.0.2.2:8099/install.conf 2400 || rc=$?
    kill "$httpd"; shred -u "$DIR/http/install.conf"
    [ $rc = 0 ] || { echo "install failed, see $DIR/console.log"; exit 1; }
    vssh uname -sr
    ;;
start)
    qemu -netdev user,id=n0,$fwd
    i=0; until vssh true 2>/dev/null; do i=$((i+1)); [ $i -lt 60 ] || { echo "no ssh after 5 minutes"; exit 1; }; sleep 5; done
    vssh uname -sr
    ;;
stop)
    vssh 'shutdown -p now' || true
    ;;
ssh)
    vssh "$@"
    ;;
deploy)
    (cd "$REPO" && git archive --format=tar HEAD) | vssh 'cat > /root/nsedit.tar'
    grep '^NSEDIT_ADMIN_PASSWORD=' "$REPO/.env" | cut -d= -f2- | tr -d '\n' | vssh 'umask 077; cat > /root/nsedit-admin-pw'
    vssh "PHPV=${PHPV:-8.4} sh -s" < "$HERE/setup.sh"
    ;;
test)
    echo "== versions: $(vssh 'uname -sr; for p in /usr/local/bin/php-8.*; do [ -e "$p" ] && "$p" -r "echo PHP_VERSION;"; done; echo; pdns_server --version 2>&1 | grep -o "Server [0-9.]*"' | tr '\n' ' ')"
    exec "$REPO/contrib/vm-checks.sh" http://127.0.0.1:8181 /var/www/logs/php-nsedit.log 127.0.0.1 "$0" "$DIR" ssh
    ;;
*) echo "unknown command $CMD"; exit 2 ;;
esac
