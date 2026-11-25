# nsedit on PHP 8.4+ (Apache + mod_php). Choose the PHP version with --build-arg PHP_VERSION=8.5
ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-apache

# Security updates of the Debian base that are newer than the image
RUN apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*

# Production php.ini; errors go to the container log, not to the browser (that would break jtable's JSON)
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
 && printf '%s\n' 'error_reporting = E_ALL' 'display_errors = Off' 'log_errors = On' 'error_log = /dev/stderr' \
      'expose_php = Off' 'session.use_strict_mode = 1' > "$PHP_INI_DIR/conf.d/zz-nsedit.ini"

# Apache runs as www-data (not root), so it listens on 8080 instead of 80
RUN sed -i 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf \
 && sed -i 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-available/000-default.conf \
 && chown -R www-data:www-data /var/run/apache2 /var/lock/apache2 /var/log/apache2

COPY docker/apache-nsedit.conf /etc/apache2/conf-enabled/nsedit.conf
COPY . /var/www/html/
COPY docker/config.inc.php /var/www/html/includes/config.inc.php

# nsedit's user database lives outside the document root
RUN mkdir -p /var/lib/nsedit && chown www-data:www-data /var/lib/nsedit \
 && rm -rf /var/www/html/docker /var/www/html/Dockerfile /var/www/html/docker-compose.yml /var/www/html/.env.example \
           /var/www/html/jquery-ui/tests /var/www/html/jquery-ui/demos
VOLUME /var/lib/nsedit

USER www-data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD php -r 'exit(@file_get_contents("http://127.0.0.1:8080/index.php") === false ? 1 : 0);'
