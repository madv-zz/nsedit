# PowerDNS Authoritative for the test stack, with the security updates of the Debian base that are newer
# than the image. The version is chosen with PDNS_IMAGE (see .env.example); CI tests 4.9, 5.0 and 5.1.
ARG PDNS_IMAGE=powerdns/pdns-auth-51:5.1.5
FROM ${PDNS_IMAGE}
USER root
RUN apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*
USER pdns
