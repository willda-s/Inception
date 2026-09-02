FROM debian:bookworm
RUN apt-get update && apt-get install -y php8.2-fpm php8.2-mysql php8.2-cli mariadb-client curl && rm -rf /var/lib/apt/lists/*
RUN curl -L -o /usr/local/bin/wp https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar \
    && chmod +x /usr/local/bin/wp
WORKDIR /var/www/html
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
