# Test WordPress: official image (latest stable WordPress, PHP 8.5, Apache)
# plus Xdebug, Redis extension, object cache drop-in, WP-CLI and Mailpit's sendmail.
# Kept apart from the image of the development environment on purpose: the test
# environment must not depend on it.
FROM wordpress:php8.5-apache

LABEL org.opencontainers.image.source=https://github.com/saijsaij/wp-test-env

# Xdebug stays inactive unless XDEBUG_MODE enables it (bin/up defaults it to "off").
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends $PHPIZE_DEPS; \
    pecl install xdebug redis < /dev/null; \
    docker-php-ext-enable xdebug redis; \
    apt-get purge -y --auto-remove $PHPIZE_DEPS; \
    rm -rf /var/lib/apt/lists/* /tmp/pear; \
    php -m | grep -qx 'xdebug' ; \
    php -m | grep -qx 'redis'

COPY php/test.ini "$PHP_INI_DIR/conf.d/zz-test.ini"
COPY apache/zz-test.conf /etc/apache2/conf-enabled/zz-test.conf

# Object cache drop-in of the Redis Object Cache plugin (pinned, with checksum); the
# entrypoint copies it into wp-content when WP_OBJECT_CACHE is set. It uses the
# Redis extension above and needs no other file of the plugin.
ARG REDIS_CACHE_VERSION=3.0.0
ARG REDIS_CACHE_SHA256=7a03342d3defbe94cac8d0470b42dc1a1c34331b19c47205df20ceccd3c8f54a
ADD --checksum=sha256:${REDIS_CACHE_SHA256} https://downloads.wordpress.org/plugin/redis-cache.${REDIS_CACHE_VERSION}.zip /tmp/redis-cache.zip
RUN set -eux; \
    mkdir -p /usr/src/wp-test-env; \
    php -r '$zip = new ZipArchive(); if ($zip->open("/tmp/redis-cache.zip") !== true) { exit(1); } $dropIn = $zip->getFromName("redis-cache/includes/object-cache.php"); if ($dropIn === false) { exit(1); } file_put_contents("/usr/src/wp-test-env/object-cache.php", $dropIn);'; \
    rm /tmp/redis-cache.zip; \
    grep -q "Version: ${REDIS_CACHE_VERSION}" /usr/src/wp-test-env/object-cache.php

COPY --from=wordpress:cli-php8.5 /usr/local/bin/wp /usr/local/bin/wp
COPY --from=axllent/mailpit:latest /mailpit /usr/local/bin/mailpit

COPY docker-entrypoint-test.sh /usr/local/bin/docker-entrypoint-test.sh
ENTRYPOINT ["docker-entrypoint-test.sh"]
CMD ["apache2-foreground"]

HEALTHCHECK --interval=1s --timeout=5s --start-period=60s --retries=60 \
    CMD curl -fsS -o /dev/null http://localhost/readme.html || exit 1
