# macOS Processor Monitor — every build, test and quality command goes through here.
#
# Plain `swift test` does not work with only the Command Line Tools installed: the default
# swiftbuild engine does not load the TestingMacros plugin, so SWIFT_FLAGS adds its path.
# Keep SWIFT_FLAGS identical for build and test invocations, or SwiftPM rebuilds everything.

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

SWIFT_BIN_DIR := $(shell dirname "$$(xcrun --find swift)")
TESTING_PLUGINS := $(SWIFT_BIN_DIR)/../lib/swift/host/plugins/testing
SWIFT_FLAGS := -Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS)
TEST_FLAGS := --disable-xctest $(SWIFT_FLAGS)
STRICT_FLAGS := -Xswiftc -warnings-as-errors

TOOLS := Tools
PMTOOLS = $(shell swift build --package-path $(TOOLS) --show-bin-path $(SWIFT_FLAGS))/pmtools
APP_EXCLUDES := --exclude ProcessorMonitor/main.swift --exclude ProcessorMonitorHelper/main.swift
TOOLS_EXCLUDES := --exclude pmtools/main.swift
APP_COVERAGE := .build/coverage.json
TOOLS_COVERAGE := $(TOOLS)/.build/coverage.json
MAX_CRAP := 16
FILTER ?=

.PHONY: help build test coverage crap gate tools-build tools-test tools-coverage tools-crap tools-gate \
        mutate mutate-changed app pkg run clean

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

# ---- App package -------------------------------------------------------------------------

build: ## Debug build of the app package, warnings are errors
	swift build $(SWIFT_FLAGS) $(STRICT_FLAGS)

test: ## Run app tests (FILTER=<regex> to narrow, e.g. FILTER=LoadCalculatorTests)
	swift test $(TEST_FLAGS) $(STRICT_FLAGS) $(if $(FILTER),--filter '$(FILTER)')

coverage: tools-build ## App tests with coverage; fails unless every source file is 100% covered
	swift test $(TEST_FLAGS) $(STRICT_FLAGS) --enable-code-coverage
	scripts/export-coverage.sh "$$(swift test $(TEST_FLAGS) $(STRICT_FLAGS) --show-codecov-path)" $(APP_COVERAGE)
	"$(PMTOOLS)" coverage --json $(APP_COVERAGE) --sources "$(CURDIR)/Sources" $(APP_EXCLUDES)

crap: tools-build ## CRAP <= 16 for every app function (uses the JSON from `make coverage`)
	"$(PMTOOLS)" crap --json $(APP_COVERAGE) --sources "$(CURDIR)/Sources" $(APP_EXCLUDES) --max $(MAX_CRAP)

gate: build coverage crap tools-gate ## Full quality gate for both packages

# ---- Tools package -----------------------------------------------------------------------

tools-build: ## Build pmtools (coverage / crap / mutate)
	swift build --package-path $(TOOLS) $(SWIFT_FLAGS) --product pmtools

tools-test: ## Run Tools tests
	swift test --package-path $(TOOLS) $(TEST_FLAGS) $(if $(FILTER),--filter '$(FILTER)')

tools-coverage: tools-build
	swift test --package-path $(TOOLS) $(TEST_FLAGS) --enable-code-coverage
	scripts/export-coverage.sh "$$(swift test --package-path $(TOOLS) $(TEST_FLAGS) --show-codecov-path)" $(TOOLS_COVERAGE)
	"$(PMTOOLS)" coverage --json $(TOOLS_COVERAGE) --sources "$(CURDIR)/$(TOOLS)/Sources" $(TOOLS_EXCLUDES)

tools-crap: tools-build
	"$(PMTOOLS)" crap --json $(TOOLS_COVERAGE) --sources "$(CURDIR)/$(TOOLS)/Sources" $(TOOLS_EXCLUDES) --max $(MAX_CRAP)

tools-gate: tools-coverage tools-crap ## Quality gate for the Tools package
