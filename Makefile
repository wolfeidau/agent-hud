BINARY  := agent-hud
VERSION := $(shell git describe --tags --exact-match 2>/dev/null || echo "dev")
DIST    := dist

TARGETS := aarch64-apple-darwin x86_64-unknown-linux-musl

.PHONY: release dry-run build clean

dry-run: build
	@echo "Would run:"
	@echo "  gh release create $(VERSION) \\"
	@echo "    $(DIST)/$(BINARY)-$(VERSION)-aarch64-apple-darwin \\"
	@echo "    $(DIST)/$(BINARY)-$(VERSION)-x86_64-unknown-linux-musl \\"
	@echo "    --title \"$(VERSION)\" --generate-notes"

release: build
	gh release create $(VERSION) \
		$(DIST)/$(BINARY)-$(VERSION)-aarch64-apple-darwin \
		$(DIST)/$(BINARY)-$(VERSION)-x86_64-unknown-linux-musl \
		--title "$(VERSION)" \
		--generate-notes

build: $(addprefix build-, $(TARGETS))

build-aarch64-apple-darwin:
	zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe --prefix zig-out/aarch64-macos
	mkdir -p $(DIST)
	cp zig-out/aarch64-macos/bin/$(BINARY) $(DIST)/$(BINARY)-$(VERSION)-aarch64-apple-darwin

build-x86_64-unknown-linux-musl:
	zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe --prefix zig-out/x86_64-linux-musl
	mkdir -p $(DIST)
	cp zig-out/x86_64-linux-musl/bin/$(BINARY) $(DIST)/$(BINARY)-$(VERSION)-x86_64-unknown-linux-musl

clean:
	rm -rf $(DIST) zig-out zig-cache .zig-cache
