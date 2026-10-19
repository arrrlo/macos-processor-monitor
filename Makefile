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
MUTATION_JOBS ?= 6
MUTATION_EXCLUDES := --exclude Sources/ProcessorMonitor/main.swift --exclude Sources/ProcessorMonitorHelper/main.swift

.PHONY: help build test coverage crap gate mutate tools-build tools-test tools-coverage tools-crap tools-gate \
        tools-mutate app pkg run overhead icon clean

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

mutate: tools-build ## Mutation testing (CHANGED=<git ref> or FILE=Sources/... to narrow); any survivor fails
	"$(PMTOOLS)" mutate --package "$(CURDIR)" --jobs $(MUTATION_JOBS) $(MUTATION_EXCLUDES) \
		--build 'swift build --build-tests -j 3 $(SWIFT_FLAGS) $(STRICT_FLAGS)' \
		--test 'swift test --skip-build $(TEST_FLAGS) $(STRICT_FLAGS)' \
		$(if $(CHANGED),--changed '$(CHANGED)') $(if $(FILE),--file '$(FILE)')

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

tools-mutate: tools-build ## Mutation testing of the Tools package
	"$(PMTOOLS)" mutate --package "$(CURDIR)/$(TOOLS)" --jobs $(MUTATION_JOBS) --exclude Sources/pmtools/main.swift \
		--build 'swift build --build-tests -j 3 $(SWIFT_FLAGS)' \
		--test 'swift test --skip-build $(TEST_FLAGS)' \
		$(if $(FILE),--file '$(FILE)')

# ---- Packaging ---------------------------------------------------------------------------

app: ## Release build/macOS Processor Monitor.app and helper (ad-hoc signed)
	scripts/build-app.sh

pkg: app ## Single-file installer build/macos-processor-monitor-<VERSION>.pkg
	scripts/build-pkg.sh

run: app ## Build and launch the .app (quits a running copy first)
	-pkill -x ProcessorMonitor
	open "build/macOS Processor Monitor.app"

overhead: ## Average CPU and memory of the running app over SECONDS (default 300)
	scripts/measure-overhead.sh $(or $(SECONDS),300)

icon: ## Regenerate packaging/AppIcon.icns
	scripts/make-icon.sh

clean: ## Remove all build output
	rm -rf .build build $(TOOLS)/.build
