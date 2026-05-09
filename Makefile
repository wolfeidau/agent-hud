BINARY  := agent-hud
VERSION := $(shell git describe --tags --exact-match 2>/dev/null || echo "dev")
DIST    := dist

.PHONY: release snapshot clean test

snapshot:
	goreleaser build --single-target --snapshot --clean

release:
	goreleaser release --clean

clean:
	rm -rf $(DIST) zig-out zig-cache .zig-cache

test:
	zig build test
