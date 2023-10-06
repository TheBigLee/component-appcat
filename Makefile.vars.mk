COMPONENT_NAME ?= appcat

git_dir     ?= $(shell git rev-parse --git-common-dir)
root_volume ?= -v "$${PWD}:/$(COMPONENT_NAME)"

ifneq "$(git_dir)" ".git"
	antora_git_volume ?= -v "$(git_dir):/preview/antora/.git:ro"
else
	antora_git_volume ?= -v "${PWD}/.git:/preview/antora/.git:ro"
endif

ifneq "$(shell which docker 2>/dev/null)" ""
	DOCKER_CMD    ?= $(shell which docker)
	DOCKER_USERNS ?= ""
else
	DOCKER_CMD    ?= podman
	DOCKER_USERNS ?= keep-id
endif
DOCKER_ARGS ?= run --rm -u "$$(id -u):$$(id -g)" --userns=$(DOCKER_USERNS) -w /$(COMPONENT_NAME) -e HOME="/$(COMPONENT_NAME)"

VALE_CMD  ?= $(DOCKER_CMD) $(DOCKER_ARGS) $(root_volume) --volume "$${PWD}"/docs/modules:/pages ghcr.io/vshn/vale:2.15.5
VALE_ARGS ?= --minAlertLevel=error --config=/pages/ROOT/pages/.vale.ini /pages

ANTORA_PREVIEW_CMD ?= $(DOCKER_CMD) run --rm --publish 35729:35729 --publish 2020:2020 $(antora_git_volume) --volume "${PWD}/docs":/preview/antora/docs ghcr.io/vshn/antora-preview:3.1.2.3 --style=syn --antora=docs
