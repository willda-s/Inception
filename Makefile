all:
	mkdir -p /home/willda-s/data/mariadb /home/willda-s/data/wordpress
	docker compose -f srcs/docker-compose.yml up -d --build

down:
	docker compose -f srcs/docker-compose.yml down

clean:
	docker compose -f srcs/docker-compose.yml down -v

fclean: clean
	sudo rm -rf /home/willda-s/data/mariadb /home/willda-s/data/wordpress

re: clean all

.PHONY: all down clean fclean re
