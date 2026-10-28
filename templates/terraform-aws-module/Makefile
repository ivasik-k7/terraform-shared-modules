# The same checks CI runs, for a laptop. `make` runs everything that needs no
# credentials; nothing here plans against or applies to AWS.

.DEFAULT_GOAL := check
SHELL := bash
.SHELLFLAGS := -euo pipefail -c

.PHONY: check fmt fmt-check init validate test examples lint scan v5 help

check: fmt-check validate test examples lint ## Everything CI runs, except the scanners

fmt: ## Format every .tf file
	terraform fmt -recursive

fmt-check:
	terraform fmt -check -recursive -diff

init:
	terraform init -backend=false -input=false >/dev/null

validate: init
	terraform validate

test: init ## Plan tests against a mocked provider
	terraform test

examples:
	@for d in examples/*/; do \
	  echo "== $$d"; \
	  terraform -chdir="$$d" init -backend=false -input=false >/dev/null; \
	  terraform -chdir="$$d" validate; \
	done

lint: ## tflint (if installed) and the repository's linters, with their self-tests
	@if command -v tflint >/dev/null; then tflint --init && tflint --recursive; else echo "tflint not installed: skipped (CI runs it)"; fi
	python3 tests/lint_validations.py --self-test
	python3 tests/lint_validations.py .
	python3 tests/check_consistency.py --self-test
	python3 tests/check_consistency.py .

scan: ## trivy config scan (if installed)
	@if command -v trivy >/dev/null; then trivy config --severity HIGH,CRITICAL --exit-code 1 .; else echo "trivy not installed: skipped (CI runs it)"; fi

v5: ## The provider's v5 end, in a throwaway copy
	@work="$$(mktemp -d)"; \
	cp -r . "$$work/"; \
	cd "$$work" && rm -rf .terraform .terraform.lock.hcl; \
	sed -i 's/version = ">= 5.90.0, < 7.0.0"/version = "= 5.100.0"/' versions.tf; \
	terraform init -backend=false -input=false >/dev/null && terraform validate && terraform test; \
	echo "copy left in $$work"

help: ## This list
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | column -t -s $$'\t'
