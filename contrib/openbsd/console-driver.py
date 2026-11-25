#!/usr/bin/env python3
"""Follows the serial console of the OpenBSD VM (unix socket), answers the autoinstall questions that cannot
be answered by a response file, and stops at the login prompt of the installed system.
Usage: console-driver.py <socket> <logfile> <response-file-url> [timeout-seconds]"""
import re
import socket
import sys
import time

sock_path, log_path, url = sys.argv[1:4]
timeout = int(sys.argv[4]) if len(sys.argv) > 4 else 2400
answers = [
    (re.compile(rb'\(I\)nstall, \(U\)pgrade, \(A\)utoinstall or \(S\)hell\? *$'), b'a\n'),
    (re.compile(rb'Response file location\? *(\[[^\]]*\])? *$'), url.encode() + b'\n'),
]
done = re.compile(rb'(^|\n)login: *$')

s = socket.socket(socket.AF_UNIX)
for _ in range(50):
    try:
        s.connect(sock_path)
        break
    except OSError:
        time.sleep(0.2)
s.settimeout(1)
buf = b''
start = time.time()
installed = False
with open(log_path, 'ab') as log:
    while time.time() - start < timeout:
        try:
            data = s.recv(4096)
        except TimeoutError:
            data = b''
        if data:
            log.write(data)
            log.flush()
            buf = (buf + data)[-2000:]
            tail = buf.rstrip(b'\r\n')[-200:]
            for pattern, answer in answers:
                if pattern.search(tail):
                    s.sendall(answer)
                    print('answered:', answer.decode().strip(), flush=True)
                    buf = b''
            if not installed and b'CONGRATULATIONS' in buf:
                installed = True
                print('install finished, rebooting', flush=True)
            if installed and done.search(buf.replace(b'\r', b'').rstrip(b'\n')[-100:]):
                print('login prompt of the installed system', flush=True)
                sys.exit(0)
print('timeout', flush=True)
sys.exit(1)
