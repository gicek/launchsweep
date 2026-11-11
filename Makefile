SHELL := /bin/zsh
.DEFAULT_GOAL := help
MAKEFLAGS += --no-builtin-rules --no-print-directory

# Xcode, even when xcode-select points at the Command Line Tools (Scripts/release.sh uses the same rule).
# Set DEVELOPER_DIR to pick another Xcode.
ifndef DEVELOPER_DIR
XCODE_SELECTED := $(shell xcode-select -p 2>/dev/null)
DEVELOPER_DIR := $(or $(filter-out %/CommandLineTools,$(XCODE_SELECTED)),/Applications/Xcode.app/Contents/Developer)
endif
export DEVELOPER_DIR

# build/ layout: debug/ holds the Debug app, release/ the signed app and zip, dist/ the notarized DMG
# (see Scripts/release.sh). DerivedData and intermediates are build intermediates.
PROJECT := LaunchSweep.xcodeproj
SCHEME := LaunchSweep
DERIVED_DATA := build/DerivedData
DEBUG_APP := build/debug/LaunchSweep.app
# Builds are quiet by default; for full output: make build XCODEBUILD_FLAGS=
# Tests are not quiet, because -quiet hides the ** TEST SUCCEEDED / FAILED ** line.
XCODEBUILD_FLAGS ?= -quiet
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
	-destination 'platform=macOS,arch=$(shell uname -m)' -derivedDataPath $(DERIVED_DATA)

.PHONY: help project open build run test icon bump release dist publish verify-release go-live clean

help: ## Show this help
	@awk 'BEGIN { FS = ":.*## " } /^##@/ { printf "\n%s\n", substr($$0, 5) } \
		/^[a-z-]+:.*## / { printf "  %-14s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

##@ Build

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

##@ Release (Developer ID; see README for the full flow)

bump: ## Next build number, and VERSION=x.y.z if given; creates the release notes template
	Scripts/bump_version.sh $(VERSION)

release: test ## make test, then a signed, not notarized app and zip into build/release
	Scripts/release.sh release

dist: test ## Release, then a notarized DMG into build/dist
	Scripts/release.sh dist

publish: test ## Dist, then a draft GitHub release from build/dist (not live yet)
	Scripts/release.sh publish

verify-release: ## Download and check the GitHub release for this version (VERSION=x.y.z for another)
	Scripts/github_release.sh verify $(VERSION)

go-live: ## Verify, then publish the draft as the latest release
	Scripts/github_release.sh go-live $(VERSION)

##@ Cleaning

# The app copies in build/ are unregistered from Launch Services first, so they don't linger as stale
# registrations.
clean: ## Remove build output
	@Scripts/unregister_apps.sh build
	rm -rf build
