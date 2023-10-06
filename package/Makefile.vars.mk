# Commodore takes the root dir name as the package name
PACKAGE_NAME ?= $(shell basename ${PWD} | sed s/package-//)

git_dir         ?= $(shell git rev-parse --git-common-dir)
root_volume     ?= -v "$${PWD}:/$(PACKAGE_NAME)"
commodore_args  ?= tests/$(instance).yml

ifneq "$(git_dir)" ".git"
	git_volume        ?= -v "$(git_dir):$(git_dir):ro"
	antora_git_volume ?= -v "$(git_dir):/preview/antora/.git:ro"
else
	git_volume        ?=
	antora_git_volume ?= -v "${PWD}/.git:/preview/antora/.git:ro"
endif

ifneq "$(shell which docker 2>/dev/null)" ""
	DOCKER_CMD    ?= $(shell which docker)
	DOCKER_USERNS ?= ""
else
	DOCKER_CMD    ?= podman
	DOCKER_USERNS ?= keep-id
endif
DOCKER_ARGS ?= run --rm -u "$$(id -u):$$(id -g)" --userns=$(DOCKER_USERNS) -w /$(PACKAGE_NAME) -e HOME="/$(PACKAGE_NAME)"

YAMLLINT_ARGS   ?= --no-warnings
YAMLLINT_CONFIG ?= .yamllint.yml
YAMLLINT_IMAGE  ?= docker.io/cytopia/yamllint:latest
YAMLLINT_DOCKER ?= $(DOCKER_CMD) $(DOCKER_ARGS) $(root_volume) $(YAMLLINT_IMAGE)

VALE_CMD  ?= $(DOCKER_CMD) $(DOCKER_ARGS) $(root_volume) --volume "$${PWD}"/docs/modules:/pages ghcr.io/vshn/vale:2.15.5
VALE_ARGS ?= --minAlertLevel=error --config=/pages/ROOT/pages/.vale.ini /pages

ANTORA_PREVIEW_CMD ?= $(DOCKER_CMD) run --rm --publish 35729:35729 --publish 2020:2020 $(antora_git_volume) --volume "${PWD}/docs":/preview/antora/docs ghcr.io/vshn/antora-preview:3.1.2.3 --style=syn --antora=docs


COMMODORE_CMD  ?= $(DOCKER_CMD) $(DOCKER_ARGS) $(root_volume) docker.io/projectsyn/commodore:latest
COMPILE_CMD    ?= $(COMMODORE_CMD) package compile . $(commodore_args)

instance ?= defaults
test_instances = tests/defaults.yml
