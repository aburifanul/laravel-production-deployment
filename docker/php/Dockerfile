FROM docker.io/dunglas/frankenphp:php8.4-alpine

RUN install-php-extensions \
    pdo_mysql \
    mbstring \
    exif \
    pcntl \
    bcmath \
    gd \
    zip \
    intl \
    opcache \
    redis

COPY --from=docker.io/library/composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

COPY . .

ENV COMPOSER_ALLOW_SUPERUSER=1

RUN rm -f \
    bootstrap/cache/*.php

RUN composer install \
    --optimize-autoloader \
    --no-dev \
    --no-interaction

RUN mkdir -p \
    storage/logs \
    storage/framework/cache \
    storage/framework/sessions \
    storage/framework/views \
    bootstrap/cache \
    && chown -R www-data:www-data /app \
    && chmod -R 775 storage bootstrap/cache

COPY docker/php/Caddyfile /etc/caddy/Caddyfile

COPY docker/php/php.ini \
    /usr/local/etc/php/conf.d/99-custom.ini

EXPOSE 80 443 443/udp

CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]