MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:

include Makefile.vars.mk

.PHONY: all
all: help

.PHONY: help
help: ## Show this help
	@grep -E -h '\s##\s' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = "(: ).*?## "}; {gsub(/\\:/,":", $$1)}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: lint_adoc
lint_adoc: ## Lint documentation
	$(VALE_CMD) $(VALE_ARGS)

.PHONY: docs-serve
docs-serve: ## Preview the documentation
	$(ANTORA_PREVIEW_CMD)
