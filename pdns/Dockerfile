# PowerDNS Authoritative with the security updates of the Debian base that are newer than the image
FROM powerdns/pdns-auth-50:5.0.8
USER root
RUN apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*
USER pdns
