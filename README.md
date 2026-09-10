*This project has been created as part of the 42 curriculum by willda-s.*

# Inception

## Description

Inception is a system administration project that builds a small web
infrastructure from scratch using Docker. The goal is to understand
containerization by writing every image by hand, rather than pulling
ready-made ones.

The stack runs three services, each in its own dedicated container,
connected by a private Docker network:

- **NGINX** — the only entry point into the infrastructure, exposed on
  port 443 only, with TLSv1.2/TLSv1.3 and a self-signed certificate.
- **WordPress + php-fpm** — executes the PHP application and listens on
  port 9000. It contains no web server of its own.
- **MariaDB** — stores the WordPress database and listens on port 3306.
  It is reachable only from inside the Docker network.

Two named volumes provide persistence: one for the database, one for the
website files. Both store their data under `/home/willda-s/data` on the
host machine.

All images are built from `debian:bookworm` (the penultimate stable
Debian release) and orchestrated with Docker Compose, driven by a
Makefile at the root of the repository.

## Instructions

### Prerequisites

- A virtual machine running Debian (this project was developed on Debian 12)
- Docker Engine and the Docker Compose plugin
- The current user must belong to the `docker` group
- The domain `willda-s.42.fr` must resolve to the local machine. Add this
  line to `/etc/hosts`:

  ```
  127.0.0.1 willda-s.42.fr
  ```

### Configuration

Two things are required before the first launch, and neither is tracked
by git:

- `srcs/.env` — non-sensitive environment variables (domain name,
  database name, usernames)
- `secrets/` — one file per password:
  `db_password.txt`, `db_root_password.txt`,
  `wp_admin_password.txt`, `wp_user_password.txt`

See `DEV_DOC.md` for the exact contents expected.

### Running

```
make          # create the data directories, build the images, start the stack
make down     # stop and remove the containers
make clean    # stop the containers and remove the Docker volumes
make fclean   # same as clean, plus delete the data directories on the host
make re       # fclean, then rebuild everything
```

Once running, the site is available at `https://willda-s.42.fr` and the
admin panel at `https://willda-s.42.fr/wp-admin`. The browser will warn
about the certificate, which is expected: it is self-signed, since the
domain is local and no certificate authority can vouch for it.

## Project description

### Use of Docker and project sources

Each service has its own directory under `srcs/requirements/`, containing
a `Dockerfile`, a `conf/` directory for configuration files, and a
`tools/` directory for the entrypoint script. Nothing is pulled from
Docker Hub except the Debian base image, which the subject explicitly
allows.

The central design constraint is that **a container is a process, not a
machine**. There is no init system inside a container, which drives three
recurring decisions across all three services:

- Every entrypoint ends with `exec`, so the daemon replaces the shell and
  becomes PID 1. Without it, `SIGTERM` would reach the shell, which
  ignores it, and Docker would kill the process after the timeout —
  risking data corruption for MariaDB.
- Runtime directories that systemd would normally create (`/run/mysqld`,
  `/run/php`) are created explicitly by the entrypoint at every start,
  since `/run` is wiped on each boot.
- Each entrypoint is idempotent: it detects whether initialization has
  already happened (`/var/lib/mysql/mysql` for MariaDB,
  `wp-config.php` for WordPress) and skips it if so. This is what makes
  the volumes meaningful — data survives container recreation.

Services address each other by service name (`mariadb`, `wordpress`),
resolved by Docker's embedded DNS on the custom bridge network. This is
also why MariaDB binds to `0.0.0.0` instead of Debian's default
`127.0.0.1`, and why the WordPress database user is declared as
`'wpuser'@'%'`: from MariaDB's point of view, the WordPress container is
a remote host.

### Virtual Machines vs Docker

Virtual machines abstract hardware using a hypervisor, requiring each instance to run its own complete guest operating system kernel. This makes them heavier, slower to boot, and resource-intensive, but provides strong isolation: each guest is confined by the hypervisor. In contrast, Docker containers virtualize at the operating system level, sharing the host Linux kernel to run applications as lightweight, isolated processes that start in seconds with a minimal disk footprint.

That shared kernel is the core trade-off. Containers are isolated by kernel features (namespaces and cgroups) rather than by a hypervisor, so a kernel vulnerability or a container escape can expose the host — a risk a VM does not carry in the same way. Containers trade isolation strength for density and speed.

This project uses both technologies in tandem. A virtual machine acts as the isolated host environment, keeping the setup off the main machine, while Docker containers running inside that VM manage individual services — NGINX, WordPress and MariaDB — independently.

### Secrets vs Environment Variables

Environment variables store parameters in memory and pass them via CLI or compose files, while Docker secrets mount sensitive data as read-only files inside /run/secrets/. Environment variables easily leak through `docker inspect` commands, process inspection via `/proc/<pid>/environ`, crash logs, and child process inheritance. Docker secrets avoid these vulnerabilities by isolating access to the filesystem layer at runtime.

To keep the application secure, environment variables are strictly limited to non-sensitive runtime configurations like database names or domain names. Sensitive credentials like passwords are managed through Docker secrets and loaded from disk, ensuring secrets are never committed to Git repositories or baked permanently into Dockerfile build layers.

### Docker Network vs Host Network

A custom bridge network gives every container its own network namespace and private IP address, and enables service discovery by name through Docker's embedded DNS resolver at 127.0.0.11. The resolver exists on the default bridge network too, but it does not resolve container names there — a legacy of the deprecated `--link` mechanism, which the subject forbids. On the default bridge, containers can only reach each other by IP, and those addresses change on every recreation. A custom bridge resolves service names dynamically, which is what makes `fastcgi_pass wordpress:9000`; possible without hardcoding an address.

Host network mode removes network boundaries entirely: containers share the host's network interface directly, losing both isolation and name-based discovery, and exposing every listening port to the host — with the port collisions that follow.

Using a custom bridge guarantees that NGINX remains the sole exposed entry point on port 443. WordPress and MariaDB communicate over the internal network without exposing FastCGI or database ports to the host interface.

### Docker Volumes vs Bind Mounts

Docker volumes are fully managed by the Docker Engine within isolated internal storage paths, whereas bind mounts map a container folder directly to an explicit path on the host filesystem. This project uses a named volume configured with `driver_opts` (type: none, o: bind), combining Docker's managed volume lifecycle with explicit host location mapping under /home/willda-s/data/....

Because the storage is registered as a named volume backed by a host location, executing docker compose down -v safely unregisters the volume metadata from Docker's internal system. The physical database files and media uploads remain completely safe and intact on the host directory.

## Resources

### Documentation

- [Docker explaination](https://youtu.be/DQdB7wFEygo)
- [Docker documentation](https://docs.docker.com/)
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/)
- [PHP-FPM configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [NGINX documentation](https://nginx.org/en/docs/)
- [WP-CLI commands](https://developer.wordpress.org/cli/commands/)

### AI usage

I used AI as a debugging and explanation partner throughout this
project. Concretely:

- **Understanding container fundamentals** — why PID 1 matters, why
  `exec` is required for correct signal handling, why daemonizing a
  process inside a container breaks it.
- **Diagnosing infrastructure issues** — a `ufw` `FORWARD DROP` policy on
  the host that silently blocked TCP forwarding to the VM (ICMP and UDP
  passed, TCP did not), and MariaDB's `--skip-grant-tables` restriction
  during `--bootstrap`, which caused privilege statements to fail
  silently.
- **Reviewing my Dockerfiles and entrypoint scripts** — catching mistakes
  such as a `RUN nginx -g 'daemon off;'` that would have hung the build,
  and a mistyped variable in the bootstrap SQL.
