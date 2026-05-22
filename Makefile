.PHONY: up down test logs

up:
	docker compose up --build -d

down:
	docker compose down

logs:
	docker compose logs -f

test:
	@echo "Waiting for services to be ready..."
	@sleep 2
	@bash tests/test.sh
