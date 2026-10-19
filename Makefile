SHELL := /bin/bash

SCRIPTS := $(wildcard *.sh) $(wildcard lib/*.sh) $(wildcard tools/*.sh)

.PHONY: help lint shellcheck links check install test

help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

lint: ## Valida la sintaxis de todos los scripts
	@for f in $(SCRIPTS); do \
		echo "bash -n $$f"; bash -n "$$f" || exit 1; \
	done
	@echo "sintaxis ok"

shellcheck: ## Corre shellcheck (si esta instalado)
	@command -v shellcheck >/dev/null || { echo "shellcheck no instalado"; exit 0; }
	shellcheck $(SCRIPTS)

links: ## Verifica los links relativos de la documentacion
	@./tools/check-links.sh

check: lint links ## Validaciones rapidas (sintaxis + links)

install: ## Aplica Nube en el sistema (requiere root; ver bootstrap.sh)
	sudo ./install.sh

bootstrap: ## Prepara el servidor desde cero (requiere root)
	sudo ./bootstrap.sh

test: ## Prueba de humo de un deploy (requiere app configurada)
	./test-hook.sh
