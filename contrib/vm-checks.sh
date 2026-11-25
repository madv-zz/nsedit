#!/bin/sh
# The checks of the CI tests job (.github/workflows/ci.yml), run against nsedit in a BSD VM.
# Usage: contrib/vm-checks.sh <base-url> <php-log-in-vm> <dns-server-in-vm> <ssh command ...>
#   e.g. contrib/vm-checks.sh http://127.0.0.1:8180 /jails/nsedit/var/log/php-nsedit.log 10.53.0.2 contrib/freebsd/vm.sh DIR ssh
# Needs: python3, curl and Docker (browser test in the Playwright image) on the host; drill or dig in the VM.
set -u
URL=$1; PHPLOG=$2; DNS=$3; shift 3
REPO=$(cd "$(dirname "$0")/.." && pwd)
fail=0
SSH_CMD="$*"
vssh() { sh -c "$SSH_CMD \"\$@\"" sh "$@"; }
dnsq() {
    vssh "if command -v drill >/dev/null; then drill @$DNS $1 $2; else dig @$DNS $1 $2; fi | awk '/^$1[[:space:]]/{print \$NF}' | head -1"
}

echo "== smoke test"
python3 -I "$REPO/tests/smoke.py" "$URL" | tail -1 | grep -q 'FAILURES: 0' && echo "FAILURES: 0" || { echo "FAILED"; fail=1; }

echo "== browser test"
docker run --rm --network host -v "$REPO:/src:ro" -w /src mcr.microsoft.com/playwright/python:v1.65.1-noble \
    sh -c "pip install -q --break-system-packages --root-user-action=ignore playwright==1.65.1 && python3 -I tests/ui.py $URL" \
    | tail -1 | tee /dev/stderr | grep -q ' 0 problems' || fail=1

echo "== no PHP warnings, notices or deprecations"
n=$(vssh "wc -l < $PHPLOG" | tr -d ' ')
echo "lines in the PHP log: $n"
[ "$n" = 0 ] || { vssh "head -5 $PHPLOG"; fail=1; }

echo "== DNS answers from PowerDNS"
KEEP=1 python3 -I "$REPO/tests/smoke.py" "$URL" >/dev/null 2>&1 || true
a=$(dnsq mail.smoketest.example. A)
p12=$(dnsq 12.2.0.192.in-addr.arpa. PTR)
p11=$(dnsq 11.2.0.192.in-addr.arpa. PTR)
echo "A=$a PTR .12=$p12 PTR .11=${p11:-none}"
[ "$a" = 192.0.2.12 ] && [ "$p12" = mail.smoketest.example. ] && [ -z "$p11" ] || fail=1
python3 -I "$REPO/tests/smoke.py" "$URL" >/dev/null 2>&1 || true   # removes the test zones again

echo "== internal files are not served"
for path in includes/config.inc.php includes/scheme.sql templates.d/template.json.example rotate-logs.php; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$URL/$path"); echo "$path $code"; [ "$code" = 403 ] || fail=1
done

if [ $fail = 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; exit 1; fi
