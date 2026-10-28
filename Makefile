# The checks CI runs, for a laptop. Nothing here plans against or applies to
# AWS. Module targets take MODULE=<name>; without it they use the modules
# changed in the working tree (or since BASE=<ref>).
#
#   make check                    changed modules + repo-wide gates
#   make check MODULE=aurora      one module
#   make check BASE=origin/main   what a pull request would run

.DEFAULT_GOAL := help
SHELL := bash
.SHELLFLAGS := -euo pipefail -c

MODULE ?=
BASE ?=
TARGETS = $(or $(MODULE),$(shell scripts/tf-modules.sh changed $(BASE)))

.PHONY: help check repo module fmt fmt-check governance governance-self-test baseline \
        actionlint shellcheck precommit hooks modules changed examples scan new-module release-check

help: ## This list
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | column -t -s $$'\t'

check: repo module ## Repo-wide gates, then every target module

repo: fmt-check governance-self-test governance actionlint shellcheck ## Gates that cover the whole repository

module: ## fmt, validate, test, examples, linters, tflint/trivy if installed
	@if [ -z "$(strip $(TARGETS))" ]; then echo "no changed modules; pass MODULE=<name>"; else scripts/tf-modules.sh check $(TARGETS); fi

fmt: ## Format every .tf file
	terraform fmt -recursive

fmt-check:
	terraform fmt -check -recursive -diff

governance: ## Module conventions against the ratcheted baseline
	python3 scripts/check_governance.py

governance-self-test:
	python3 scripts/check_governance.py --self-test >/dev/null

baseline: ## Re-record governance debt (review the diff: it should only shrink)
	python3 scripts/check_governance.py --write-baseline

actionlint:
	@if command -v actionlint >/dev/null; then actionlint; else echo "actionlint not installed: skipped (CI runs it)"; fi

shellcheck:
	@if command -v shellcheck >/dev/null; then shellcheck .githooks/pre-commit scripts/*.sh .claude/hooks/*.sh; else echo "shellcheck not installed: skipped (CI runs it)"; fi

precommit: ## pre-commit hooks on staged files (core.hooksPath blocks `pre-commit install`)
	pre-commit run

hooks: ## Use the repo's git hooks in this clone
	git config core.hooksPath .githooks
	@echo "hooks: $$(git config --get core.hooksPath)"

modules: ## List module directories
	@scripts/tf-modules.sh list

changed: ## Modules changed in the working tree (or since BASE)
	@scripts/tf-modules.sh changed $(BASE)

examples: ## Example directories that call MODULE
	@scripts/tf-modules.sh examples $(MODULE)

scan: ## trivy config scan of the target modules (if installed)
	@if command -v trivy >/dev/null; then for m in $(TARGETS); do trivy config --severity HIGH,CRITICAL --exit-code 1 --ignorefile .trivyignore modules/$$m; done; else echo "trivy not installed: skipped (CI runs it)"; fi

new-module: ## Scaffold modules/NAME from templates/terraform-aws-module
	scripts/new-module.sh $(NAME)

release-check: ## Pre-tag checks: make release-check MODULE=aurora VERSION=2.0.0
	scripts/tf-modules.sh release-check $(MODULE) $(VERSION)
