# syntax=docker/dockerfile:1
# updatool preset — PHP (Composer)
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN --mount=type=cache,target=/tmp/composer-cache \
    COMPOSER_CACHE_DIR=/tmp/composer-cache composer install --no-dev --no-scripts --prefer-dist

FROM php:8.3-apache
COPY --from=vendor /app/vendor /var/www/html/vendor
COPY . /var/www/html
EXPOSE 80
