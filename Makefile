# Quick development commands. Run `make` (or `make help`) to list them.

APP        := build/Manita.app
DESIGN     ?= cartoon
SIZE       ?= 1
MOOD       ?= 1
APPEARANCE ?= light
OUT        ?= /tmp/manita-pointer.png

.DEFAULT_GOAL := help
.PHONY: help build test app open release quit preview pointer clean

help: ## List the commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-8s %s\n", $$1, $$2}'

build: ## Compile (debug)
	swift build

test: ## Run the unit tests
	swift test

app: ## Build the debug app bundle (build/Manita.app)
	scripts/build-app.sh debug

quit: ## Quit a running Manita
	@pkill -x Manita 2>/dev/null || true

open: quit app ## Quit Manita, rebuild the debug app and open it
	open $(APP)

release: ## Build the release app bundle
	scripts/build-app.sh

preview: build ## Render the design's artwork: make preview DESIGN=path/to/folder
	.build/debug/Manita --render-preview /tmp/manita-preview.png $(DESIGN) 2
	open /tmp/manita-preview.png

pointer: build ## Render the whole pointer: make pointer DESIGN=cartoon SIZE=2 MOOD=3 APPEARANCE=dark
	.build/debug/Manita --render-pointer $(OUT) $(DESIGN) $(SIZE) $(MOOD) $(APPEARANCE)
	open $(OUT)

clean: ## Remove build outputs
	rm -rf .build build
