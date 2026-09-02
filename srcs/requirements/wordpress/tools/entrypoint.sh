#!/bin/sh
mkdir -p /run/php
chown www-data:www-data /run/php

if [ ! -f /var/www/html/wp-config.php ]; then
	DB_PASS=$(cat /run/secrets/db_password)
	WP_ADMIN_PASS=$(cat /run/secrets/wp_admin_password)
	WP_USER_PASS=$(cat /run/secrets/wp_user_password)
	wp core download --allow-root
	wp config create --dbname=${MYSQL_DATABASE} --dbuser=${MYSQL_USER} \
	    --dbpass=${DB_PASS} --dbhost=mariadb --allow-root
	wp core install --url=${DOMAIN_NAME} --title=Inception \
	     --admin_user=${WP_ADMIN_USER} --admin_password=${WP_ADMIN_PASS} \
	     --admin_email=${WP_ADMIN_EMAIL} --allow-root
	wp user create ${WP_USER} ${WP_USER_EMAIL} --role=author \
	     --user_pass=${WP_USER_PASS} --allow-root
fi

exec php-fpm8.2 -F
