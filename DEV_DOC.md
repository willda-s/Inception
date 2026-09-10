# Developer Documentation

## Setting up from scratch

### Prerequisites

- Virtualization software (VirtualBox, or QEMU/KVM with libvirt)
- A Debian 12 netinst ISO
- During the Debian installation, select only `SSH server` and
  `standard system utilities` — no desktop environment
- Create the user as `willda-s`: the compose file and the Makefile
  reference `/home/willda-s/data`, so the username must match

### On the VM

Install the required packages:

- Docker Engine and the Docker Compose plugin (from Docker's official
  repository, not Debian's `docker.io`, which is too old for Compose v2)
- `git` and `make`
- Add your user to the `docker` group, then reconnect:
  `sudo usermod -aG docker $USER`

### Clone the repository

    git clone <repository-url> inception
    cd inception

### Create the untracked configuration

Two things are excluded from git by `.gitignore` and must be recreated
by hand — they hold credentials and must never be committed:

`srcs/.env` — non-sensitive variables:

    DOMAIN_NAME=willda-s.42.fr
    MYSQL_DATABASE=wordpress
    MYSQL_USER=wpuser
    WP_ADMIN_USER=leroi
    WP_ADMIN_EMAIL=willda-s@student.42lyon.fr
    WP_USER=user
    WP_USER_EMAIL=user@gmail.com

`secrets/` — one password per file:

    mkdir -p secrets
    openssl rand -hex 16 > secrets/db_password.txt
    openssl rand -hex 16 > secrets/db_root_password.txt
    openssl rand -hex 16 > secrets/wp_admin_password.txt
    openssl rand -hex 16 > secrets/wp_user_password.txt

Keep a note of `wp_admin_password.txt`: it is the password for the
WordPress admin panel.

### Point the domain to the local machine

The domain does not exist publicly, so it must be resolved locally to
the machine where NGINX listens:

    echo "127.0.0.1 willda-s.42.fr" | sudo tee -a /etc/hosts

### Launch

    make

## Building and launching

The Makefile at the root drives everything. It never calls Docker
directly on a container: every target goes through Docker Compose,
which reads `srcs/docker-compose.yml`.

    make          Create the data directories, build the images, start the stack
    make down     Stop and remove the containers
    make clean    Same as down, plus remove the Docker volumes
    make fclean   Same as clean, plus delete the data directories on the host
    make re       fclean, then all

### `make`

Two steps, in order:

1. `mkdir -p /home/willda-s/data/{mariadb,wordpress}` — the volumes are
   declared with `driver_opts` pointing at these paths. Docker refuses
   to mount a volume whose `device` does not exist, so the directories
   must be created first.
2. `docker compose up -d --build` — `--build` forces the images to be
   rebuilt. Without it, Compose reuses existing images and any change
   to a Dockerfile or an entrypoint is silently ignored.

### `clean` versus `fclean`

This distinction matters because of how the volumes are configured.

`make clean` runs `docker compose down -v`, which unregisters the
volumes from Docker. But the actual files stay on the host: the volumes
use `driver_opts` with `o: bind`, so their storage lives in
`/home/willda-s/data/`, outside Docker's own volume directory. A
standard Docker volume would have its data deleted here.

`make fclean` therefore deletes those directories explicitly. It is the
only way to start from a genuinely empty state — which matters because
both entrypoints are idempotent and skip initialization when they find
existing data.

## Managing containers and volumes

### Checking state

    docker compose ps                  # status of all three services
    docker compose logs <service>      # output of one service
    docker compose logs -f <service>   # follow the output live

`docker compose ps` shows whether a container is `Up` or has exited.
Note that a container can briefly report `Up` even after its process
has crashed, so always read the logs after starting the stack rather
than trusting the status alone.

### Inspecting a running container

    docker exec <container> <command>        # run a command inside
    docker exec -it <container> bash         # open an interactive shell
    docker exec <container> ps -ef           # list processes

`ps -ef` is the way to verify that the daemon is PID 1. If a shell
appears as PID 1 with the service as a child, the entrypoint is missing
its `exec` and the container will not shut down cleanly.

### Connecting to the database

    docker exec -it mariadb mariadb -u root -p

The root password is in `secrets/db_root_password.txt`. Useful queries:

    SHOW DATABASES;
    SELECT user, host FROM mysql.user;
    USE wordpress; SHOW TABLES;

Connecting as `wpuser` this way will fail with `Access denied`. That is
expected, not a bug: `docker exec` connects through the Unix socket, so
MariaDB sees `localhost`, while the user is declared as `'wpuser'@'%'`
for network connections from the WordPress container.

### Inspecting volumes

    docker volume ls                   # list volumes
    docker volume inspect srcs_db_data # show its driver options and device

    docker inspect mariadb --format '{{json .Mounts}}'

The last command lists what a container actually has mounted. An empty
result means the service has no `volumes:` key in the compose file —
its data lives in the container layer and will be lost on removal.

### Testing the stack

    curl -k -o /dev/null -w "%{http_code}\n" -s https://willda-s.42.fr

`-k` accepts the self-signed certificate; `-w "%{http_code}"` prints
only the status code. A `200` means the whole chain works. A `302`
usually means WordPress is redirecting to `/wp-admin/install.php`,
which indicates the database is empty while `wp-config.php` exists.

    time docker stop mariadb

Should complete in under a second. Exactly ten seconds is Docker's kill
timeout, meaning `SIGTERM` never reached the daemon.

## Where data lives and how it persists

### Physical location

Both volumes store their data under `/home/willda-s/data`:

    /home/willda-s/data/mariadb     the database files
    /home/willda-s/data/wordpress   the WordPress site files

This is not a bind mount. Each volume is declared as a named volume
whose local driver is given explicit mount options:

    db_data:
      driver: local
      driver_opts:
        type: none
        o: bind
        device: /home/willda-s/data/mariadb

Docker still manages the volume — it appears in `docker volume ls` and
is referenced by name — but its backing storage is redirected to a
chosen host path, which is what the subject requires.

### What survives what

    docker compose down       Removes the containers and the network.
                              Images and volumes are untouched.

    docker compose down -v    Also unregisters the volumes from Docker.
                              The files under /home/willda-s/data remain,
                              because they live outside Docker's storage.

    make fclean               Deletes those directories as well.

A container is an instance of an image, with a writable layer on top.
`down` destroys the instance; the image itself is unaffected.

### Why nothing is reinstalled on restart

Persistent volumes alone are not enough: the entrypoints run on every
container start, so they must detect that initialization has already
happened and skip it. Both are idempotent, each guarded by a witness
file:

    MariaDB     /var/lib/mysql/mysql        created by mariadb-install-db
    WordPress   /var/www/html/wp-config.php created by wp config create

If the witness is present, the setup block is skipped and the service
starts directly.

One consequence is worth knowing. The two witnesses live in two
different volumes, and nothing guarantees they stay consistent. If the
database volume is emptied while the WordPress one is not,
`wp-config.php` still exists — so the installation is skipped — but the
tables are gone, and WordPress redirects to `/wp-admin/install.php`.
Recovering from that means clearing both volumes together, which is
what `make fclean` does.
