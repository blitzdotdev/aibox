# aibox v2 — Revamp Requirements

Requirements for rewriting aibox around how it is actually used: one trusted
machine, one user, Claude Code in a sandbox, containers that are cheap to
enter and impossible to lose data in.

This document is the spec for the rewrite. It records the decisions already
made (with rationale), the exact command surface, the architecture, and what
gets deleted. A separate one-time migration script (also specced here) moves
existing data into the new layout.

---

## 1. Why

The current `bin/aibox` is 2,379 lines, 16 commands, and optimizes for
safety features and isolation modes that go unused, while getting the one
thing that matters wrong: **data durability**.

Concrete problems in the current implementation:

- **Destructive lifecycle by default.** When the last `claude`/`shell`
  session exits, the script silently runs `docker compose down`
  (`bin/aibox:1154-1170`). The container is *removed*, not stopped — every
  apt package, global npm install, and any file outside a mounted volume is
  destroyed. This has caused real data loss. A second destructive path:
  running `aibox claude` in a different mode than the container was started
  with (`--yolo` vs `--safe`) also `down`s the running container
  (`bin/aibox:1447-1453`).
- **Fragmented session history.** Auth/session state lives in a volume named
  per image — `aibox-auth-<image>` (`bin/aibox:1068`). Change the image tag
  and you get a fresh volume: new login, empty session list, old sessions
  stranded in the previous volume. Multiple such volumes now exist, each
  holding a slice of history.
- **No first-class backup.** Backups currently depend on an external
  hand-rolled script.
- **Port forwarding is manual and clunky.** Each forwarded port is a
  `alpine/socat` sidecar container created by hand (`aibox port-forward`).
  In practice this was abandoned in favor of asking Claude to open a
  Cloudflare quick tunnel — workable, but slow, public, and not ideal.
- **Unused surface area.** Safe mode + domain-allowlist firewall, restricted
  sudo, `--copy` / `--worktree` isolation, named instances, `--repo` clone
  mode, compose orchestration, `init` / WebStorm integration, `clean`,
  `nuke`, `doctor`, `volumes`, `disk` — none of it is used. It exists to
  serve hypothetical users, and it is where the 2,400 lines went.
- **It writes into your project.** Plain `aibox up` auto-runs init when
  `compose.dev.yaml` is missing (`bin/aibox:1314-1327`), dropping
  `compose.dev.yaml`, `.aibox`, and `.idea/workspace.xml` into the project
  and editing its `.gitignore`.
- **Greedy global flag parsing.** All argv is scanned for aibox flags before
  dispatch (`bin/aibox:251-325`), so `aibox claude -c` becomes aibox's
  `--copy` instead of Claude's `--continue`; interactive prompts plus
  unconditional `docker exec -it` also make non-interactive use
  (`claude -p` in a pipe) impossible.

## 2. Product decisions (settled)

These were decided explicitly; the rewrite must not relitigate them.

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| D1 | Language / distribution | Single bash file, published to npm as `aibox-cli` (same as today) | New scope is ~500 lines, not 2,400; zero runtime deps beyond Docker |
| D2 | Security posture | Permission prompts on by default with bypass selectable in-session (`--allow-dangerously-skip-permissions`); `aibox --yolo` starts in bypass (`--dangerously-skip-permissions`). No firewall, no restricted sudo | Isolation comes from the container boundary itself; the prompt default is the only mode switch |
| D3 | Container lifecycle | Container **keeps running in the background** when the last session exits. `aibox stop` stops it explicitly. It is only ever *removed* when the image changes (and then only recreated, never left absent) | Instant re-attach; idle containers cost ~nothing; kills the data-loss footgun |
| D4 | Instances | Exactly one persistent container per project directory; multiple terminals just `exec` into the same container. No named instances. `--copy` additionally spawns a disposable container per run (unique name, removed on exit) | Matches real usage; disposable runs must not fight over one name |
| D5 | Session/home storage | One **global** named volume `aibox-home`, mounted in **slices** (`volume-subpath`, Engine 26+): shared slices for the Claude login/settings and binary, a private per-project slice for each project's home and transcripts. Old flat volumes migrate in place automatically (safety backup first; unrecognized files never moved) | One login and one backup tar stay; project-vs-project isolation is enforced at the mount level — the only level that means anything with full sudo inside |
| D6 | Project mount | Bind-mount the project directory at **the same absolute path as on the host** (today's default-mode behavior, `bin/aibox:475`). `--copy` skips the bind mount and streams a tar snapshot to the same path instead | Claude session keys are derived from cwd — keeping the path keeps every existing session valid with zero migration (copy mode included, since the path matches) |
| D7 | Backup | Built-in `aibox backup` / `aibox restore` — clean and simple, must actually work | Replaces the external script |
| D8 | Migration of old data | A **separate standalone script** (not part of the CLI) that merges both live `aibox-auth-*` volumes **and** old backup folders into the new `aibox-home` volume | One-time operation; keeps the CLI clean |
| D9 | Dev-server access | Host-side reverse proxy with wildcard subdomains: `http://<port>.<project>.aibox.localhost` → container port. Replaces port-forward sidecars and ad-hoc Cloudflare tunnels for local use | `*.localhost` (multi-level included) resolves to loopback natively in Chrome/Edge and Firefox 84+ with zero setup, no sudo, no dnsmasq; Safari only gained this on macOS 26 Tahoe (WebKit bug 160504). CLI tools using the system resolver (curl) don't resolve it — documented workaround, not solved. `/etc/hosts` can't do wildcards, so there is no hosts-file step |
| D10 | Base image | `node:${node_version}-bookworm` (Debian 12), `node_version` configurable in `~/.aibox/config`, default = current Active LTS (`24` as of mid-2026; Node 22 entered maintenance Oct 2025, Node 20 is EOL) | Debian-based official node images are the standard container base; glibc means nothing is uninstallable. Node version is a one-line config change |
| D11 | Command surface | Exactly the commands in §3 (including the post-spec `sessions`/`rc-resume` additions). Everything from v1 outside it is deleted | See §8 for the deletion list |

## 3. Command surface

```
aibox                      # same as `aibox claude`
aibox claude [args...]     # shorthand for `aibox run claude`; --yolo skips all prompts, --copy uses a disposable snapshot container, other args pass through (--resume, -c, etc.)
aibox run [--copy] <prog> [args...]  # ensure image/container/proxy, then run any program inside (e.g. aibox run codex)
aibox serve                # sessions UI (port 45789) in the container: new/resume/stop phone-drivable sessions, each a detached claude --remote-control process; serve stop ends it all
                           # (known trade-off: the UI binds container-wide for the proxy, so other containers on the aibox network can reach it; its endpoints only spawn/stop THIS project's sessions)
aibox sessions             # host-side all-projects page (loopback :45790, foreground): expand/search every project's sessions, open in a terminal, copy the resume command, or send to the phone
aibox rc-resume <id>       # plumbing for the above: make one past session of this project phone-drivable
aibox shell [cmd...]       # zsh in the container, or run a one-off command
aibox stop [--all]         # stop this project's container (--all: every aibox container + proxy). Never deletes anything
aibox status               # all aibox containers: project, state, uptime, image; proxy URLs; volume size
aibox backup [dir]         # snapshot aibox-home volume to a tar.gz on the host
aibox restore <path>       # restore a backup into aibox-home (with automatic pre-restore safety backup)
aibox update               # update CLI (npm), rebuild image if needed, mark containers for recreation
aibox version              # CLI version, image version, docker info
aibox help
```

Rules:

- Unknown command → one-line error with a help hint, exit 1. No interactive prompts anywhere except
  destructive confirmations (`restore`) and first-run niceties.
- Everything after `claude` passes through to claude, except aibox's own
  `--copy`/`--yolo`, which are consumed wherever they appear; a `--` ends
  aibox flag parsing. Nothing else gets swallowed the way v1's parser ate
  `-c` (`bin/aibox:251-325`).
- Allocate a TTY (`docker exec -it`) only when stdin is a terminal, so
  `aibox claude -p "..."` and piped/scripted use work; v1 hard-coded `-it`.
- `run`/`claude`/`shell`/`serve`/`rc-resume` create everything they need;
  everything they need (image, network, volume, container, proxy) is created
  idempotently on demand. There is no `up`/`build`/`init`.
- Keep v1's non-blocking update notice (`bin/aibox:2304-2326`): a cached,
  24h-throttled npm version check that prints a one-line hint when a newer
  `aibox-cli` exists. It must never block or slow a command.
- Every command must be safe to run concurrently from multiple terminals
  (two tabs running `aibox claude` simultaneously on the same project must
  not race the container creation — use a lock or tolerate-exists creation).

## 4. Architecture

### 4.1 Naming and identity

- Project identity = absolute path of the project directory (the cwd where
  `aibox` is invoked; symlinks resolved).
- Container name: `aibox-<slug>-<hash6>` where `<slug>` is the sanitized
  directory basename and `<hash6>` is the first 6 hex chars of the SHA-256 of
  the absolute path. Two directories both named `app` never collide.
- Proxy hostname label: `<slug>` (see §5); on slug collision between two
  *running* projects, the later one uses `<slug>-<hash6>`. `aibox status`
  always shows the canonical URL.
- Docker network: `aibox` (bridge), shared by all project containers and the
  proxy.
- Volume: `aibox-home`, mounted at `/home/aibox` in every project container.
- Image: `aibox:<cli-version>` (e.g. `aibox:2.0.0`), so image staleness is
  detectable by tag comparison alone.

### 4.2 Container spec

- Plain `docker run` / `docker exec` — **no docker compose**, no generated
  YAML. One container needs no orchestrator, and compose's `down` semantics
  were part of the original footgun.
- Mounts (see D5 — five volume-subpath slices of `aibox-home`):
  - `projects/<hash6>/home` → `/home/aibox` (private)
  - `shared/claude-cfg` → `/home/aibox/.claude` (login/settings, shared)
  - `projects/<hash6>/claude-projects` → `/home/aibox/.claude/projects` (private transcripts)
  - `shared/local-bin` + `shared/claude-app` → the claude binary (shared)
  - `<project-abs-path>:<project-abs-path>` (bind, rw), workdir = that path
- `CLAUDE_CONFIG_DIR=/home/aibox/.claude` (unchanged from v1, so existing
  `.claude` contents drop in as-is).
- User `aibox` (uid 1000), passwordless sudo, login shell zsh. Note:
  `node:*-bookworm` ships a `node` user already occupying uid 1000 — the
  Dockerfile must remove it (`userdel -r node`) before creating `aibox`.
- `--add-host host.docker.internal:host-gateway` so the container can reach
  services on the Mac (kept from v1).
- `docker exec` forwards `TERM`, `COLORTERM`, `LANG`, and any `ANTHROPIC_*`
  vars set on the host (kept from v1; the IDE-integration env plumbing is
  not kept).
- No host dotfiles are mounted (`.gitconfig`, `~/.ssh` — same as v1). This
  is fine in v2 precisely because the home volume persists: configure git
  identity or SSH keys once inside the container and they stick forever.
- Long-running init process: `sleep infinity` (or equivalent) so the
  container stays up independent of sessions. `--restart unless-stopped` so
  it survives Docker/Colima restarts. No healthcheck needed.
- Sessions are `docker exec -it` — a session ending never affects the
  container.

### 4.3 Lifecycle

```
aibox claude/shell:
  docker running?          → if colima installed but stopped: colima start; else error with install hint
  image aibox:<ver> exists? → build if missing (first run or post-update)
  container exists?
    ├─ no  → create (docker run -d)
    ├─ yes, stopped → docker start
    └─ yes, running → (nothing)
  container image ≠ aibox:<ver>?
    → if no active exec sessions: recreate (rm + run; aibox-home and project
      bind survive by construction; warn that apt-installed packages reset)
    → if sessions active: warn and continue on the old image
  proxy running? → start if not (§5)
  docker exec -it <container> <claude|zsh> ...
```

- One generic launcher (`cmd_run`) runs any program in the sandbox;
  `aibox`/`aibox claude` dispatch to `run claude`. When the program is
  claude, it is invoked with `--allow-dangerously-skip-permissions` (prompts
  on, bypass selectable in-session) plus any passthrough args; `--yolo`
  swaps that for `--dangerously-skip-permissions` (all prompts skipped) and
  is rejected for other programs (their approval flags pass through as
  normal args).
- `--copy` runs claude in a disposable container instead: fresh container
  per run (`<container>-copy-<rand>`, no restart policy, labeled
  `aibox.copy=1` with slug `<slug>-copy` for its own dev URLs), no bind
  mount — the project is streamed in as a tar snapshot to the same absolute
  path, extracted as the container user (so ownership is right without a
  full-tree chown). It shares the home volume, so login and session history work,
  and the container is removed on exit (EXIT trap; work is kept by
  committing/pushing from inside).
- **Nothing happens on session exit.** No idle-detection, no auto-stop, no
  down. The container idles at ~zero CPU until the next attach or an
  explicit `aibox stop`.
- `aibox stop` = `docker stop` only. A stopped container preserves its
  writable layer (apt installs etc.); next `aibox claude` starts it again in
  ~1s.
- The only code path that ever runs `docker rm` on a project container is
  image-change recreation, which immediately recreates it.

### 4.4 Image

Dockerfile is embedded in the script (heredoc, as today) and written to
`~/.aibox/Dockerfile` at build time:

- `FROM node:${node_version}-bookworm` — verified to ship git, python3,
  make, gcc/g++, and curl out of the box (~400 MB compressed, ~1.6 GB
  uncompressed).
- apt: `zsh sudo ripgrep fzf jq less procps curl` (keep this list short —
  the container persists, so Claude apt-installs anything else once and it
  sticks).
- Claude Code installed via the native installer
  (`curl -fsSL https://claude.ai/install.sh | bash`) **at first container
  start** (entrypoint checks, installs if missing). The installer puts a
  launcher at `~/.local/bin/claude` with versions under
  `~/.local/share/claude/` — both inside the `aibox-home` volume — so
  `claude update` (and the native install's background auto-updates)
  persist across container recreation and image rebuilds, and all projects
  share one install. Current Claude Code versions verifiably create
  `.claude.json` *inside* `CLAUDE_CONFIG_DIR`, so all state lands in the
  volume (very old builds handled `CLAUDE_CONFIG_DIR` inconsistently —
  irrelevant here since the installer always fetches current). This is a hard constraint, not a
  preference: v1 bakes the installer into the image's home dir
  (`bin/aibox:556`), but in v2 the `aibox-home` volume mounts over all of
  `/home/aibox`, shadowing anything the image put there — so nothing may be
  installed into the home directory at image-build time.
- The entrypoint also fixes ownership of `/home/aibox` on start (migrated
  v1 volumes can contain root-owned files; v1 did the same for `.claude`,
  `bin/aibox:572`).
- Optional user extension: if `~/.aibox/Dockerfile.extra` exists, its
  contents are appended to the generated Dockerfile before build. This is
  the supported way to make custom tooling survive image-change recreations.
- Build with `docker build --pull` so the `node:*-bookworm` base actually
  refreshes on rebuilds (v1 never pulled, so its base only updated by
  accident).

### 4.5 State on the host

```
~/.aibox/
  config             # key=value, see §7
  Dockerfile         # generated at build (informational; regenerated each build)
  Dockerfile.extra   # optional, user-authored
  Caddyfile          # generated proxy config (§5)
~/aibox-backups/     # default backup destination (§6)
```

`~/.config/aibox` (v1) is left untouched; the migration script may read it,
the new CLI never does.

## 5. Dev-server proxy

Goal: Claude starts `vite` / `next dev` / `wrangler dev` on any port inside
the container, and the host browser reaches it immediately at a stable URL —
no commands, no restarts, no sidecars, no tunnels.

- One shared container `aibox-proxy` (image: `caddy:2-alpine`), on the
  `aibox` network, publishing `127.0.0.1:80->80`. Started lazily by the
  first `aibox claude`/`shell`; stopped by `aibox stop --all`.
- Routing rule: request `Host` of the form `<port>.<slug>.aibox.localhost`
  reverse-proxies to `aibox-<slug>-<hash6>:<port>` over the Docker network.
  Because the proxy reaches containers directly on the internal network, **no
  container ports are ever published** — any port works dynamically, ports
  the app opens after container start included.
- Config: a small generated Caddyfile (`~/.aibox/Caddyfile`) mounted into
  the proxy. When a project container is created or renamed, the CLI
  regenerates the file and reloads the proxy (`caddy reload` via exec —
  graceful, in-flight connections drain rather than drop).
- The core routing needs no per-project config at all — this exact
  Caddyfile was tested against `caddy:2-alpine` (v2.11) and routes
  `Host: 5173.myapp.aibox.localhost` to container `aibox-myapp:5173`
  (labels index right-to-left from zero):

  ```
  http://*.*.aibox.localhost {
      reverse_proxy aibox-{http.request.host.labels.2}:{http.request.host.labels.3}
  }
  ```

  Per-project regeneration is only needed because real container names
  carry the `-<hash6>` suffix (§4.1) — a `map` block from slug to full
  container name, rewritten on container create/rename.
- WebSockets must work (Caddy's `reverse_proxy` handles them by default) —
  vite HMR is the primary consumer.
- `aibox status` and container-start output print the concrete base URL,
  e.g. `http://5173.myapp.aibox.localhost`.
- Inside the container, set an env var (e.g. `AIBOX_URL_BASE=myapp.aibox.localhost`)
  so Claude can tell the user the right URL for whatever port it just opened.
- If publishing host port 80 fails (already taken, or the runtime can't),
  fall back to `proxy_port` from config (default fallback 8080) and include
  the port in printed URLs (`http://5173.myapp.aibox.localhost:8080`).
  Low-port caveat on macOS: binding `127.0.0.1:80` specifically needs
  privileges — Docker Desktop handles it via its privileged helper, while
  Colima/OrbStack emulate loopback-only publishing by binding `0.0.0.0` and
  rejecting non-loopback sources (old Colima versions ignored the loopback
  restriction entirely, exposing the port on the LAN — acceptable here
  since everything behind it is already sandboxed dev traffic, but worth a
  line in the README).
- Non-goals: HTTPS (plain http on loopback is fine), public sharing
  (Cloudflare tunnels remain possible manually; a built-in `aibox share` is
  a future idea, §9), and CLI tools that don't respect `*.localhost` DNS
  (curl needs `--resolve`; documented, not solved — `/etc/hosts` has no
  wildcard support so there is no standard hosts-file fix).

## 6. Backup and restore

Design principle: a backup is one portable file; restore is dumb and
predictable; nothing in either path can delete data it didn't just save.

- `aibox backup [dir]`
  - Snapshots the **entire `aibox-home` volume** (sessions, `.claude.json`,
    credentials, shell history, claude binary, npm globals) to
    `<dir>/aibox-home-<version>-<UTC timestamp>.tar.gz`. Default dir:
    `~/aibox-backups` (overridable in config).
  - Implemented as a throwaway helper container mounting the volume
    **read-only** and streaming `tar` to the host (the pattern Docker's own
    docs recommend for volume backup). Safe to run while containers are up
    in the sense that the source is never written to; a session actively
    appending its `.jsonl` mid-tar may be captured mid-write, which is
    acceptable for append-only session logs.
  - Prints archive path + size; keeps every backup (no rotation in v2 — the
    user deletes old ones; a `backup_keep` config knob is a future idea).
- `aibox restore <path>`
  - `<path>` is an archive produced by `aibox backup`.
  - Steps: (1) require confirmation, (2) automatically run a safety backup
    of the current volume first, (3) stop containers using the volume,
    (4) wipe the volume and extract the archive into it, (5) restart what
    was running — v2 instead REMOVES aibox containers after restore so the
    next run recreates them against the restored layout (subpath mounts of a
    pre-migration backup would not match).
  - Restore is **replace**, not merge — merging heterogeneous histories is
    the migration script's job (§6.1). This keeps restore trivially
    predictable: after restore, the volume equals the backup, and the state
    it replaced is itself a backup.

### 6.1 Migration script (separate, one-time)

`scripts/migrate-to-v2.sh` — lives in the repo, runs standalone (not part of
the npm bin, never called by the CLI).

Sources, all merged into the (possibly already-populated) `aibox-home`
volume:

1. **Every `aibox-auth-*` Docker volume** found on the machine (running or
   stopped v1 containers don't matter; sources are only ever read).
2. **Old backup folders** produced by the user's existing external backup
   script, passed as arguments: `migrate-to-v2.sh [backup-dir ...]`.

Merge rules:

- Everything except `.claude.json`: copy the **entire volume tree
  no-clobber** — don't enumerate directories (v1 volumes contain at least
  `projects/`, `todos/`, `session-env/`, `file-history/`,
  `shell-snapshots/`, per `bin/aibox:2047`, and the set may vary by Claude
  Code version). Sessions are one file per UUID, so a plain union is
  correct. Count copied vs skipped and report.
- `.claude.json`: start from the newest copy (by mtime), then merge the
  `projects` map keys from every other copy via `jq` (newest wins per key).
  OAuth/credentials come from the newest copy only.
- Session-key paths: default-mode v1 sessions are keyed by host paths (D6)
  and need **no remapping**. Old `--copy`/`--worktree` sessions keyed under
  `/workspace/...` are copied as-is (harmless), with an optional
  `--map /workspace/foo=/Users/me/foo` flag to rekey them if ever wanted.
- Idempotent: running it twice changes nothing the second time.
- Strictly read-only on all sources. It never stops, deletes, or edits v1
  containers, volumes, or backup folders — the user deletes those manually
  after verifying (`docker volume rm`, etc.; the script prints the exact
  cleanup commands as its final output but does not run them).

## 7. Config

`~/.aibox/config`, `key=value`, all optional:

```
node_version=24        # base image tag: node:<this>-bookworm
proxy_port=80          # host port for the dev-server proxy
backup_dir=~/aibox-backups
```

No per-project config file in v2 (v1's `.aibox` is ignored). Changing
`node_version` takes effect via `aibox update` (image rebuild → containers
recreate on next start).

## 8. Deleted from v1

Removed entirely, with no deprecation shims — v2 is a clean break
(major-version bump of `aibox-cli`):

- Commands: `up`, `down`, `build`, `init`, `port-forward`, `volumes`,
  `disk`, `clean`, `nuke`, `doctor`.
- Flags: `-n/--name`, `-r/--repo`, `-b/--branch`, `-c/--copy`,
  `-w/--worktree`, `-y/--yolo` and `-c/--copy` (v2 keeps only the long
  `--yolo` / `--copy` spellings: claude's bypass-permissions flag and the
  disposable snapshot container), `-s/--safe`,
  `-i/--image`, `--all`/`--clean` on `down`.
- Mechanisms: compose orchestration (v1 pipes generated YAML into
  `docker compose -f -`) and the JetBrains-facing `compose.dev.yaml`, socat
  port-forward sidecars, network firewall + `AIBOX_EXTRA_DOMAINS`,
  restricted sudo, sensitive-file detection, WebStorm/JetBrains config
  generation, IDE-integration plumbing (`~/.claude/ide` ro-mount and
  `ENABLE_IDE_INTEGRATION`/`CLAUDE_CODE_SSE_PORT` forwarding), per-image
  `aibox-auth-*` volumes, auto-`down` on last session exit, mode-switch
  `down`, Colima/Docker auto-*install* (auto-*start* of an installed
  Colima/OrbStack/Docker Desktop stays; installation becomes a printed
  one-liner hint).

Target size was **~500 lines** of bash for the core; the serve/sessions UIs
(embedded Node, added post-spec) put the final file at ~1,700. If a CORE
addition pushes past the ballpark,
something from this spec is being over-built.

## 9. Non-goals / future ideas

Not in v2; recorded so they aren't accidentally half-built:

- `aibox share <port>` — public URL via `cloudflared` quick tunnel (the
  current manual workflow, automated).
- Backup rotation (`backup_keep=N`).
- Linux hosts as a first-class target (nothing should actively break, but
  macOS + Colima/Docker Desktop/OrbStack is what gets tested).
- Multiple containers per project, non-Claude agent presets, Homebrew tap
  refresh.

## 9b. Accepted implementation deviations

Recorded post-implementation; intentional:

- Image tag is `aibox:<cli-version>-node<node_version>` (not bare
  `aibox:<cli-version>`) so a `node_version` config change also triggers
  rebuild + recreation by pure tag comparison.
- Proxy slug-collision labels are computed over all project containers
  (running or stopped), not just running ones — URLs stay stable across
  stop/start.
- `aibox status` shows the image only when it differs from current (as a
  "will be recreated" note) rather than as a column.
- Unstamped git checkouts run as version `dev` (image `aibox:dev-node<v>`),
  with the npm update notice disabled.

## 10. Acceptance criteria

The rewrite is done when all of these hold:

1. `cd proj && aibox` on a fresh machine (Docker present): builds image,
   creates volume/network/container/proxy, lands in a Claude session.
2. Exit Claude, run `aibox claude` again → re-attached in under a second;
   `apt install imagemagick` from a previous session is still installed.
3. Two terminal tabs, same project: both `aibox claude` concurrently → two
   sessions, one container, no race errors.
4. `aibox stop && aibox claude` → container starts again with all state
   (including apt layer) intact.
5. Claude runs `npx vite` (port 5173) inside the container →
   `http://5173.<slug>.aibox.localhost` serves it in the host browser with
   working HMR, with no port ever having been published or configured.
6. `aibox update` after a version bump → next `aibox claude` recreates the
   container on the new image; all Claude sessions, login, and `claude`
   binary version are unchanged (home volume); a warning notes the apt
   layer reset.
7. `aibox backup` while a session is running → single `.tar.gz`;
   `aibox restore` of it onto a wiped volume reproduces login + full
   session list (`claude --resume` shows history).
8. `scripts/migrate-to-v2.sh <old-backup-dir>` on a machine with existing
   `aibox-auth-*` volumes → one `aibox-home` volume where `claude --resume`
   in a previously-used project lists sessions that originated from *both*
   the live volumes and the old backup folders; running it again reports
   zero new files.
9. Deleting any project container (`docker rm -f`) loses no Claude data —
   next `aibox claude` recreates it and every session is still there.
10. The core (excluding the embedded serve/sessions UI payloads) stays in
    the ~500-line ballpark, and no command outside §3 exists.
