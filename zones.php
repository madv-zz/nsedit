<?php

include_once('includes/config.inc.php');
include_once('includes/session.inc.php');
include_once('includes/misc.inc.php');
include_once('includes/class/PdnsApi.php');
include_once('includes/class/Zone.php');

if (!is_csrf_safe()) {
    header('Location: ./index.php');
    jtable_respond(null, 'error', "Authentication required");
}


$quoteus = array('TXT', 'SPF');

/* This function is taken from:
http://pageconfig.com/post/how-to-validate-ascii-text-in-php and got fixed by
#powerdns */
function is_ascii($string) {
    return ( bool ) ! preg_match( '/[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x80-\\xff]/' , $string );
}

function _valid_label($name) {
    return is_ascii($name) && ( bool ) preg_match("/^([-.a-z0-9_\/\*]+)?.$/i", $name );
}

function decode_record_id($id) {
    $record = json_decode($id, true);
    if (!$record
        || !isset($record['name'])
        || !isset($record['type'])
        || !isset($record['ttl'])
        || !isset($record['content'])
        || !isset($record['disabled'])) {
        jtable_respond(null, 'error', "Invalid record id");
    }
    return $record;
}

function compareName($a, $b) {
    $a = array_reverse(explode('.', $a));
    $b = array_reverse(explode('.', $b));
    for ($i = 0; ; ++$i) {
        if (!isset($a[$i])) {
            return isset($b[$i]) ? -1 : 0;
        } else if (!isset($b[$i])) {
            return 1;
        }
        $cmp = strnatcasecmp($a[$i], $b[$i]);
        if ($cmp) {
            return $cmp;
        }
    }
}

function zone_compare($a, $b) {
    if ($cmp = strnatcasecmp($a['name'], $b['name'])) return $cmp;
    return 0;
}

function rrtype_compare($a, $b) {
    # sort specials before everything else
    $specials = array('SOA', 'NS', 'MX');
    $spa = array_search($a, $specials, true);
    $spb = array_search($b, $specials, true);
    if ($spa === false) {
        return ($spb === false) ? strcmp($a, $b) : 1;
    } else {
        return ($spb === false) ? -1 : $spa - $spb;
    }
}

function record_compare_default($a, $b) {
    if ($cmp = compareName($a['name'], $b['name'])) return $cmp;
    if ($cmp = rrtype_compare($a['type'], $b['type'])) return $cmp;
    if ($cmp = strnatcasecmp($a['content'], $b['content'])) return $cmp;
    return 0;
}

function record_compare_name($a, $b) {
    return record_compare_default($a, $b);
}

function record_compare_type($a, $b) {
    if ($cmp = rrtype_compare($a['type'], $b['type'])) return $cmp;
    if ($cmp = compareName($a['name'], $b['name'])) return $cmp;
    if ($cmp = strnatcasecmp($a['content'], $b['content'])) return $cmp;
    return 0;
}

function record_compare_content($a, $b) {
    if ($cmp = strnatcasecmp($a['content'], $b['content'])) return $cmp;
    if ($cmp = compareName($a['name'], $b['name'])) return $cmp;
    if ($cmp = rrtype_compare($a['type'], $b['type'])) return $cmp;
    return 0;
}

function add_db_zone($zonename, $accountname) {
    if (valid_user($accountname) === false) {
        jtable_respond(null, 'error', "$accountname is not a valid username");
    }
    if (!_valid_label($zonename)) {
        jtable_respond(null, 'error', "$zonename is not a valid zonename");
    }

    if (is_apiuser() && !user_exists($accountname)) {
        add_user($accountname);
    }

    $db = get_db();
    $q = $db->prepare("INSERT OR REPLACE INTO zones (zone, owner) VALUES (?, (SELECT id FROM users WHERE emailaddress = ?))");
    $q->bindValue(1, $zonename, SQLITE3_TEXT);
    $q->bindValue(2, $accountname, SQLITE3_TEXT);
    $q->execute();
}

function delete_db_zone($zonename) {
    if (!_valid_label($zonename)) {
        jtable_respond(null, 'error', "$zonename is not a valid zonename");
    }
    $db = get_db();
    $q = $db->prepare("DELETE FROM zones WHERE zone = ?");
    $q->bindValue(1, $zonename, SQLITE3_TEXT);
    $q->execute();
}

function get_zone_account($zonename, $default) {
    if (!_valid_label($zonename)) {
        jtable_respond(null, 'error', "$zonename is not a valid zonename");
    }
    $db = get_db();
    $q = $db->prepare("SELECT u.emailaddress FROM users u, zones z WHERE z.owner = u.id AND z.zone = ?");
    $q->bindValue(1, $zonename, SQLITE3_TEXT);
    $result = $q->execute();
    $zoneinfo = $result->fetchArray(SQLITE3_ASSOC);
    if (isset($zoneinfo['emailaddress']) && $zoneinfo['emailaddress'] != null ) {
        return $zoneinfo['emailaddress'];
    }

    return $default;
}

function quote_content($content) {
    # empty TXT records are ok, otherwise require surrounding quotes: "..."
    if (strlen($content) == 1 || substr($content, 0, 1) !== '"' || substr($content, -1) !== '"') {
        # fix quoting: first escape all \, then all ", then surround with quotes.
        $content = '"'.str_replace('"', '\\"', str_replace('\\', '\\\\', $content)).'"';
    }

    return $content;
}

function check_account($zone) {
    $account = is_array($zone) ? ($zone['account'] ?? '') : $zone->account;
    return is_adminuser() or ($account === get_sess_user());
}

# Load a zone from the API and make sure the current user may access it.
function load_zone_checked($api, $zoneid) {
    $zone = new Zone();
    $zone->parse($api->loadzone($zoneid));
    if ($zone->account == '') {
        $zone->setAccount(get_zone_account($zone->name, 'admin'));
    }
    if (!check_account($zone)) {
        jtable_respond(null, 'error', "You don't have access to this zone");
    }
    return $zone;
}

# Reverse DNS name for an IPv4/IPv6 address, or false.
function reverse_name($ip) {
    $packed = @inet_pton($ip);
    if ($packed === false) {
        return false;
    }
    if (strlen($packed) == 4) {
        return implode('.', array_reverse(explode('.', inet_ntop($packed)))) . '.in-addr.arpa.';
    }
    return implode('.', array_reverse(str_split(bin2hex($packed)))) . '.ip6.arpa.';
}

# Reverse zones that cover an IPv4/IPv6 prefix such as 185.69.204.0/22 or 2a06:900::/29.
# IPv4 zones are /8, /16 or /24 (a /22 gives four /24 zones), IPv6 zones end on a nibble
# (a /29 gives eight /32 zones). Returns an array of zone names, or an error string.
function reverse_zones_for_prefix($prefix, $max) {
    $shown = htmlspecialchars($prefix, ENT_QUOTES);  # jTable shows error messages as HTML
    if (!preg_match('#^([0-9a-fA-F:.]+)/([0-9]{1,3})$#', trim($prefix), $m)) {
        return "$shown: use address/length, e.g. 192.0.2.0/24";
    }
    $packed = @inet_pton($m[1]);
    $len = (int) $m[2];
    if ($packed === false) {
        return "$shown: not an IP address";
    }
    $v4 = strlen($packed) == 4;
    $bits = $v4 ? 32 : 128;
    $step = $v4 ? 8 : 4;
    if ($len > $bits) {
        return "$shown: prefix length is too long";
    }
    if ($v4 && $len > 24) {
        return "$shown: IPv4 prefixes longer than /24 need classless delegation (RFC 2317), not supported";
    }
    # the zone length: the prefix length rounded up to the next label boundary
    $zonelen = (int) (ceil($len / $step) * $step);
    if ($zonelen == 0) {
        return "$shown: too short";
    }
    $count = 1 << ($zonelen - $len);
    if ($count > $max) {
        return "$shown: gives $count zones, more than the maximum of $max";
    }
    # the address as a string of bits; check that no bits are set after the prefix
    $bin = '';
    foreach (str_split($packed) as $c) {
        $bin .= str_pad(decbin(ord($c)), 8, '0', STR_PAD_LEFT);
    }
    if (strpos(substr($bin, $len), '1') !== false) {
        return "$shown: host bits are set, did you mean ".inet_ntop(pack_bits(substr($bin, 0, $len), $bits))."/$len?";
    }
    $zones = array();
    for ($i = 0; $i < $count; $i++) {
        $extra = $zonelen - $len;
        $zonebits = substr($bin, 0, $len) . ($extra ? str_pad(decbin($i), $extra, '0', STR_PAD_LEFT) : '');
        $labels = array();
        foreach (str_split($zonebits, $step) as $chunk) {
            $labels[] = $v4 ? (string) bindec($chunk) : dechex(bindec($chunk));
        }
        $zones[] = implode('.', array_reverse($labels)) . ($v4 ? '.in-addr.arpa.' : '.ip6.arpa.');
    }
    return $zones;
}

# A string of bits, padded with zeroes to $bits, as a packed address for inet_ntop().
function pack_bits($bitstring, $bits) {
    $bitstring = str_pad($bitstring, $bits, '0');
    $packed = '';
    foreach (str_split($bitstring, 8) as $byte) {
        $packed .= chr(bindec($byte));
    }
    return $packed;
}

# The most specific reverse zone for $revname that the current user may change, or false.
# Zones of other users are skipped: for an ISP the reverse zones usually belong to the admin.
function find_ptr_zone($api, $revname) {
    $best = false;
    foreach ($api->listzones() as $z) {
        $zname = $z['name'] ?? '';
        if (($z['kind'] ?? '') == 'Slave' || $zname == '') continue;
        if (!string_ends_with($revname, '.'.$zname) && $revname !== $zname) continue;
        if (($z['account'] ?? '') == '') {
            $z['account'] = get_zone_account($zname, 'admin');
        }
        if (!check_account($z)) continue;
        if ($best === false || strlen($zname) > strlen($best)) {
            $best = $zname;
        }
    }
    return $best;
}

# Move the records that fall inside a newly created zone out of its parent zone (the
# most specific existing zone above it) into the new zone. Without this, records such as
# the PTRs of a /56 that is split off a /32 become invisible: PowerDNS answers from the
# new, empty zone. NS and DS records at the apex of the new zone stay in the parent
# (they are the delegation). Only done when the user may change the parent zone.
# Returns array(parent zone name or false, number of records moved).
function move_records_from_parent($api, $zonename) {
    $parentname = false;
    foreach ($api->listzones() as $z) {
        $zname = $z['name'] ?? '';
        if ($zname == '' || $zname === $zonename || ($z['kind'] ?? '') == 'Slave') continue;
        if (!string_ends_with($zonename, '.'.$zname)) continue;
        if ($parentname === false || strlen($zname) > strlen($parentname)) {
            $parentname = $zname;
        }
    }
    if ($parentname === false) {
        return array(false, 0);
    }
    $parent = new Zone();
    $parent->parse($api->loadzone($parentname));
    if ($parent->account == '') {
        $parent->setAccount(get_zone_account($parentname, 'admin'));
    }
    if (!check_account($parent)) {
        writelog("Records under $zonename not moved: no access to parent zone $parentname");
        return array($parentname, 0);
    }
    $move = array();
    $count = 0;
    foreach ($parent->rrsets as $rrset) {
        if ($rrset->name !== $zonename && !string_ends_with($rrset->name, '.'.$zonename)) continue;
        if ($rrset->name === $zonename && in_array($rrset->type, array('SOA', 'NS', 'DS'), true)) continue;
        $move[] = $rrset;
        $count += count($rrset->records);
    }
    if (!$move) {
        return array($parentname, 0);
    }
    # first add them to the new zone; only when that worked, remove them from the parent
    $child = new Zone();
    $child->parse($api->loadzone($zonename));
    $child->rrsets = $move;
    $api->savezone($child->export());
    foreach ($move as $rrset) {
        $rrset->delete();
    }
    $parent->rrsets = $move;
    save_reverse_zone($api, $parent);
    writelog("Moved $count records under $zonename from $parentname into $zonename");
    return array($parentname, $count);
}

# Work out where the PTR for an A/AAAA record goes, before anything is saved, so an
# invalid address gives an error without changing the zone. Returns null when no PTR
# is wanted, otherwise array(reverse name, reverse zone or false).
function plan_ptr($api, $type, $ip) {
    if (empty($_POST['setptr']) || ($type != 'A' && $type != 'AAAA')) {
        return null;
    }
    $revname = reverse_name($ip);
    if ($revname === false) {
        jtable_respond(null, 'error', "Cannot create PTR: $ip is not an IP address");
    }
    return array($revname, find_ptr_zone($api, $revname));
}

# Save a changed reverse zone; raises its SOA serial like the forward zone paths do.
function save_reverse_zone($api, $revzone) {
    global $defaults;
    $revzone->setSoaEditApi($defaults['soa_edit_api']);
    $api->savezone($revzone->export());
}

# Create/replace the PTR record planned by plan_ptr(). PowerDNS used to do this with
# 'set-ptr', which was removed from its API in version 4.4. Runs after the forward
# record was saved: a failure is logged, not reported as a failed save.
function set_ptr_record($api, $plan, $hostname, $ttl, $disabled) {
    if ($plan === null) {
        return;
    }
    list($revname, $revzonename) = $plan;
    if ($revzonename === false) {
        writelog("No reverse zone you can change for $revname, PTR not set");
        return;
    }
    try {
        $revzone = load_zone_checked($api, $revzonename);
        $rrset = $revzone->getRRSet($revname, 'PTR');
        if ($rrset !== FALSE) {
            foreach ($rrset->records as $r) {
                $rrset->deleteRecord($r->content);
            }
            $rrset->addRecord($hostname, $disabled);
            $rrset->setTtl($ttl);
        } else {
            $revzone->addRecord($revname, 'PTR', $hostname, $disabled, $ttl);
        }
        save_reverse_zone($api, $revzone);
        writelog("Set PTR $revname -> $hostname");
    } catch (Exception $e) {
        writelog("Could not set PTR $revname -> $hostname: ".$e->getMessage());
    }
}

# Remove the PTR of an old A/AAAA address if it still points to $hostname.
function remove_old_ptr_record($api, $ip, $hostname) {
    $revname = reverse_name($ip);
    $revzonename = $revname === false ? false : find_ptr_zone($api, $revname);
    if ($revzonename === false) {
        return;
    }
    try {
        $revzone = load_zone_checked($api, $revzonename);
        $rrset = $revzone->getRRSet($revname, 'PTR');
        if ($rrset === FALSE) {
            return;
        }
        foreach ($rrset->records as $r) {
            if ($r->content === $hostname) {
                $rrset->deleteRecord($hostname);
                if (count($rrset->records) == 0) {
                    $rrset->delete();
                }
                save_reverse_zone($api, $revzone);
                writelog("Removed old PTR $revname -> $hostname");
                return;
            }
        }
    } catch (Exception $e) {
        writelog("Could not remove old PTR $revname -> $hostname: ".$e->getMessage());
    }
}

function post_ttl() {
    global $defaults;
    $ttl = isset($_POST['ttl']) && $_POST['ttl'] !== '' ? $_POST['ttl'] : $defaults['ttl'];
    # no ctype_digit(): the ctype extension is a separate package on BSD and nsedit does not need it otherwise
    if (!preg_match('/^[0-9]+$/', (string) $ttl)) {
        jtable_respond(null, 'error', "TTL must be a positive number");
    }
    return (int) $ttl;
}

if (isset($_GET['action'])) {
    $action = $_GET['action'];
} else {
    jtable_respond(null, 'error', 'No action given');
}

try {
$api = new PdnsAPI;

switch ($action) {

case "list":
case "listslaves":
    $return = Array();
    $q = isset($_POST['domsearch']) ? $_POST['domsearch'] : false;
    foreach ($api->listzones($q) as $sresult) {
        $zone = new Zone();
        $zone->parse($sresult);
        if ($zone->account == '') {
            $zone->setAccount(get_zone_account($zone->name, 'admin'));
        }

        if (!check_account($zone))
            continue;

        if ($action == "listslaves" and $zone->kind == "Slave") {
            array_push($return, $zone->export());
        } elseif ($action == "list" and $zone->kind != "Slave") {
            if ($zone->dnssec) {
                $zone->setKeyinfo($api->getzonekeys($zone->id));
            }
            array_push($return, $zone->export());
        }
    }
    usort($return, "zone_compare");
    jtable_respond($return);
    break;

case "listrecords":
    $zone = load_zone_checked($api, $_GET['zoneid'] ?? '');
    $records = $zone->rrsets2records();

    if(!empty($_POST['label'])) {
        $records=array_filter($records,
            function ($val) {
                return(stripos($val['name'], $_POST['label']) !== FALSE);
            }
        );
    }

    if(!empty($_POST['type'])) {
        $records=array_filter($records,
            function ($val) {
                return($val['type'] == $_POST['type']);
            }
        );
    }

    if(!empty($_POST['content'])) {
        $records=array_filter($records,
            function ($val) {
                return(stripos($val['content'], $_POST['content']) !== FALSE);
            }
        );
    }

    if (isset($_GET['jtSorting'])) {
        list($scolumn, $sorder) = array_pad(preg_split("/ /", $_GET['jtSorting']), 2, 'ASC');
        switch ($scolumn) {
            case "type":
                usort($records, "record_compare_type");
                break;
            case "content":
                usort($records, "record_compare_content");
                break;
            default:
                usort($records, "record_compare_name");
                break;
        }
        if ($sorder == "DESC") {
            $records = array_reverse($records);
        }
    } else {
        usort($records, "record_compare_name");
    }
    jtable_respond($records);
    break;

case "delete":
    $zone = load_zone_checked($api, $_POST['id'] ?? '');
    $api->deletezone($zone->id);

    delete_db_zone($zone->name);
    writelog("Deleted zone ".$zone->name);
    jtable_respond(null, 'delete');
    break;


case "create":
    $zonename = isset($_POST['name']) ? $_POST['name'] : '';
    $zonekind = isset($_POST['kind']) ? $_POST['kind'] : '';

    if (!is_adminuser() and $allowzoneadd !== true) {
        jtable_respond(null, 'error', "You are not allowed to add zones");
    }
    if (!_valid_label($zonename)) {
        jtable_respond(null, 'error', "Please only use [a-z0-9_/.-]");
    }

    if (!$zonename || !$zonekind) {
        jtable_respond(null, 'error', "Not enough data");
    }

    $zone = new Zone();
    $zone->setKind($zonekind);
    $zone->setName($zonename);

    if ($zonekind != "Slave") {
        if (!isset($_POST['zone']) or isset($_POST['owns'])) {
            foreach ((array) ($_POST['nameserver'] ?? array()) as $ns) {
                if (trim($ns) === '') continue;
                $zone->addNameserver(trim($ns));
            }
        } else {
            $zone->importData($_POST['zone']);
        }
        if (isset($defaults['soa_edit_api'])) {
            $zone->setSoaEditApi($defaults['soa_edit_api'], True);
        }
        if (isset($defaults['soa_edit'])) {
            $zone->setSoaEdit($defaults['soa_edit']);
        }
    } else { // Slave
        if (isset($_POST['masters'])) {
            foreach (preg_split('/[,;\s]+/', $_POST['masters'], -1, PREG_SPLIT_NO_EMPTY) as $master) {
                $zone->addMaster($master);
            }
        }
    }

    // only admin user and original account can "recreate" zones that are already
    // present in our own db but got lost in pdns.
    if (!is_adminuser() && get_sess_user() !== get_zone_account($zonename, get_sess_user())) {
        jtable_respond(null, 'error', 'Zone already owned by someone else');
    }

    $api->savezone($zone->export());

    $zone = new Zone();
    $zone->parse($api->loadzone($zonename));
    $zonename = $zone->name;

    if (is_adminuser() && isset($_POST['account'])) {
        add_db_zone($zonename, $_POST['account']);
        $zone->setAccount($_POST['account']);
    } else {
        add_db_zone($zonename, get_sess_user());
        $zone->setAccount(get_sess_user());
    }

    if (isset($_POST['template']) && $_POST['template'] != 'None') {
        foreach (user_template_list() as $template) {
            if ($template['name'] !== $_POST['template']) continue;

            foreach ($template['records'] as $record) {
                $rrset = $zone->getRRSet($record['name'], $record['type']);
                if ($rrset) {
                    $rrset->delete();
                }
            }
            $api->savezone($zone->export());

            foreach ($template['records'] as $record) {
                if ($record['type'] == 'NS') continue;
                $name = $record['name'] != '' ? join(Array($record['name'],'.',$zonename)) : $zonename;
                $record['content'] = str_replace("[zonename]", $zonename, $record['content']);
                $zone->addRecord($name, $record['type'], $record['content']);
            }

            break;
        }
    }

    $zone = $api->savezone($zone->export());
    writelog("Created zone ".$zone['name']);
    if (!empty($_POST['moverecords']) && $zonekind != 'Slave') {
        try {
            move_records_from_parent($api, $zone['name']);
            $zone = $api->loadzone($zone['name']);
        } catch (Exception $e) {
            writelog("Records under ".$zone['name']." not moved from the parent zone: ".$e->getMessage());
        }
    }
    jtable_respond($zone, 'single');
    break;

case "update":
    $zone = load_zone_checked($api, $_POST['id'] ?? '');
    if ($zone->setSoaEditApi($defaults['soa_edit_api']) != False)
        writelog("Set SOA-EDIT-API to ".$defaults['soa_edit_api']." for ".$zone->name);
    $zoneaccount = isset($_POST['account']) ? $_POST['account'] : $zone->account;

    if ($zone->account !== $zoneaccount) {
        if (!is_adminuser()) {
            jtable_respond(null, 'error', "Can't change account");
        } else {
            add_db_zone($zone->name, $zoneaccount);
            $zone->setAccount($zoneaccount);
        }
    }

    if (isset($_POST['masters'])) {
        $zone->eraseMasters();
        foreach(preg_split('/[,;\s]+/', $_POST['masters'], -1, PREG_SPLIT_NO_EMPTY) as $master) {
            $zone->addMaster($master);
        }
    }

    writelog("Updated zone ".$zone->name);
    jtable_respond($api->savezone($zone->export()), 'single');
    break;

case "createrecord":
    $zone = load_zone_checked($api, $_GET['zoneid'] ?? '');
    if ($zone->setSoaEditApi($defaults['soa_edit_api']) != False)
        writelog("Set SOA-EDIT-API to ".$defaults['soa_edit_api']." for ".$zone->name);

    $name = isset($_POST['name']) ? $_POST['name'] : '';
    $type = $_POST['type'] ?? '';
    $content = $_POST['content'] ?? '';

    if ('' == $name) {
        $name = $zone->name;
    } elseif (string_ends_with($name, '.')) {
        # "absolute" name, shouldn't append zone[name] - but check.
        if (!string_ends_with($name, $zone->name)) {
            jtable_respond(null, 'error', "Name $name not in zone ".$zone->name);
        }
    } else if (!string_ends_with($name.'.', $zone->name)) {
        $name = $name . '.' . $zone->name;
    } else {
        $name = $name.'.';
    }

    if (!_valid_label($name)) {
        jtable_respond(null, 'error', "Please only use [a-z0-9_/.-]");
    }
    if (!$type) {
        jtable_respond(null, 'error', "Require a type");
    }
    if (!is_ascii($content)) {
        jtable_respond(null, 'error', "Please only use ASCII-characters in your fields");
    }

    if (array_search($type, $quoteus) !== FALSE) {
        $content = quote_content($content);
    }

    $ptrplan = plan_ptr($api, $type, $content);
    $record = $zone->addRecord($name, $type, $content, (bool) ($_POST['disabled'] ?? false), post_ttl(), (bool) ($_POST['setptr'] ?? false));
    $api->savezone($zone->export());
    set_ptr_record($api, $ptrplan, $name, post_ttl(), (bool) ($_POST['disabled'] ?? false));

    writelog("Created record: ".$record['id']);
    jtable_respond($record, 'single');
    break;

case "editrecord":
    $zone = load_zone_checked($api, $_GET['zoneid'] ?? '');
    if ($zone->setSoaEditApi($defaults['soa_edit_api']) != False)
        writelog("Set SOA-EDIT-API to ".$defaults['soa_edit_api']." for ".$zone->name);

    $old_record = decode_record_id(isset($_POST['id']) ? $_POST['id'] : '');

    $rrset = $zone->getRRSet($old_record['name'], $old_record['type']);
    if ($rrset === FALSE) {
        jtable_respond(null, 'error', "Record not found");
    }
    $rrset->deleteRecord($old_record['content']);

    $name = $_POST['name'] ?? '';
    $content = $_POST['content'] ?? '';
    $type = $_POST['type'] ?? '';
    if (!_valid_label($name)) {
        jtable_respond(null, 'error', "Please only use [a-z0-9_/.-]");
    }
    if (!is_ascii($content)) {
        jtable_respond(null, 'error', "Please only use ASCII-characters in your fields");
    }
    if (array_search($type, $quoteus) !== FALSE) {
        $content = quote_content($content);
    }

    $ptrplan = plan_ptr($api, $type, $content);
    $zone->addRecord($name, $type, $content, (bool) ($_POST['disabled'] ?? false), post_ttl(), (bool) ($_POST['setptr'] ?? false));

    $api->savezone($zone->export());
    if ($ptrplan !== null && in_array($old_record['type'], array('A', 'AAAA'), true)
        && ($old_record['content'] !== $content || $old_record['name'] !== $name)) {
        remove_old_ptr_record($api, $old_record['content'], $old_record['name']);
    }
    set_ptr_record($api, $ptrplan, $name, post_ttl(), (bool) ($_POST['disabled'] ?? false));

    $record = $zone->getRecord($name, $type, $content);
    writelog("Updated record ".$_POST['id']." to ".$record['id']);
    jtable_respond($record, 'single');
    break;

case "deleterecord":
    $zone = load_zone_checked($api, $_GET['zoneid'] ?? '');
    if ($zone->setSoaEditApi($defaults['soa_edit_api']) != False)
        writelog("Set SOA-EDIT-API to ".$defaults['soa_edit_api']." for ".$zone->name);

    $old_record = decode_record_id(isset($_POST['id']) ? $_POST['id'] : '');
    $rrset = $zone->getRRSet($old_record['name'], $old_record['type']);
    if ($rrset === FALSE) {
        jtable_respond(null, 'error', "Record not found");
    }
    $rrset->deleteRecord($old_record['content']);

    $api->savezone($zone->export());

    writelog("Deleted record ".$_POST['id']);
    jtable_respond(null, 'delete');
    break;

case "export":
    load_zone_checked($api, $_GET['zoneid'] ?? '');
    writelog("Exported zone ".$_GET['zoneid']);
    jtable_respond($api->exportzone($_GET['zoneid']), 'single');
    break;

case "clone":
    $name = $_POST['destname'] ?? '';
    $src  = $_POST['sourcename'] ?? '';

    if (!string_ends_with($name, '.')) {
        $name = $name.".";
    }

    if (!_valid_label($name)) {
        jtable_respond(null, 'error', "Invalid destination zonename");
    }

    if (!is_adminuser() and $allowzoneadd !== true) {
        jtable_respond(null, 'error', "You are not allowed to add zones");
    }
    if (!is_adminuser() && get_sess_user() !== get_zone_account($name, get_sess_user())) {
        jtable_respond(null, 'error', 'Zone already owned by someone else');
    }

    $srczone = load_zone_checked($api, $src);
    $srcname = $srczone->name;
    # keep the rrsets of the source, renamed to the new zone; not its SOA: the new
    # zone keeps the SOA PowerDNS made for it (the source SOA names the source zone)
    $srcrrsets = array();
    foreach ($srczone->rrsets as $rrset) {
        if ($rrset->type == 'SOA') continue;
        $rrset->setName(preg_replace('/'.preg_quote($srcname, '/').'$/', $name, $rrset->name));
        $srcrrsets[] = $rrset;
    }
    $srczone->rrsets = array();

    $srczone->setId('');
    $srczone->setName($name);
    $srczone->setSerial('');
    $srczone->setKind($_POST['kind'] ?? 'Master');
    $srczone->eraseMasters();
    if ($srczone->setSoaEditApi($defaults['soa_edit_api']) != False)
        writelog("Set SOA-EDIT-API to ".$defaults['soa_edit_api']." for ".$name);

    # create the (empty) zone, then replace its rrsets with those of the source.
    # Don't mix both sets: PowerDNS 5 rejects duplicate rrsets in one PATCH.
    $newzone = new Zone();
    $newzone->parse($api->savezone($srczone->export()));
    $newzone->rrsets = $srcrrsets;

    if (is_adminuser() && isset($_POST['account'])) {
        add_db_zone($name, $_POST['account']);
        $newzone->setAccount($_POST['account']);
    } else {
        add_db_zone($name, get_sess_user());
        $newzone->setAccount(get_sess_user());
    }

    $zone = $api->savezone($newzone->export());

    writelog("Cloned zone $srcname into $name");
    jtable_respond($zone, 'single');
    break;

case "createreverse":
    # Create all reverse zones for one or more prefixes (admin only). Zones that
    # already exist are left alone; nothing is created when a prefix is invalid.
    if (!is_adminuser()) {
        jtable_respond(null, 'error', "You are not allowed to add reverse zones");
    }
    $max = 256;
    $kind = $_POST['kind'] ?? 'Master';
    if (!in_array($kind, array('Master', 'Native'), true)) {
        jtable_respond(null, 'error', "Type must be Master or Native");
    }
    $prefixes = preg_split('/[\s,;]+/', $_POST['prefixes'] ?? '', -1, PREG_SPLIT_NO_EMPTY);
    if (!$prefixes) {
        jtable_respond(null, 'error', "Give at least one prefix, e.g. 192.0.2.0/24");
    }
    $wanted = array();
    foreach ($prefixes as $prefix) {
        $res = reverse_zones_for_prefix($prefix, $max);
        if (!is_array($res)) {
            jtable_respond(null, 'error', $res);
        }
        $wanted = array_merge($wanted, $res);
    }
    $wanted = array_values(array_unique($wanted));
    if (count($wanted) > $max) {
        jtable_respond(null, 'error', count($wanted)." zones, more than the maximum of $max per request");
    }
    $nameservers = array();
    foreach ((array) ($_POST['nameserver'] ?? array()) as $ns) {
        if (trim($ns) !== '') $nameservers[] = trim($ns);
    }
    if (!$nameservers && $kind == 'Master') {
        jtable_respond(null, 'error', "Give at least one nameserver");
    }
    $account = $_POST['account'] ?? get_sess_user();

    $existing = array();
    foreach ($api->listzones() as $z) {
        $existing[$z['name']] = true;
    }
    $moverecords = !empty($_POST['moverecords']);
    $created = $skipped = $failed = $moved = array();
    foreach ($wanted as $zonename) {
        if (isset($existing[$zonename])) {
            $skipped[] = $zonename;
            continue;
        }
        try {
            $zone = new Zone();
            $zone->setKind($kind);
            $zone->setName($zonename);
            foreach ($nameservers as $ns) {
                $zone->addNameserver($ns);
            }
            if (isset($defaults['soa_edit_api'])) {
                $zone->setSoaEditApi($defaults['soa_edit_api'], True);
            }
            if (isset($defaults['soa_edit'])) {
                $zone->setSoaEdit($defaults['soa_edit']);
            }
            $api->savezone($zone->export());
            add_db_zone($zonename, $account);
            writelog("Created reverse zone $zonename");
            $created[] = $zonename;
        } catch (Exception $e) {
            $failed[] = "$zonename: ".$e->getMessage();
            continue;
        }
        if ($moverecords) {
            try {
                list($parentname, $n) = move_records_from_parent($api, $zonename);
                if ($n > 0) $moved[] = "$zonename: $n from $parentname";
            } catch (Exception $e) {
                $failed[] = "$zonename: created, but records not moved from the parent zone: ".$e->getMessage();
            }
        }
    }
    if (!$created && $failed) {
        jtable_respond(null, 'error', "No zones created. ".implode('; ', $failed));
    }
    jtable_respond(array('id' => '', 'prefixes' => implode(' ', $prefixes),
        'created' => $created, 'skipped' => $skipped, 'failed' => $failed, 'moved' => $moved), 'single');
    break;

case "gettemplatenameservers":
    $ret = array();
    $type = $_GET['prisec'] ?? '';

    foreach (user_template_list() as $template) {
        if ($template['name'] !== ($_GET['template'] ?? '')) continue;
        $rc = 0;
        foreach ($template['records'] as $record) {
            if ($record['type'] == "NS") {
                if (($type == 'pri' && $rc == 0) or ($type == 'sec' && $rc == 1)) {
                    echo $record['content'];
                    exit(0);
                }
                $rc++;
            }
        }
        echo "";
    }
    break;
case "getformnameservers":
    $inputs = array();
    foreach (user_template_list() as $template) {
        if ($template['name'] !== ($_GET['template'] ?? '')) continue;
        foreach ($template['records'] as $record) {
            if ($record['type'] == "NS" and array_search($record['content'], $inputs) === false) {
		array_push($inputs, $record['content']);
                echo '<input type="text" name="nameserver[]" value="'.htmlspecialchars($record['content'], ENT_QUOTES).'" readonly /><br />';
            }
        }
    }
    break;
case "formzonelist":
    $zones = $api->listzones();
    usort($zones, "zone_compare");
    $ret = array();
    foreach ($zones as $zone) {
        if (($zone['account'] ?? '') == '') {
            $zone['account'] = get_zone_account($zone['name'], 'admin');
        }
        if (!check_account($zone))
            continue;
        if ($zone['kind'] == 'Slave')
            continue;
        array_push($ret, array(
            'DisplayText' => $zone['name'],
            'Value'       => $zone['id']));
    }
    jtable_respond($ret, 'options');
    break;

default:
    jtable_respond(null, 'error', 'No such action');
    break;
}
} catch (Exception $e) {
    jtable_respond(null, 'error', $e->getMessage());
}
