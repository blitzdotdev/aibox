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
- **One home volume, sliced per project.** Claude login, settings, and the `claude` binary live in shared slices of the `aibox-home` volume — log in once, forever. Everything else in a project's home (ssh keys, shell history, caches, and that project's sessions) is a private slice only its own containers mount, so one project's agent can't read another project's home directory or session transcripts. What *is* shared, because there is one login: Claude's settings and plugins (writable by every project, hooks included), the user-level CLAUDE.md, and Claude Code's own bookkeeping — the prompt history of every project (each prompt you typed, with its project path), snapshots of files Claude edited, todos, pastes. So an agent in one project can see what you *asked* in another (and those edit snapshots), but not the conversations or tool output. Two more things are common to all projects: `~/.local/bin`, where the `claude` binary lives and self-updates (writable by every project), and the Docker network, so one project's dev servers are reachable from another's container. A flat `aibox-home` volume (from `migrate-to-v2.sh`, or a pre-release v2) is re-sliced into this layout automatically on first run, with a safety backup taken first.
- **Nothing is destroyed implicitly.** Exiting Claude leaves the container running in the background (idle containers cost ~nothing) — the next `aibox` attaches instantly. `aibox stop` stops it; a stopped container keeps everything, including packages you apt-installed. Containers are only recreated when the image changes, and the home volume survives even that.
- **Sleep on battery works like native Claude.** Claude Code keeps a Mac awake while it works (it runs `caffeinate`), but only when it runs on the Mac itself; from inside a container it can't. aibox closes that gap: a hook in the container marks every prompt and tool call, and the `aibox` process on your Mac holds an idle-sleep assertion while the mark is under three minutes old — the same policy Claude applies natively. That covers sessions in an open `aibox` terminal; phone/browser sessions left running detached (`aibox serve`, `rc-resume`, on-start Remote Control) don't hold the Mac awake. Idle at the prompt, the Mac sleeps as usual; scheduled jobs hold it for their whole run; closing the lid sleeps regardless. (If the Mac does sleep mid-task nothing is lost: the VM pauses with it and the session resumes at wake, retrying the API call in flight.)
- **The container is the sandbox.** Full sudo inside. Permission prompts are on by default, but bypass mode is always available in-session (aibox passes claude's `--allow-dangerously-skip-permissions`); run `aibox --yolo` to start with all prompts skipped (`--dangerously-skip-permissions`).
- **Disposable copies on demand.** `aibox --copy` runs Claude in a fresh container on a *snapshot* of the project instead — nothing is bind-mounted, so the agent physically can't touch your real files. Same login and session history (shared home volume), own dev URLs (`<port>.<project>-copy.aibox.localhost`). The container is removed when the session exits; keep work by committing and pushing from inside. Each `--copy` run is its own independent sandbox. Combines with `--yolo`, and works for any program via `aibox run <prog> --copy`.

## Dev servers

Anything listening on any port inside the container is instantly reachable from your browser:

```
http://<port>.<project>.aibox.localhost
```

Claude starts `vite` on 5173 in project `myapp` → open `http://5173.myapp.aibox.localhost`. No ports to publish, no restarts, no config — a tiny shared Caddy proxy on the Docker network reaches any container port directly, WebSockets/HMR included.

Works out of the box in Chrome, Edge, and Firefox (`*.localhost` resolves to loopback natively). Safari needs macOS 26+. CLI tools like `curl` need `--resolve` (the system resolver doesn't do `*.localhost`). If host port 80 is taken, the proxy falls back to 8080 and URLs get `:8080`; `proxy_port` in the config picks any other port.

### GPU rendering

Containers have no GPU, so headless Chromium inside renders WebGL in software. For real GPU renders (WebGL/WebGPU screenshots of a three.js scene, say), run a Playwright browser server **on the Mac** and let sessions connect to it:

```bash
aibox browser          # runs the server in the foreground; prints the ws URL; Ctrl-C stops it
aibox browser setup    # update Playwright to latest (the first `aibox browser` sets up on its own)
```

The first run creates a hidden, unprivileged user with its own node and Playwright (it asks for sudo). The browser runs as that user, so it can read nothing of yours: it has its own group (`aibox-render`, not `staff`, so other accounts' homes are closed to it too), and setup closes your home directory to other local users. While it runs, every container sees the URL and Playwright version in a read-only file, `~/.aibox/host/browser.url`, and the shared CLAUDE.md tells sessions how to use it: matching client version, a `Host` header, one shared Chromium with a context per session, pages served over HTTP (your dev servers reach it through the proxy URL). When you stop it the URL is withdrawn, and Claude asks you to start it again when a render needs the GPU. macOS only.

aibox starts it with a plain `sudo -u render`. If Chromium can't start that way on your Mac, aibox says so and retries inside `render`'s launchd domain (`launchctl asuser`). Started that way, Chromium crashes whenever a page closes (the user has no display session), which drops every connected session; the server relaunches it on the same URL and keeps one page of its own open. If you see "browser exited" on its terminal, give `render` a display session once (`/var/render/README.md` has the command that sets a password; log that user in via Fast User Switching and switch straight back).

What a session gains access to through this, beyond what a container can already reach: a browser process on the Mac running as `render`, which can open `file://` for that user's own files and world-readable system files, and can browse anything the Mac can reach. It cannot touch your home, keychain, screen, or camera.

## Phone & browser sessions

```bash
aibox serve
```

runs a small sessions UI at `http://45789.<project>.aibox.localhost`. **New session** starts a fresh session you drive from claude.ai/code or the Claude phone app ([Remote Control](https://code.claude.com/docs/en/remote-control)); **Resume** brings any past session back the same way; live sessions show as such and can be stopped. Every session is one detached claude process inside the project's container — closing your terminal changes nothing, and registration is outbound-only HTTPS (no ports, nothing exposed). Any Claude session can pull the same tricks on request — the shared CLAUDE.md teaches it the commands, so you can also say "start me a new session" from your phone in any live chat. `aibox serve stop` ends the UI and every live session of this project. On a remote Linux box, reach the UI with `ssh -L 8080:127.0.0.1:80 host` and open the same URL with `:8080`; the phone side needs no tunnel at all.

## After a crash

If Docker's VM dies (a full Mac disk is the usual cause) or Docker restarts, every running session dies with it. The conversations are safe on disk, and

```bash
aibox recover
```

lists every session, across all projects, that was running at the time, and after you confirm, reopens each one with `--resume` in its own terminal window: the terminal you run it from if that's Ghostty, iTerm or Terminal, otherwise Ghostty if installed, else Terminal. Sessions that ran detached (`aibox serve`, `rc-resume`) come back detached, with Remote Control. `--rc` turns on Remote Control in the windows too, so you can carry on from the phone; `--detached` reopens everything without windows, as Remote Control sessions only; `--yes` skips the question; `--list` only lists; `--forget` drops the list. Sessions started with `--yolo` come back with it. The list shows which sessions were mid-task, but a reopened session waits for you; nothing is re-run on its own.

How it knows: hooks in the container keep one small file per running interactive session in `~/.aibox/inbox/<project>/.live/`, removed when the session exits normally (`/clear` and `/resume` update it). When a container starts, it moves the leftovers to `.live/cut/`; any `aibox` run then reminds you they're there. `aibox stop` clears its project's list, since stopping is deliberate. Headless runs (`-p`, scheduled jobs) and `--copy` sessions aren't tracked. This tracking starts once a project's container has been recreated with this version, which happens on the next `aibox` run when nothing is running in it.

## Scheduled jobs

```bash
cd myproject
aibox schedule add briefing "weekdays 08:00" claude routines/briefing.md   # a prompt file in the project
aibox schedule add tests "every 2h" run "npm test"
aibox schedule add chrome on-start run "chromium --headless --remote-debugging-port=9222"
aibox schedule            # list: next run, last result, proposals waiting
```

Every job runs **inside that project's sandbox**: `claude` entries as a fresh headless session reading the prompt file from stdin (`--permission-mode auto --permission-prompts none --max-turns 30`, so write the file to stand on its own), `run` entries as a one-line shell command. The host side is one launchd agent (macOS) or crontab line (Linux) that ticks every minute: a due job starts Colima and the container if they are down and holds the Mac awake until it finishes, a run missed while the Mac slept happens once at wake, and `on-start` entries re-launch once per container boot (dev servers, a headless browser, a Remote Control session), including after a reboot. Output goes to `~/.aibox/schedule.log`; a failed run shows a notification. Schedules: `daily HH:MM`, `weekdays HH:MM`, `every 30m` … `every 24h` (counted from local midnight), `on-start`.

Ask Claude in any session to "summarize my open PRs every weekday morning" and it writes a **proposal** (`~/.aibox/proposals/<name>` inside its container, which is a host-side inbox) — nothing runs until you approve it: a dialog on your Mac shows exactly what would run (Approve / Reject / Later), or `aibox schedule approve <name>`, and every aibox run prints a reminder while proposals wait. Approval is tied to the reviewed contents, names are unique across projects, containers cannot write the registry, the registry cannot express a host command, and `aibox schedule off` stops the ticker without forgetting the entries.

## Backup & restore

Everything worth keeping is in one volume, so backup is one file:

```bash
aibox backup                 # ~/aibox-backups/aibox-home-<ver>-<timestamp>.tar.gz
aibox backup /some/dir       # custom destination
aibox restore <backup.tar.gz> # replaces the volume (auto safety-backup first; containers are recreated, apt installs reset)
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
| `aibox recover [--rc] [--detached]` | Reopen every session a VM crash or Docker restart cut off, each in its own terminal window or detached with Remote Control. Lists them and asks first. See [After a crash](#after-a-crash) |
| `aibox browser [setup]` | GPU-backed Playwright browser server on the Mac that sessions connect to; foreground, Ctrl-C stops it (see [GPU rendering](#gpu-rendering)). macOS only |
| `aibox schedule [add\|rm\|approve\|reject\|on\|off\|log]` | Jobs that run inside project sandboxes on a schedule or on container start; no args lists them with next/last run and pending proposals. See [Scheduled jobs](#scheduled-jobs) |
| `aibox shell [cmd]` | zsh in the container, or run a one-off command |
| `aibox stop [--all]` | Stop this project's container (`--all`: everything incl. proxy). Loses nothing |
| `aibox status` | Containers with live memory + disk use, dev URLs, Docker disk totals, home volume size |
| `aibox backup [dir]` | Snapshot the home volume to a tar.gz |
| `aibox restore <file>` | Restore a backup (safety-backup of current state first; all containers are recreated, so apt-installed packages reset) |
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
brew install colima docker && colima start --cpu 4 --memory 8
```

Give the VM real memory: Colima's default is 2 GiB, shared by every container, and one forgotten headless browser or a couple of dev servers will starve Claude in it (it gets OOM-killed or hangs). Size it for your machine — e.g. `--memory 16` on a 24 GB Mac — and resize any time with `colima stop && colima start --memory N`. Docker's "legacy builder is deprecated" line during the image build is harmless; `brew install docker-buildx` (plus the symlink its install notes print) silences it.

Keep free space on the Mac's disk: the VM's disk image grows as containers write, and when the Mac's disk fills up, macOS stops the VM with every session in it. aibox warns when less than 20 GB is free. `docker system df` shows what Docker holds; `docker image prune -a` and removing old stopped containers free the most.

aibox auto-starts an installed-but-stopped runtime; it won't install one for you. If Colima says it's "already running" but Docker doesn't answer, its VM is stuck; aibox says so, and `colima stop -f && colima start` brings it back (containers and files are kept).

Note on the dev-server proxy port: the proxy asks Docker for `127.0.0.1:80` only, but some Colima versions ignore the loopback restriction and publish the port on your LAN. Everything behind it is your own sandboxed dev traffic, but if that matters to you, keep Colima current (or use OrbStack/Docker Desktop).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Design/requirements for v2 are in [REVAMP.md](REVAMP.md).

## License

MIT
