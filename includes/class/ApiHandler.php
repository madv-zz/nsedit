<?php

include_once(__DIR__ . '/../config.inc.php');

class ApiHandler {
    public $headers;
    public $hostname;
    public $port;
    public $auth;
    public $proto;
    public $sslverify;
    public $curlh;
    public $method;
    public $content;
    public $apiurl;
    public $url;
    public $json;
    
    public function __construct() {
        global $apiip, $apiport, $apipass, $apiproto, $apisslverify;

        $this->headers = Array();
        $this->hostname = $apiip;
        $this->port = $apiport;
        $this->auth = $apipass;
        $this->proto = $apiproto;
        $this->sslverify = $apisslverify;
        $this->curlh = curl_init();
        $this->method = 'GET';
        $this->content = FALSE;
        $this->apiurl = '';
    }

    public function addheader($field, $content) {
        $this->headers[$field] = $content;
    }

    private function authheaders() {
        $this->addheader('X-API-Key', $this->auth);
    }

    private function apiurl() {
        $tmp = new ApiHandler();

        $tmp->url = '/api/v1/servers/localhost';
        $tmp->go();

        if (!isset($tmp->json['url'])) {
            throw new Exception("Unexpected answer from the PowerDNS API");
        }
        $this->apiurl = $tmp->json['url'];
    }

    private function curlopts() {
        $this->authheaders();
        $this->addheader('Accept', 'application/json');

        curl_reset($this->curlh);
        curl_setopt($this->curlh, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($this->curlh, CURLOPT_CONNECTTIMEOUT, 5);
        curl_setopt($this->curlh, CURLOPT_TIMEOUT, 30);

        if (strcasecmp($this->proto, 'https') == 0) {
            curl_setopt($this->curlh, CURLOPT_SSL_VERIFYPEER, (bool) $this->sslverify);
            curl_setopt($this->curlh, CURLOPT_SSL_VERIFYHOST, $this->sslverify ? 2 : 0);
        }

        $setheaders = Array();

        foreach ($this->headers as $k => $v) {
            array_push($setheaders, join(": ", Array($k, $v)));
        }
        curl_setopt($this->curlh, CURLOPT_HTTPHEADER, $setheaders);
    }

    public function __clone() {
        // every clone needs its own curl handle
        $this->curlh = curl_init();
        $this->headers = Array();
    }

    private function baseurl() {
        $ip = $this->hostname;

        if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)) {
            $ip = sprintf('[%s]', $ip); // curl needs brackets for IPv6
        }

        return $this->proto.'://'.$ip.':'.$this->port.$this->apiurl;
    }

    private function go() {
        if ($this->content) {
            // must be added before curlopts() sets the headers
            $this->addheader('Content-Type', 'application/json');
        }

        $this->curlopts();

        if ($this->content) {
            curl_setopt($this->curlh, CURLOPT_POSTFIELDS, $this->content);
        }

        switch ($this->method) {
            case 'POST':
                curl_setopt($this->curlh, CURLOPT_POST, true);
                break;
            case 'GET':
                curl_setopt($this->curlh, CURLOPT_HTTPGET, true);
                break;
            case 'DELETE':
            case 'PATCH':
            case 'PUT':
                curl_setopt($this->curlh, CURLOPT_CUSTOMREQUEST, $this->method);
                break;
        }

        curl_setopt($this->curlh, CURLOPT_URL, $this->baseurl().$this->url);

        $return = curl_exec($this->curlh);
        if ($return === false) {
            throw new Exception("Could not connect to the PowerDNS API: ".curl_error($this->curlh));
        }
        $code = curl_getinfo($this->curlh, CURLINFO_HTTP_CODE);
        $json = ($return === '') ? null : json_decode($return, true);

        if (is_array($json) && isset($json['error'])) {
            throw new Exception("API Error $code: ".$json['error']);
        } elseif ($code < 200 || $code >= 300) {
            if ($code == 401) {
                throw new Exception("Authentication failed. Have you configured your authmethod correct?");
            }
            throw new Exception("Curl Error: $code ".curl_error($this->curlh));
        }

        $this->json = $json;
    }

    public function call() {
        if (substr($this->url, 0, 1) != '/') {
            $this->url = '/'.$this->url;
        }
        $this->apiurl();
        $this->url = str_replace($this->apiurl, '', $this->url);
        $this->go();
    }
}

