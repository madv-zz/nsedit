#!/bin/sh
# FreeBSD test VM on a Linux laptop with KVM (no root needed: user in group kvm, qemu-system-x86 installed).
# Usage: contrib/freebsd/vm.sh <dir> {create|start|stop|ssh|deploy|test}
#   create  download FreeBSD $FREEBSD (VM image with cloud-init), check its SHA512, make the disk and seed ISO
#   start   boot the VM: ssh on 127.0.0.1:2222, nsedit on 127.0.0.1:8180
#   deploy  copy this checkout (git archive HEAD) and the admin password from .env into the VM, run setup-jails.sh
#           (PHP=php85 or php86 in the environment picks the PHP version, default php84)
#   test    the checks of the CI tests job against the jails: smoke test, browser test, PHP log, DNS, 403s
# The seed ISO is made with xorriso in a Docker container; tests/ui.py runs in the Playwright image.
set -eu
DIR=${1:?usage: $0 <dir> create|start|stop|ssh|deploy|test}; CMD=${2:?}; shift 2
FREEBSD=${FREEBSD:-15.1-RELEASE}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
IMG=FreeBSD-$FREEBSD-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz
mkdir -p "$DIR"; DIR=$(cd "$DIR" && pwd)

vssh() {
    ssh -q -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile="$DIR/known_hosts" \
        -o ConnectTimeout=5 -i "$DIR/id_ed25519" -p 2222 root@127.0.0.1 "$@"
}

case "$CMD" in
create)
    base=https://download.freebsd.org/releases/VM-IMAGES/$FREEBSD/amd64/Latest
    (cd "$DIR" && curl -fsS -o CHECKSUM.SHA512 "$base/CHECKSUM.SHA512" && curl -fsS -o "$IMG" "$base/$IMG" \
        && grep -F "($IMG)" CHECKSUM.SHA512 | awk -v f="$IMG" '{print $NF"  "f}' | sha512sum -c -)
    xz -dc "$DIR/$IMG" > "$DIR/disk.qcow2" && qemu-img resize -q "$DIR/disk.qcow2" 30G
    [ -f "$DIR/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C nsedit-bsd-vm -f "$DIR/id_ed25519"
    mkdir -p "$DIR/seed"
    printf 'instance-id: nsedit-freebsd-1\nlocal-hostname: nsedit-freebsd\n' > "$DIR/seed/meta-data"
    { echo '#cloud-config'; echo 'ssh_authorized_keys:'; echo "  - $(cat "$DIR/id_ed25519.pub")"
      cat <<'EOT'
runcmd:
  - mkdir -p /root/.ssh && chmod 700 /root/.ssh
  - cp /home/freebsd/.ssh/authorized_keys /root/.ssh/authorized_keys
  - sysrc sshd_enable=YES
  - echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config
  - service sshd restart
EOT
    } > "$DIR/seed/user-data"
    docker run --rm -v "$DIR:/d" alpine:3.20 sh -c "apk add -q xorriso >/dev/null && \
        xorriso -as mkisofs -quiet -V cidata -J -r -o /d/seed.iso /d/seed/user-data /d/seed/meta-data && chown $(id -u):$(id -g) /d/seed.iso"
    ;;
start)
    qemu-system-x86_64 -name nsedit-freebsd -machine q35,accel=kvm -cpu host -smp 4 -m 4096 \
        -drive file="$DIR/disk.qcow2",if=virtio,format=qcow2 -drive file="$DIR/seed.iso",media=cdrom,readonly=on \
        -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:8180-:8180 -device virtio-net-pci,netdev=n0 \
        -display none -serial file:"$DIR/console.log" -daemonize -pidfile "$DIR/qemu.pid"
    i=0; until vssh true 2>/dev/null; do i=$((i+1)); [ $i -lt 60 ] || { echo "no ssh after 5 minutes"; exit 1; }; sleep 5; done
    vssh freebsd-version
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
    vssh 'test -f /usr/local/etc/pkg/repos/FreeBSD-latest.conf || { mkdir -p /usr/local/etc/pkg/repos; printf "FreeBSD-latest: { url: \"pkg+https://pkg.FreeBSD.org/\${ABI}/latest\", mirror_type: \"srv\", signature_type: \"fingerprints\", fingerprints: \"/usr/share/keys/pkg\", enabled: yes }\n" > /usr/local/etc/pkg/repos/FreeBSD-latest.conf; }; env ASSUME_ALWAYS_YES=yes pkg update -q'
    vssh "PHP=${PHP:-php84} sh -s" < "$REPO/contrib/freebsd/setup-jails.sh"
    ;;
test)
    echo "== versions: $(vssh 'freebsd-version; jexec nsedit php -r "echo PHP_VERSION;"; echo; jexec pdns pdns_server --version 2>&1 | grep -o "Server [0-9.]*"' | tr '\n' ' ')"
    exec "$REPO/contrib/vm-checks.sh" http://127.0.0.1:8180 /jails/nsedit/var/log/php-nsedit.log 10.53.0.2 "$0" "$DIR" ssh
    ;;
*) echo "unknown command $CMD"; exit 2 ;;
esac
