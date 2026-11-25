#!/usr/bin/env python3
"""Check the JavaScript libraries that are shipped in this repository (and loaded by index.php)
against the OSV database. Trivy does not see them, because they are plain files without a lock file.

Known findings can be accepted temporarily in .osv-ignore, one per line:
    <OSV/GHSA id> <expires YYYY-MM-DD> <reason>
An expired entry no longer counts, so the check fails again after that date.
"""
import datetime
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent


def version_from(path, pattern):
    match = re.search(pattern, (ROOT / path).read_text(encoding="utf-8", errors="replace"))
    if not match:
        sys.exit(f"cannot find the version in {path}")
    return match.group(1)


# npm package name -> (file that holds the version, regular expression for the version)
LIBRARIES = {
    "jquery": ("jquery-ui/external/jquery/jquery.js", r"jQuery JavaScript Library v(\S+)"),
    # unbuilt source checkout of jQuery UI (the files say @VERSION); version from its old package.json
    "jquery-ui": ("jquery-ui/VERSION", r"^(\S+)"),
    "jtable": ("jtable/lib/jquery.jtable.js", r"jTable (\d+\.\d+\.\d+)"),
}


def load_ignores():
    ignores, today = {}, datetime.date.today()
    path = ROOT / ".osv-ignore"
    if not path.exists():
        return ignores
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        vuln_id, expires, *_ = line.split()
        if datetime.date.fromisoformat(expires) >= today:
            ignores[vuln_id] = expires
        else:
            print(f"   ignore for {vuln_id} expired on {expires}")
    return ignores


def query(name, version):
    body = json.dumps({"package": {"name": name, "ecosystem": "npm"}, "version": version}).encode()
    request = urllib.request.Request("https://api.osv.dev/v1/query", data=body,
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:  # nosec B310 - fixed https URL
        return json.load(response).get("vulns", [])


def main():
    ignores, bad = load_ignores(), 0
    for name, (path, pattern) in LIBRARIES.items():
        version = version_from(path, pattern)
        vulns = query(name, version)
        print(f"-- {name} {version}: {len(vulns)} known vulnerabilities")
        for vuln in vulns:
            accepted = vuln["id"] in ignores
            bad += not accepted
            note = f"accepted until {ignores[vuln['id']]}" if accepted else "NOT ACCEPTED"
            print(f"   {vuln['id']} ({note}): {vuln.get('summary', '')[:100]}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
