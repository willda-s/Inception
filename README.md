This project has been created as part of the 42 curriculum by willda-s.

Inception
Description

Inception is a system administration project that builds a small web infrastructure from scratch using Docker. The goal is to understand containerization by writing every image by hand, rather than pulling ready-made ones.

The stack runs three services, each in its own dedicated container, connected by a private Docker network:

NGINX — the only entry point into the infrastructure, exposed on port 443 only, with TLSv1.2/TLSv1.3 and a self-signed certificate.
WordPress + php-fpm — executes the PHP application and listens on port 9000. It contains no web server of its own.
MariaDB — stores the WordPress database and listens on port 3306. It is reachable only from inside the Docker network.

Two named volumes provide persistence: one for the database, one for the website files. Both store their data under /home/willda-s/data on the host machine.

All images are built from debian:bookworm (the penultimate stable Debian release) and orchestrated with Docker Compose, driven by a Makefile at the root of the repository.

Instructions
Prerequisites
A virtual machine running Debian (this project was developed on Debian 12)
Docker Engine and the Docker Compose plugin
The current user must belong to the docker group
The domain willda-s.42.fr must resolve to the local machine. Add this line to /etc/hosts:
  127.0.0.1 willda-s.42.fr
Configuration

Two things are required before the first launch, and neither is tracked by git:

srcs/.env — non-sensitive environment variables (domain name, database name, usernames)
secrets/ — one file per password: db_password.txt, db_root_password.txt, wp_admin_password.txt, wp_user_password.txt

See DEV_DOC.md for the exact contents expected.

Running
make          # create the data directories, build the images, start the stack
make down     # stop and remove the containers
make clean    # stop the containers and remove the Docker volumes
make fclean   # same as clean, plus delete the data directories on the host
make re       # clean, then rebuild everything

Once running, the site is available at https://willda-s.42.fr and the admin panel at https://willda-s.42.fr/wp-admin. The browser will warn about the certificate, which is expected: it is self-signed, since the domain is local and no certificate authority can vouch for it.

Project description
Use of Docker and project sources

Each service has its own directory under srcs/requirements/, containing a Dockerfile, a conf/ directory for configuration files, and a tools/ directory for the entrypoint script. Nothing is pulled from Docker Hub except the Debian base image, which the subject explicitly allows.

The central design constraint is that a container is a process, not a machine. There is no init system inside a container, which drives three recurring decisions across all three services:

Every entrypoint ends with exec, so the daemon replaces the shell and becomes PID 1. Without it, SIGTERM would reach the shell, which ignores it, and Docker would kill the process after the timeout — risking data corruption for MariaDB.
Runtime directories that systemd would normally create (/run/mysqld, /run/php) are created explicitly by the entrypoint at every start, since /run is wiped on each boot.
Each entrypoint is idempotent: it detects whether initialization has already happened (/var/lib/mysql/mysql for MariaDB, wp-config.php for WordPress) and skips it if so. This is what makes the volumes meaningful — data survives container recreation.

Services address each other by service name (mariadb, wordpress), resolved by Docker's embedded DNS on the custom bridge network. This is also why MariaDB binds to 0.0.0.0 instead of Debian's default 127.0.0.1, and why the WordPress database user is declared as 'wpuser'@'%': from MariaDB's point of view, the WordPress container is a remote host.

Virtual Machines vs Docker
<!-- TODO: compare the two. Points worth covering, drawn from what you actually built: - What each one virtualizes (hardware vs the OS process space) - Whether a kernel is shared or duplicated - Consequences for boot time, disk footprint, and resource use - Consequences for isolation strength - Why this project uses BOTH: a VM to host Docker, containers for the services -->
Secrets vs Environment Variables
<!-- TODO: compare the two. Points worth covering: - Where each one is stored and how it reaches the container (environment variable vs a read-only file in /run/secrets/) - Why environment variables leak: docker inspect, /proc/<pid>/environ, crash logs, child processes - What you put in each in this project, and why that split - Why the subject forbids passwords in Dockerfiles and in the repo -->
Docker Network vs Host Network
<!-- TODO: compare the two. Points worth covering: - What network namespace each container gets in either mode - How name resolution works on a custom bridge network - Why host mode would defeat the "NGINX is the only entry point" requirement - Port conflicts and isolation -->
Docker Volumes vs Bind Mounts
<!-- TODO: compare the two. Points worth covering: - Who owns and manages the storage in each case - How each is declared and referenced - What this project uses: a named volume with driver_opts (type: none, o: bind, device: /home/willda-s/data/...) and why that still counts as a named volume - What `docker compose down -v` removes, and what it leaves behind on the host -->
Resources
Documentation
Docker documentation
Dockerfile best practices
Docker Compose file reference
Docker secrets in Compose
MariaDB Knowledge Base
PHP-FPM configuration
NGINX documentation
WP-CLI commands
AI usage

I used Claude as a debugging and explanation partner throughout this project. Concretely:

Understanding container fundamentals — why PID 1 matters, why exec is required for correct signal handling, why daemonizing a process inside a container breaks it.
Diagnosing infrastructure issues — a ufw FORWARD DROP policy on the host that silently blocked TCP forwarding to the VM (ICMP and UDP passed, TCP did not), and MariaDB's --skip-grant-tables restriction during --bootstrap, which caused privilege statements to fail silently.
Reviewing my Dockerfiles and entrypoint scripts — catching mistakes such as a RUN nginx -g 'daemon off;' that would have hung the build, and a mistyped variable in the bootstrap SQL.

All configuration files, Dockerfiles, and entrypoint scripts were written by me. AI was used to explain concepts and identify errors, not to generate code I could not explain.
