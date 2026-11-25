<?php

include_once('includes/config.inc.php');
include_once('includes/session.inc.php');
include_once('includes/misc.inc.php');

if(php_sapi_name() !== 'cli') {
    echo "This script is intended to be run from the command line";
} else {
    if($allowrotatelogs === TRUE) {
        global $current_user;
        $current_user = array('username' => '<system>', 'id' => 0, 'localauth' => false,
            'is_admin' => true, 'has_csrf_token' => true, 'is_api' => false);
        rotatelogs();
    } else {
        echo "Rotating logs has been disabled.";
    }
}
