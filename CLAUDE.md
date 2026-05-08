# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
mise install          # install Zig (required before anything else)
zig build             # dev build → zig-out/bin/agent-hud
zig build run         # build and run (reads stdin)
zig build -Doptimize=ReleaseSafe  # optimised build
make dry-run          # cross-compile both targets and print the gh release command
make release          # cross-compile and publish to GitHub (requires an exact git tag)
make clean            # remove dist/, zig-out/, .zig-cache/
```

## Architecture

Single file: `src/main.zig`. No external dependencies — only Zig's standard library.

Uses the Zig 0.16 `std.process.Init` main signature so the runtime provides `init.gpa` (general-purpose allocator) and `init.io` (the async-capable `std.Io` instance). All I/O — stdin, stdout, and child processes — goes through `init.io`.

**Data flow:**
1. Read all of stdin via `std.Io.File.stdin().reader(io, &buf).interface.allocRemaining()`
2. Parse JSON with `std.json.parseFromSlice` into typed structs (all fields optional with `null` defaults)
3. Spawn `git -C <cwd> rev-parse --abbrev-ref HEAD` via `std.process.run(gpa, io, ...)`
4. Print one line to stdout via `std.Io.File.stdout().writer(io, &buf).interface`

**Key Zig 0.16 API notes** (differ from older Zig versions):
- `std.heap.DebugAllocator` replaces `GeneralPurposeAllocator`
- `File.reader()`/`File.writer()` return a `File.Reader`/`File.Writer` — call `.interface` to get the `Io.Reader`/`Io.Writer` with `allocRemaining`, `print`, `flush`, etc.
- `Child.Term` uses lowercase variants: `.exited`, not `.Exited`
- `std.mem.trimEnd` replaces `std.mem.trimRight`

## Releases

Cross-compilation uses Zig's built-in cross-compiler — no Docker or extra tooling needed. Release targets: `aarch64-macos` and `x86_64-linux-musl`. Cross builds use `--prefix zig-out/<target>` to avoid overwriting the native dev binary at `zig-out/bin/agent-hud`.

Release workflow:
```bash
git tag v0.x.0
git push origin v0.x.0
make release   # requires gh auth login
```

## Claude Code integration

The binary is configured as a Claude Code `statusLine` command in `~/.claude/settings.json`. It reads the JSON payload Claude Code sends on stdin and outputs one line:

```
[Model] dirname (branch) | N% context | N% limit
```

`limit` reflects the 5-hour rolling rate limit (`rate_limits.five_hour.used_percentage`) — only populated for Claude.ai subscribers.
