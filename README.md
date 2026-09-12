<p align="center">
  <h1 align="center">aibox</h1>
  <p align="center"><strong>Persistent Docker sandboxes for Claude Code</strong></p>
  <p align="center">
    <a href="https://www.npmjs.com/package/aibox-cli"><img src="https://img.shields.io/npm/v/aibox-cli" alt="npm" /></a>
    <a href="https://www.npmjs.com/package/aibox-cli"><img src="https://img.shields.io/npm/dm/aibox-cli" alt="downloads" /></a>
    <a href="https://github.com/blitzdotdev/aibox/blob/main/LICENSE"><img src="https://img.shields.io/github/license/blitzdotdev/aibox" alt="license" /></a>
  </p>
</p>

> *One command into a sandboxed Claude Code. Nothing gets destroyed behind your back.*

```bash
cd myproject && aibox
```

aibox runs Claude Code inside a Docker container, so the agent can run wild while your Mac stays clean. Add `--yolo` to skip all permission prompts. One container per project, all sharing a single persistent home volume — one login, per-project session history, everything survives.

## Quickstart

```bash
npm install -g aibox-cli    # 1. install
cd myproject                # 2. go to your project
aibox                       # 3. run (builds the image on first use)
```

## How it works

- **One container per project directory.** `aibox` in a project creates (or re-attaches to) that project's container. Open more terminal tabs and run `aibox` again — they attach to the same container.
- **Your project is bind-mounted at its real path.** Changes sync both ways, paths inside the container match your Mac.
- **One home volume, sliced per project.** Claude login, settings, and the `claude` binary live in shared slices of the `aibox-home` volume — log in once, forever. Everything else in a project's home (ssh keys, shell history, caches, and that project's sessions) is a private slice only its own containers mount, so one project's agent can't read another project's home directory or session transcripts. (Claude's shared bookkeeping — settings, todos, file-history — stays common; the private slices are the home dir and transcripts.) Volumes from older aibox versions migrate to this layout automatically on first run, with a safety backup taken first.
- **Nothing is destroyed implicitly.** Exiting Claude leaves the container running in the background (idle containers cost ~nothing) — the next `aibox` attaches instantly. `aibox stop` stops it; a stopped container keeps everything, including packages you apt-installed. Containers are only recreated when the image changes, and the home volume survives even that.
- **The container is the sandbox.** Full sudo inside. Permission prompts are on by default, but bypass mode is always available in-session (aibox passes claude's `--allow-dangerously-skip-permissions`); run `aibox --yolo` to start with all prompts skipped (`--dangerously-skip-permissions`).
- **Disposable copies on demand.** `aibox --copy` runs Claude in a fresh container on a *snapshot* of the project instead — nothing is bind-mounted, so the agent physically can't touch your real files. Same login and session history (shared home volume), own dev URLs (`<port>.<project>-copy.aibox.localhost`). The container is removed when the session exits; keep work by committing and pushing from inside. Each `--copy` run is its own independent sandbox. Combines with `--yolo`, and works for any program via `aibox run <prog> --copy`.

## Dev servers

Anything listening on any port inside the container is instantly reachable from your browser:

```
http://<port>.<project>.aibox.localhost
```

Claude starts `vite` on 5173 in project `myapp` → open `http://5173.myapp.aibox.localhost`. No ports to publish, no restarts, no config — a tiny shared Caddy proxy on the Docker network reaches any container port directly, WebSockets/HMR included.

Works out of the box in Chrome, Edge, and Firefox (`*.localhost` resolves to loopback natively). Safari needs macOS 26+. CLI tools like `curl` need `--resolve` (the system resolver doesn't do `*.localhost`).

## Phone & browser sessions

```bash
aibox serve
```

runs a small sessions UI at `http://45789.<project>.aibox.localhost`. **New session** starts a fresh session you drive from claude.ai/code or the Claude phone app ([Remote Control](https://code.claude.com/docs/en/remote-control)); **Resume** brings any past session back the same way; live sessions show as such and can be stopped. Every session is one detached claude process inside the project's container — closing your terminal changes nothing, and registration is outbound-only HTTPS (no ports, nothing exposed). Any Claude session can pull the same tricks on request — the shared CLAUDE.md teaches it the commands, so you can also say "start me a new session" from your phone in any live chat. `aibox serve stop` ends the UI and every live session of this project. On a remote Linux box, reach the UI with `ssh -L 8080:127.0.0.1:80 host` and open the same URL with `:8080`; the phone side needs no tunnel at all.

## Backup & restore

Everything worth keeping is in one volume, so backup is one file:

```bash
aibox backup                 # ~/aibox-backups/aibox-home-<ver>-<timestamp>.tar.gz
aibox backup /some/dir       # custom destination
aibox restore <backup.tar.gz> # replaces the volume (auto safety-backup first)
```

Backups are safe to take while sessions are running.

## Migrating from aibox v1

v2 is a clean break: one container per project, one shared home volume, and no destructive lifecycle. A standalone script merges all your v1 data — every per-image `aibox-auth-*` volume **and** any old backup folders — into the new volume:

```bash
# npm installs ship the script next to the CLI:
bash "$(npm root -g)/aibox-cli/scripts/migrate-to-v2.sh" [old-backup-dir ...]

# or fetch it directly:
curl -fsSL https://raw.githubusercontent.com/blitzdotdev/aibox/main/scripts/migrate-to-v2.sh | bash -s -- [old-backup-dir ...]
```

Sessions merge file-by-file (nothing is ever overwritten or deleted; sources are read-only), `.claude.json` is merged newest-wins, and the script prints — but never runs — the cleanup commands for old v1 resources.

**Order matters:** run this merge **before** your first v2 `aibox` run — that first run slices the volume into the per-project layout, and data merged into the flat layout afterwards would sit unmounted (visible via `aibox sessions`, but not live).

## Commands

| Command | What it does |
|---------|-------------|
| `aibox` / `aibox claude [args]` | Shorthand for `aibox run claude`. `--yolo` skips all permission prompts; `--copy` uses a disposable snapshot container (no bind mount, removed on exit); other args pass through verbatim (`--resume`, `-p`, ...). `aibox --resume` works too |
| `aibox run [--copy] <prog> [args]` | Run any program in the sandbox (e.g. `aibox run codex`). `--copy` works the same as above; the program's own flags pass through |
| `aibox serve` | Sessions UI in the container: start new phone/claude.ai-drivable sessions, resume past ones, stop live ones. `aibox serve stop` ends the UI and every live session of this project |
| `aibox sessions` | All projects' sessions on one local page (host-side, loopback-only, foreground). Buttons per session: open in Ghostty/Terminal, copy the resume command, or send to your phone |
| `aibox shell [cmd]` | zsh in the container, or run a one-off command |
| `aibox stop [--all]` | Stop this project's container (`--all`: everything incl. proxy). Loses nothing |
| `aibox status` | Containers with live memory + disk use, dev URLs, Docker disk totals, home volume size |
| `aibox backup [dir]` | Snapshot the home volume to a tar.gz |
| `aibox restore <file>` | Restore a backup (safety-backup of current state first) |
| `aibox update` | Update the CLI; image rebuilds automatically on next run |
| `aibox version` / `help` | Versions + docker state / this table's long form |

## Config

`~/.aibox/config` (key=value, all optional):

```
node_version=24        # base image: node:<this>-bookworm
proxy_port=80          # host port for the dev-server proxy
backup_dir=~/aibox-backups
```

The image is `node:<version>-bookworm` (Debian) plus a few basics (zsh, sudo, ripgrep, fzf, jq, less, procps, curl) — Claude apt-installs anything else on demand, and it persists across stop/start. To make custom tooling survive image rebuilds too, put extra Dockerfile lines in `~/.aibox/Dockerfile.extra`.

## Prerequisites

Built for macOS; works on Linux too. Needs Docker Engine 26+ (any 2024-or-later runtime; aibox checks and tells you if not). On macOS, Docker via [Colima](https://github.com/abiosoft/colima), [OrbStack](https://orbstack.dev), or [Docker Desktop](https://www.docker.com/products/docker-desktop/):

```bash
brew install colima docker && colima start
```

aibox auto-starts an installed-but-stopped runtime; it won't install one for you.

Note on the dev-server proxy port: the proxy asks Docker for `127.0.0.1:80` only, but some Colima versions ignore the loopback restriction and publish the port on your LAN. Everything behind it is your own sandboxed dev traffic, but if that matters to you, keep Colima current (or use OrbStack/Docker Desktop).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Design/requirements for v2 are in [REVAMP.md](REVAMP.md).

## License

MIT
