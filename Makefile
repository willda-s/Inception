all:
	mkdir -p /home/willda-s/data/mariadb /home/willda-s/data/wordpress
	docker compose -f srcs/docker-compose.yml up -d --build

down:
	docker compose -f srcs/docker-compose.yml down

clean:
	docker compose -f srcs/docker-compose.yml down -v

re: clean all
