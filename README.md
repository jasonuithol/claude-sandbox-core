# claude-sandbox-core

A single, data-driven scaffold for running [Claude Code](https://claude.ai/code)
in a sandbox container against per-domain MCP service stacks.

Replaces the per-domain `claude-pygame` / `claude-sandbox` repos, which
duplicated 95% of the same Dockerfile + entrypoint + start/stop boilerplate
and differed only in which MCP services they registered.

## Layout

```
core/        Dockerfile + entrypoint.sh — same image for every domain
domains/     <domain>.conf files — MCP services, mounts, env per domain
bin/         setup.sh / start.sh / stop.sh / clean.sh — generic orchestrators
workspaces/  default per-domain workspace dirs (created on demand)
```

## Install loop

```bash
git clone https://github.com/jasonuithol/claude-sandbox-core ~/Projects/claude-sandbox-core

# Clone the MCP services you want. Each domain conf lists its required repos.
git clone https://github.com/jasonuithol/mcp-pygame   ~/Projects/mcp-pygame    # for pygame domain
git clone https://github.com/jasonuithol/mcp-valheim  ~/Projects/mcp-valheim   # for valheim domain
git clone https://github.com/jasonuithol/mcp-steam    ~/Projects/mcp-steam     # for valheim domain
git clone https://github.com/jasonuithol/mcp-dosre    ~/Projects/mcp-dosre     # optional, opportunistic
```

That's it — the install decision loop is "core + the services I want".

## Usage

```bash
./bin/start.sh pygame  UltimatePyve     # pygame domain, project at ~/Projects/UltimatePyve
./bin/start.sh valheim EepeyDeepey      # valheim domain, project at ~/Projects/EepeyDeepey

./bin/stop.sh  pygame                   # stop all pygame MCP services
./bin/stop.sh  valheim --kill           # SIGKILL instead of SIGTERM
./bin/clean.sh valheim                  # full teardown for valheim + remove sandbox image
```

`bin/start.sh` does, in order:

1. Source `domains/<domain>.conf`.
2. Verify each `MCP_REPOS` sibling is checked out and has a `start.sh`.
3. Build the `claude-sandbox-core` image (idempotent; first run only).
4. Run each repo's `start.sh` (also idempotent).
5. `podman run` the sandbox, mounting the conf at
   `/etc/claude-sandbox-domain.conf` for `entrypoint.sh` to source, plus
   the workspace, project dir, and any `EXTRA_MOUNTS` / `EXTRA_ENV`.
6. On Claude exit, run each repo's `stop.sh` so the next start revives them.

The sandbox auto-resumes the prior conversation if one exists for the
working directory (via `claude --continue`). To start fresh in-session,
use `/clear`.

## Adding a domain

Drop a `domains/<name>.conf` declaring the four arrays:

```bash
MCP_REPOS=( "$HOME/Projects/mcp-foo" )
SERVICES=( "foo-build|http://localhost:5192/mcp" )
OPTIONAL_SERVICES=()
EXTRA_MOUNTS=( "$HOME/Projects/mcp-foo/docs:/workspace/docs:ro,Z" )
EXTRA_ENV=()
```

No code changes needed — `bin/*.sh` and `core/entrypoint.sh` iterate these
arrays generically.

## Why split out the MCP services?

Each `mcp-*` sibling is a self-contained service with its own lifecycle
(`setup.sh`, `start.sh`, `stop.sh`, `clean.sh`). `claude-sandbox-core` only
knows the four-script contract — it doesn't know what's inside, what
ports anything binds, or which images get built. That split lets each
service evolve independently and lets the same MCP run under multiple
domains (e.g. `mcp-steam` is consumed by the valheim domain but isn't
Valheim-specific).
