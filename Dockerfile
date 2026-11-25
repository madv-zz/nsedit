# nsedit on PHP 8.4+ (Apache + mod_php). Choose the PHP version with --build-arg PHP_VERSION=8.5
ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-apache

# Production php.ini; errors go to the container log, not to the browser (that would break jtable's JSON)
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
 && printf '%s\n' 'error_reporting = E_ALL' 'display_errors = Off' 'log_errors = On' 'error_log = /dev/stderr' \
      'expose_php = Off' 'session.use_strict_mode = 1' > "$PHP_INI_DIR/conf.d/zz-nsedit.ini"

COPY docker/apache-nsedit.conf /etc/apache2/conf-enabled/nsedit.conf
COPY . /var/www/html/
COPY docker/config.inc.php /var/www/html/includes/config.inc.php

# nsedit's user database lives outside the document root
RUN mkdir -p /var/lib/nsedit && chown www-data:www-data /var/lib/nsedit \
 && rm -rf /var/www/html/screenshots /var/www/html/docker /var/www/html/tests /var/www/html/Dockerfile /var/www/html/docker-compose.yml /var/www/html/.env.example \
           /var/www/html/jquery-ui/tests /var/www/html/jquery-ui/demos
VOLUME /var/lib/nsedit
