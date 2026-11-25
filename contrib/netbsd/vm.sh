#!/bin/sh
# NetBSD test VM on a Linux laptop with KVM (no root needed: user in group kvm, qemu-system-x86 installed).
# Usage: contrib/netbsd/vm.sh <dir> {create|start|stop|ssh|deploy|test}
#   create  install NetBSD $NETBSD with anita (NetBSD's own install-test tool, in a venv; its tarball is checked
#           against a fixed SHA256), then enable DHCP, sshd and an SSH key for root
#   start   boot the VM: ssh on 127.0.0.1:2224, nsedit on 127.0.0.1:8182 (QEMU without IPv6: pkgsrc's CDN
#           answers with IPv6 addresses first and QEMU's NAT does not route IPv6, so downloads hung)
#   deploy  this checkout (git archive HEAD) + the admin password from .env, then setup.sh (PHPV=8.4|8.5)
#   test    the checks of the CI tests job (contrib/vm-checks.sh)
# Needs python3 (venv), Docker (xorriso as mkisofs for anita, and the browser test) and ~1 GB for the sets.
set -eu
DIR=${1:?usage: $0 <dir> create|start|stop|ssh|deploy|test}; CMD=${2:?}; shift 2
NETBSD=${NETBSD:-11.1}
MIRROR=${MIRROR:-https://cdn.netbsd.org/pub/NetBSD}
ANITA=2.18
ANITA_SHA256=fa5ac3a8b3e30a3a35df9254bbee213b28210a396544592c3e604a1e53a294ce
REPO=$(cd "$(dirname "$0")/../.." && pwd)
HERE=$REPO/contrib/netbsd
mkdir -p "$DIR"; DIR=$(cd "$DIR" && pwd)
URL=$MIRROR/NetBSD-$NETBSD/amd64/

vssh() {
    ssh -q -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile="$DIR/known_hosts" \
        -o ConnectTimeout=5 -i "$DIR/id_ed25519" -p 2224 root@127.0.0.1 "$@"
}
anita() {
    PATH="$DIR/venv/bin:$PATH" "$DIR/venv/bin/anita" --workdir "$DIR/work" --memory-size 4G \
        --vmm-args "-accel kvm -cpu host -smp 4" "$@"
}

case "$CMD" in
create)
    if [ ! -x "$DIR/venv/bin/anita" ]; then
        curl -fsS -o "$DIR/anita-$ANITA.tar.gz" "https://www.gson.org/netbsd/anita/download/anita-$ANITA.tar.gz"
        echo "$ANITA_SHA256  $DIR/anita-$ANITA.tar.gz" | sha256sum -c -
        mkdir -p "$DIR/anita-src" && tar -xzf "$DIR/anita-$ANITA.tar.gz" -C "$DIR/anita-src"
        python3 -m venv "$DIR/venv"
        "$DIR/venv/bin/pip" install -q pexpect==4.9.0 "$DIR/anita-src/anita-$ANITA"
    fi
    # anita builds an ISO of the sets with mkisofs: xorriso's emulation in a container
    printf 'FROM alpine:3.20\nRUN apk add --no-cache xorriso\n' | docker build -q -t nsedit-xorriso:local - >/dev/null
    cat > "$DIR/venv/bin/mkisofs" <<EOT
#!/bin/sh
exec docker run --rm -u $(id -u):$(id -g) -v "$DIR:$DIR" -w "\$PWD" nsedit-xorriso:local xorriso -as mkisofs "\$@"
EOT
    chmod +x "$DIR/venv/bin/mkisofs"
    [ -f "$DIR/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C nsedit-bsd-vm -f "$DIR/id_ed25519"
    anita --disk-size 30G install "$URL" > "$DIR/install.log" 2>&1
    key=$(cat "$DIR/id_ed25519.pub")
    anita --persist --run "echo dhcpcd=YES >> /etc/rc.conf; echo sshd=YES >> /etc/rc.conf; echo hostname=nsedit-netbsd >> /etc/rc.conf; mkdir -p /root/.ssh; echo '$key' > /root/.ssh/authorized_keys; chmod 700 /root/.ssh; chmod 600 /root/.ssh/authorized_keys; echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config" \
        boot "$URL" > "$DIR/setup.log" 2>&1
    echo "installed: $DIR/work/wd0.img"
    ;;
start)
    qemu-system-x86_64 -name nsedit-netbsd -machine q35,accel=kvm -cpu host -smp 4 -m 4096 \
        -drive file="$DIR/work/wd0.img",format=raw \
        -netdev user,id=n0,ipv6=off,hostfwd=tcp:127.0.0.1:2224-:22,hostfwd=tcp:127.0.0.1:8182-:80 \
        -device virtio-net-pci,netdev=n0 -display none -serial file:"$DIR/console.log" -daemonize -pidfile "$DIR/qemu.pid"
    i=0; until vssh true 2>/dev/null; do i=$((i+1)); [ $i -lt 60 ] || { echo "no ssh after 5 minutes"; exit 1; }; sleep 5; done
    vssh uname -sr
    ;;
stop)
    vssh '/sbin/shutdown -p now' || true
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
    echo "== versions: $(vssh 'uname -sr; for p in /usr/pkg/bin/php8[0-9]; do [ -e "$p" ] && "$p" -r "echo PHP_VERSION;" && echo; done; /usr/pkg/sbin/pdns_server --version 2>&1 | grep -o "Server [0-9.]*"' | tr '\n' ' ')"
    exec "$REPO/contrib/vm-checks.sh" http://127.0.0.1:8182 /var/log/php-nsedit.log 127.0.0.1 "$0" "$DIR" ssh
    ;;
*) echo "unknown command $CMD"; exit 2 ;;
esac
