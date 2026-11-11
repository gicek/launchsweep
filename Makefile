SHELL := /bin/zsh
.DEFAULT_GOAL := help
MAKEFLAGS += --no-builtin-rules --no-print-directory

# Xcode, even when xcode-select points at the Command Line Tools. Set DEVELOPER_DIR to pick another Xcode.
ifndef DEVELOPER_DIR
XCODE_SELECTED := $(shell xcode-select -p 2>/dev/null)
DEVELOPER_DIR := $(or $(filter-out %/CommandLineTools,$(XCODE_SELECTED)),/Applications/Xcode.app/Contents/Developer)
endif
export DEVELOPER_DIR

PROJECT := LaunchSweep.xcodeproj
SCHEME := LaunchSweep
DERIVED_DATA := build/DerivedData
DEBUG_APP := build/debug/LaunchSweep.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Builds are quiet by default; for full output: make build XCODEBUILD_FLAGS=
# Tests are not quiet, because -quiet hides the ** TEST SUCCEEDED / FAILED ** line.
XCODEBUILD_FLAGS ?= -quiet
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
	-destination 'platform=macOS,arch=$(shell uname -m)' -derivedDataPath $(DERIVED_DATA)

.PHONY: help project open build run test icon clean

help: ## Show this help
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "  %-10s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

project: ## Generate LaunchSweep.xcodeproj from project.yml (needs xcodegen)
	@xcodegen generate --quiet

open: project ## Open the project in Xcode
	open $(PROJECT)

build: project ## Build the Debug app into build/debug
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) build
	@rm -rf $(DEBUG_APP) && mkdir -p $(dir $(DEBUG_APP))
	@ditto $(DERIVED_DATA)/Build/Products/Debug/LaunchSweep.app $(DEBUG_APP)
	@echo "==> $(DEBUG_APP)"

run: build ## Build and launch the Debug app, quitting a running copy first
	@pkill -x LaunchSweep || true
	open $(DEBUG_APP)

test: project ## Run the unit tests
	$(XCODEBUILD) test

icon: ## Regenerate the app icon from design/logo (needs Node)
	Scripts/build_icon.sh

# The build copies are unregistered from Launch Services first, so they don't linger as stale registrations.
clean: ## Remove build output
	@for app in $(DEBUG_APP) $(DERIVED_DATA)/Build/Products/*/LaunchSweep.app(N); do \
		$(LSREGISTER) -u $$app 2>/dev/null || true; \
	done
	rm -rf build
