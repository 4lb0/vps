SHELL := /bin/bash

SCRIPTS := $(wildcard *.sh) install.sh lib.sh $(wildcard lib/*.sh) $(wildcard tools/*.sh)

.PHONY: help lint shellcheck install test

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

install: ## Instala Nube en el sistema (requiere root)
	sudo ./install.sh

test: ## Prueba de humo de un deploy (requiere app configurada)
	./test-hook.sh
