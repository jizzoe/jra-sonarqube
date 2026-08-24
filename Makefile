# SonarQube ECS singleton — lifecycle orchestration (Slice 08)
SHELL := /bin/bash

.PHONY: start cold-stop status health logs

start:
	./scripts/start.sh

cold-stop:
	./scripts/cold-stop.sh

status:
	./scripts/status.sh status

health:
	./scripts/status.sh health

logs:
	./scripts/status.sh logs $(PREFIX)
