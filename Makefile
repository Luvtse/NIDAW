.PHONY: setup dev test deploy clean destroy-infra

setup:
	chmod +x scripts/*.sh
	./scripts/setup.sh

dev:
	docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml up -d

test:
	cd services/api && go test ./... -race -cover
	cd apps/consumer_app && flutter test
	cd apps/driver_app && flutter test

deploy:
	./scripts/deploy.sh

clean:
	docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml down

# Destructive infrastructure teardown is intentionally separate from routine cleanup.
destroy-infra:
	terraform -chdir=infrastructure/environments/dev destroy