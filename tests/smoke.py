#!/usr/bin/env python3
"""Smoke test for nsedit: runs every action through HTTP against a running instance.

Usage: [KEEP=1] tests/smoke.py [base-url]      (default base-url: http://127.0.0.1:8080)

Reads NSEDIT_ADMIN_USER / NSEDIT_ADMIN_PASSWORD from .env in the repository root and
never prints them. KEEP=1 leaves the test zones in place, e.g. to query them with dig.
"""
import http.cookiejar
import json
import os
import re
import sys
import urllib.parse
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:8080'
env = {}
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.env'), encoding='utf-8') as envfile:
    for line in envfile:
        if '=' in line and not line.startswith('#'):
            k, v = line.rstrip('\n').split('=', 1)
            env[k] = v
fails = 0

Z = 'smoketest.example.'
CLONE = 'clone.example.'
REV4 = '2.0.192.in-addr.arpa.'
REV6 = '8.b.d.0.1.0.0.2.ip6.arpa.'
SLAVE = 'slave.example.'
CUST = 'customer@example.com'


class Client:
    def __init__(self, cookie=None):
        self.jar = http.cookiejar.CookieJar()
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar))
        if cookie:
            self.op.addheaders = [('Cookie', cookie)]
        self.csrf = None

    def req(self, path, data=None, get=None):
        url = BASE + '/' + path + ('?' + urllib.parse.urlencode(get) if get else '')
        body = urllib.parse.urlencode(data, doseq=True).encode() if data is not None else None
        r = urllib.request.Request(url, data=body)
        if self.csrf:
            r.add_header('X-CSRF-Token', self.csrf)
        with self.op.open(r) as resp:
            if resp.headers.get('X-CSRF-Token'):
                self.csrf = resp.headers['X-CSRF-Token']
            return resp.read().decode()

    def j(self, path, action, data=None, **get):
        txt = self.req(path, data if data is not None else {}, dict(action=action, **get))
        try:
            return json.loads(txt)
        except ValueError:
            return {'Result': 'NOJSON', 'Message': txt[:300]}

    def login(self, user, password, **extra):
        self.req('index.php', dict(formname='loginform', username=user, password=password, **extra))
        return 'logout' in self.req('index.php').lower()


def check(name, res, want='OK'):
    global fails
    ok = res.get('Result') == want
    fails += not ok
    print(('ok   ' if ok else 'FAIL ') + name + ('' if ok else '  -> ' + str(res)[:300]))
    return res


def expect(name, ok, detail=''):
    global fails
    fails += not ok
    print(('ok   ' if ok else 'FAIL ') + name + (': ' + str(detail) if detail else ''))


def records(client, zone, rtype=None):
    return [(x['name'], x['type'], x['content'])
            for x in client.j('zones.php', 'listrecords', zoneid=zone).get('Records', [])
            if rtype is None or x['type'] == rtype]


a = Client()
expect('login admin', a.login(env['NSEDIT_ADMIN_USER'], env['NSEDIT_ADMIN_PASSWORD']))

# clean up a previous run
for z in (Z, CLONE, REV4, REV6, SLAVE):
    a.j('zones.php', 'delete', {'id': z})
for u in a.j('users.php', 'list').get('Records', []):
    if u['emailaddress'] == CUST:
        a.j('users.php', 'delete', {'id': u['id']})

# zones and records
check('create zone', a.j('zones.php', 'create', {'name': Z, 'kind': 'Master', 'account': 'admin', 'template': 'None',
                                                 'nameserver[]': ['ns1.example.com.', 'ns2.example.com.']}))
check('create IPv4 reverse zone', a.j('zones.php', 'create', {'name': REV4, 'kind': 'Master', 'nameserver[]': ['ns1.example.com.'], 'template': 'None'}))
check('create IPv6 reverse zone', a.j('zones.php', 'create', {'name': REV6, 'kind': 'Master', 'nameserver[]': ['ns1.example.com.'], 'template': 'None'}))
check('list zones (paged)', a.j('zones.php', 'list', jtStartIndex=0, jtPageSize=10))
check('search zones', a.j('zones.php', 'list', {'domsearch': 'smoke'}))
check('A record', a.j('zones.php', 'createrecord', {'name': 'www', 'type': 'A', 'content': '192.0.2.10', 'ttl': '300', 'disabled': '0', 'setptr': '0'}, zoneid=Z))
check('A record with PTR', a.j('zones.php', 'createrecord', {'name': 'mail', 'type': 'A', 'content': '192.0.2.11', 'ttl': '300', 'disabled': '0', 'setptr': '1'}, zoneid=Z))
check('AAAA record with PTR', a.j('zones.php', 'createrecord', {'name': 'v6', 'type': 'AAAA', 'content': '2001:db8::1', 'ttl': '300', 'disabled': '0', 'setptr': '1'}, zoneid=Z))
check('TXT record (quoting)', a.j('zones.php', 'createrecord', {'name': '', 'type': 'TXT', 'content': 'v=spf1 -all', 'ttl': '3600', 'disabled': '0'}, zoneid=Z))
check('MX record', a.j('zones.php', 'createrecord', {'name': '', 'type': 'MX', 'content': '10 mail.smoketest.example.', 'ttl': '3600', 'disabled': '0'}, zoneid=Z))
check('invalid TTL refused', a.j('zones.php', 'createrecord', {'name': 'x', 'type': 'A', 'content': '192.0.2.1', 'ttl': 'abc'}, zoneid=Z), 'ERROR')
expect('IPv4 PTR created', records(a, REV4, 'PTR') == [('11.2.0.192.in-addr.arpa.', 'PTR', 'mail.smoketest.example.')], records(a, REV4, 'PTR'))
expect('IPv6 PTR created', records(a, REV6, 'PTR') == [('1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.' + REV6, 'PTR', 'v6.smoketest.example.')], records(a, REV6, 'PTR'))
expect('TXT is quoted', ('smoketest.example.', 'TXT', '"v=spf1 -all"') in records(a, Z))
recs = check('list records (sorted)', a.j('zones.php', 'listrecords', zoneid=Z, jtSorting='type ASC'))
check('filter records', a.j('zones.php', 'listrecords', {'label': 'www', 'type': 'A'}, zoneid=Z))
www = next(x for x in recs.get('Records', []) if x['name'].startswith('www.'))
e = check('edit record', a.j('zones.php', 'editrecord', {'id': www['id'], 'name': www['name'], 'type': 'A', 'content': '192.0.2.20',
                                                          'ttl': '600', 'disabled': '1', 'setptr': '0'}, zoneid=Z))
check('delete record', a.j('zones.php', 'deleterecord', {'id': e['Record']['id']}, zoneid=Z))
check('export zone', a.j('zones.php', 'export', zoneid=Z))
check('update zone', a.j('zones.php', 'update', {'id': Z, 'account': 'admin'}))
check('clone zone', a.j('zones.php', 'clone', {'sourcename': Z, 'destname': CLONE.rstrip('.'), 'kind': 'Master'}))
cr = [(n, t) for n, t, c in records(a, CLONE)]
expect('clone has the records of the source', ('mail.' + CLONE, 'A') in cr and (CLONE, 'MX') in cr and cr.count((CLONE, 'SOA')) == 1, cr)
check('zone list for forms', a.j('zones.php', 'formzonelist'))
check('create slave zone', a.j('zones.php', 'create', {'name': SLAVE, 'kind': 'Slave', 'masters': '192.0.2.53, 192.0.2.54'}))
check('list slave zones', a.j('zones.php', 'listslaves'))
check('change slave masters', a.j('zones.php', 'update', {'id': SLAVE, 'masters': '192.0.2.55'}))

# users
check('create user', a.j('users.php', 'create', {'emailaddress': CUST, 'password': 'Customer-test-123', 'isadmin': '0'}))
check('list users', a.j('users.php', 'list'))
check('user options', a.j('users.php', 'listoptions'))
uid = next(u['id'] for u in a.j('users.php', 'list')['Records'] if u['emailaddress'] == CUST)
check('update user', a.j('users.php', 'update', {'id': uid, 'isadmin': '0', 'password': 'Customer-test-456'}))
check('give clone to customer', a.j('zones.php', 'update', {'id': CLONE, 'account': CUST}))

# non-admin user
k = Client()
expect('login customer', k.login(CUST, 'Customer-test-456'))
names = [z['name'] for z in k.j('zones.php', 'list').get('Records', [])]
expect('customer only sees own zone', names == [CLONE], names)
check('customer: records of own zone', k.j('zones.php', 'listrecords', zoneid=CLONE))
check('customer: records of other zone refused', k.j('zones.php', 'listrecords', zoneid=Z), 'ERROR')
check('customer: export of other zone refused', k.j('zones.php', 'export', zoneid=Z), 'ERROR')
check('customer: edit other zone refused', k.j('zones.php', 'createrecord', {'name': 'x', 'type': 'A', 'content': '192.0.2.8'}, zoneid=Z), 'ERROR')
check('customer: users.php refused', k.j('users.php', 'list'), 'ERROR')
check('customer: create zone refused', k.j('zones.php', 'create', {'name': 'no.example.', 'kind': 'Master'}), 'ERROR')
check('customer: clone zone refused', k.j('zones.php', 'clone', {'sourcename': CLONE, 'destname': 'no.example', 'kind': 'Master'}), 'ERROR')
good = k.csrf
k.csrf = 'wrong'
k.j('zones.php', 'createrecord', {'name': 'csrf', 'type': 'A', 'content': '192.0.2.9'}, zoneid=CLONE)
k.csrf = good
expect('no record created without a valid csrf token', not [r for r in records(k, CLONE) if r[0].startswith('csrf.')])

# change password through the form (csrf token taken from the page)
tok = re.search(r'name="csrf-token" value="([^"]+)"', k.req('index.php'))
k.req('index.php', {'formname': 'changepwform', 'username': CUST, 'password': 'Customer-test-789',
                    'password2': 'Customer-test-789', 'csrf-token': tok.group(1) if tok else ''})
expect('change password through form', Client().login(CUST, 'Customer-test-789'))

# auto-login ("remember me", needs NSEDIT_SECRET)
if env.get('NSEDIT_SECRET'):
    al = Client()
    al.login(CUST, 'Customer-test-789', autologin='1')
    cookie = [c.value for c in al.jar if c.name == 'NSEDIT_AUTOLOGIN']
    al2 = Client('NSEDIT_AUTOLOGIN=' + cookie[0]) if cookie else Client()
    al2.req('index.php')
    expect('auto-login with encrypted cookie', bool(cookie) and al2.j('zones.php', 'list').get('Result') == 'OK')
    al3 = Client('NSEDIT_AUTOLOGIN=enc%3Aaaaa%3Abbbb')
    al3.req('index.php')
    expect('forged auto-login cookie refused', al3.j('zones.php', 'list').get('Result') != 'OK')

# logs
check('list logs', a.j('logs.php', 'list'))
check('filter logs', a.j('logs.php', 'list', {'user': 'admin', 'entry': 'zone'}))

# clean up
if not os.environ.get('KEEP'):
    for z in (CLONE, SLAVE, REV4, REV6, Z):
        check('delete zone ' + z, a.j('zones.php', 'delete', {'id': z}))
    check('delete user', a.j('users.php', 'delete', {'id': uid}))
a.req('index.php', get={'logout': 1})
expect('logout', 'loginform' in a.req('index.php'))

print('\nFAILURES:', fails)
sys.exit(1 if fails else 0)
