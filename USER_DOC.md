# User Documentation

## What the stack provides

Running this project gives you a self-hosted WordPress site, served over
HTTPS at `https://willda-s.42.fr`. The site runs entirely on the local
machine: the domain is resolved locally and is not reachable from the
internet.

Behind the scenes it runs three isolated services — a web server
(NGINX), the WordPress application (php-fpm), and a database (MariaDB) —
but as a user you only interact with the website itself.

Two accounts are created automatically on first launch:

- an **administrator**, who can install themes and plugins, publish and
  edit any content, and manage users
- an **author**, who can write and publish their own posts but cannot
  change the site configuration

Content and site settings are stored persistently, so they survive
restarts of the stack.

## Starting and stopping

All commands are run from the root of the project.

### Daily use

    make          Start the site (builds the images on first run)
    make down     Stop the site

`make down` stops and removes the containers but keeps all your data.
Running `make` again brings the site back exactly as you left it: your
posts, users, settings and uploaded media are all preserved.

### Resetting

Two commands go further, and both cause data loss:

    make clean    Stops the site and removes the Docker volumes
    make fclean   Same, and deletes the data files on the host

Use these only when you want to start over from an empty site. After
`make fclean`, the next `make` reinstalls WordPress from scratch: all
content, users and settings are gone.

For everyday use, `make down` is the command you want.

## Accessing the site and the admin panel

- Website: `https://willda-s.42.fr`
- Admin panel: `https://willda-s.42.fr/wp-admin`

### Prerequisite

The domain is local and does not exist on the internet, so the machine
must be told where to find it. This line is required in `/etc/hosts`:

    127.0.0.1 willda-s.42.fr

Without it, the browser will report that the address cannot be found.

### About the security warning

On first visit, your browser will warn that the connection is not
private, and you will need to click through an "Advanced" link to
continue. This is expected.

The certificate is self-signed: a certificate authority can only vouch
for a domain whose ownership can be verified, and `willda-s.42.fr` does
not exist publicly. The connection is still encrypted with TLS 1.2 or
1.3 — it simply is not vouched for by a third party.

### Logging in

Use the administrator username defined in `srcs/.env` and the password
stored in `secrets/wp_admin_password.txt`. See the next section.

## Credentials

Credentials are split across two locations, and neither is tracked by
git.

### `srcs/.env` — names

Usernames and the database name:

    MYSQL_DATABASE, MYSQL_USER
    WP_ADMIN_USER, WP_ADMIN_EMAIL
    WP_USER, WP_USER_EMAIL

### `secrets/` — passwords

One password per file:

    secrets/db_password.txt          WordPress's database user
    secrets/db_root_password.txt     MariaDB root account
    secrets/wp_admin_password.txt    WordPress administrator
    secrets/wp_user_password.txt     WordPress author account

To read one:

    cat secrets/wp_admin_password.txt

These files are mounted read-only inside the containers at
`/run/secrets/`, so the passwords never appear in the environment, in
`docker inspect`, or in the image itself.

### Changing a password

Editing a file in `secrets/` does not change an existing password. The
entrypoints read these files only once, during the initial setup; after
that the password is stored in the database, which is the authority.

To change a WordPress password, use the admin panel:
**Users → Edit → Set New Password**.

To change the database passwords, the stack must be reinitialized:

    make fclean
    # edit the files in secrets/
    make

This deletes all existing content.

## Checking that the services are running

### Quick check

Open `https://willda-s.42.fr` in a browser. If the site loads, the
whole chain works: NGINX, php-fpm and MariaDB are all responding.

From the command line:

    curl -k -o /dev/null -w "%{http_code}\n" -s https://willda-s.42.fr

A `200` means everything is up. `-k` accepts the self-signed
certificate.

### Container status

    docker compose -f srcs/docker-compose.yml ps

All three services — `mariadb`, `wordpress` and `nginx` — should show
`Up`. Only `nginx` should list a port, `0.0.0.0:443->443/tcp`: it is the
sole entry point into the infrastructure.

### If something is wrong

    docker compose -f srcs/docker-compose.yml logs mariadb
    docker compose -f srcs/docker-compose.yml logs wordpress
    docker compose -f srcs/docker-compose.yml logs nginx

Read them bottom-up: the last lines usually name the problem.

Two common cases:

- **The site is unreachable** — check that `127.0.0.1 willda-s.42.fr`
  is present in `/etc/hosts`.
- **You get a `302` to `/wp-admin/install.php`** — WordPress considers
  itself uninstalled, which usually means the database volume was
  cleared while the site files were kept. `make fclean` then `make`
  resets both together.
