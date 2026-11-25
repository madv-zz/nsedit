<?php
# nsedit config for the Docker stack: everything comes from environment variables (see .env / docker-compose.yml).

function nsedit_env($name, $default = '') {
    $v = getenv($name);
    return ($v === false || $v === '') ? $default : $v;
}
function nsedit_env_bool($name, $default = false) {
    $v = getenv($name);
    if ($v === false || $v === '') return $default;
    return in_array(strtolower($v), array('1', 'true', 'yes', 'on'), true);
}

$apipass       = nsedit_env('PDNS_API_KEY');         # The PowerDNS API key
$apiip         = nsedit_env('PDNS_API_HOST', 'pdns'); # Host/IP of the PowerDNS API
$apiport       = nsedit_env('PDNS_API_PORT', '8081');
$apiproto      = nsedit_env('PDNS_API_PROTO', 'http'); # http | https
$apisslverify  = nsedit_env_bool('PDNS_API_SSLVERIFY', true);
$allowzoneadd  = nsedit_env_bool('NSEDIT_ALLOW_ZONEADD', false);
$logging       = TRUE;
$allowclearlogs  = TRUE;
$allowrotatelogs = FALSE;
$logsdirectory   = '/var/lib/nsedit';

$authdb  = '/var/lib/nsedit/pdns.users.sqlite3';

# Only used on the very first start (when $authdb does not exist yet)
$default_admin_username = nsedit_env('NSEDIT_ADMIN_USER', 'admin');
$default_admin_password = nsedit_env('NSEDIT_ADMIN_PASSWORD', 'admin');

# A secret enables auto-login and long living csrf tokens
$secret = nsedit_env('NSEDIT_SECRET');

$templates = array();

$defaults['soa_edit']     = 'INCEPTION-INCREMENT';
$defaults['soa_edit_api'] = 'DEFAULT';
$defaults['defaulttype']  = nsedit_env('NSEDIT_DEFAULT_KIND', 'Master');   # 'Native' or 'Master'
$defaults['ns'][0] = nsedit_env('NSEDIT_NS1', 'ns1.example.com.');
$defaults['ns'][1] = nsedit_env('NSEDIT_NS2', 'ns2.example.com.');
$defaults['ttl']   = (int) nsedit_env('NSEDIT_DEFAULT_TTL', '3600');
$defaults['disabled'] = false;

$menutype = 'horizontal';
$logo = 'img/nsedit.svg';
