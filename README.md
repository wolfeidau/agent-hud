# agent-hud

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

A status bar for [Claude Code](https://claude.ai/code) that displays context usage, session limit, and current git branch.

```
[Sonnet] agent-hud (main) | 43% context | 18% limit
```

## Installation

### Via mise (recommended)

```bash
mise use "ubi:wolfeidau/agent-hud"
```

This installs the latest release binary from GitHub and makes `agent-hud` available in your mise environment. The `statusLine` command path should then be set to the output of `mise which agent-hud`.

### Manual

Download the latest binary for your platform from the [releases page](https://github.com/wolfeidau/agent-hud/releases), then install it somewhere on your `PATH`:

```bash
install -m 755 agent-hud /usr/local/bin/agent-hud
```

## Setup

Add the following to your Claude Code `settings.json` (`~/.claude/settings.json`), adjusting the path to wherever `agent-hud` was installed:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/usr/local/bin/agent-hud"
  }
}
```

## Building from source

Requires [mise](https://mise.jdx.dev) and [Zig](https://ziglang.org) (installed automatically via mise).

```bash
mise install
zig build
```

### Publishing a release

Requires [`gh`](https://cli.github.com). Cross-compilation is handled by Zig with no extra tooling.

```bash
git tag v0.1.0
git push origin v0.1.0
make release
```

## Licence

Apache 2.0 — see [LICENSE](LICENSE).
