<p align="center">
  <h1 align="center">aibox</h1>
  <p align="center"><strong>Instant Docker sandboxes for AI coding agents</strong></p>
  <p align="center">
    <a href="https://www.npmjs.com/package/aibox-cli"><img src="https://img.shields.io/npm/v/aibox-cli" alt="npm" /></a>
    <a href="https://www.npmjs.com/package/aibox-cli"><img src="https://img.shields.io/npm/dm/aibox-cli" alt="downloads" /></a>
    <a href="https://github.com/blitzdotdev/aibox/blob/main/LICENSE"><img src="https://img.shields.io/github/license/blitzdotdev/aibox" alt="license" /></a>
  </p>
</p>

<!-- TODO: Add a terminal recording (asciinema/VHS) demo GIF here showing `aibox claude --yolo` in action -->

> *Skip permission prompts safely. Let agents run wild. Tear everything down when you're done.*

```bash
cd myproject && aibox claude --yolo
```

One command to go from bare project to fully isolated Claude Code session. Changes sync both ways, the agent stays sandboxed, tear everything down when you're done.

## Quickstart

```bash
npm install -g aibox-cli    # 1. install
cd myproject                 # 2. go to your project
aibox claude --yolo          # 3. run
```

## Features

- **Zero config** — don't even need Docker installed. Detects your machine, auto-installs Colima/Docker, builds an Alpine image with Claude Code + dev tools on first run
- **Safe by default** — network firewall (allowlisted domains only), restricted sudo, sensitive file detection. `--yolo` to unlock everything
- **Full isolation** — `--copy` snapshots into a Docker volume, `--worktree` creates a git worktree. Both handle uncommitted changes, submodules, and LFS
- **Parallel agents** — run multiple named instances on the same project, each with its own container
- **Editor integration** — VS Code, Cursor, JetBrains, Windsurf — set startup command to `aibox claude --yolo`
- **Clone and run** — `--repo <url>` clones any git repo and launches an agent session
- **Not just Claude** — container ships with Node.js, python3, git, ripgrep, build tools. Run aider, codex, or anything else
- **Just a shell script** — no daemon, no runtime dependencies, easy to fork

## Install

```bash
npm install -g aibox-cli
# or
brew install blitzdotdev/tap/aibox
```

<details>
<summary><strong>Prerequisites</strong></summary>

On macOS, if Docker isn't installed, aibox will offer to install [Colima](https://github.com/abiosoft/colima) + Docker via Homebrew automatically. Also works with [Docker Desktop](https://www.docker.com/products/docker-desktop/) or [OrbStack](https://orbstack.dev).

</details>

## Usage

```bash
aibox up                    # start container (auto-builds image on first run)
aibox claude --yolo         # no prompts, full sudo, no firewall
aibox claude --safe         # keep prompts, restricted sudo, firewall on
aibox claude                # asks you each time
aibox claude --resume       # resume most recent conversation
aibox shell                 # zsh inside the container
aibox down                  # stop and remove
```

### Named instances

Run multiple containers for the same project:

```bash
aibox --name refactor claude --yolo
aibox --name tests claude --safe
aibox --name refactor down
```

### Isolation modes

| Mode | Flag | How it works |
|------|------|-------------|
| **Bind mount** | *(default)* | Live-sync project directory |
| **Copy** | `--copy` | Snapshot into Docker volume (git or non-git) |
| **Worktree** | `--worktree` | Lightweight git worktree on host |

Both `--copy` and `--worktree` auto-detect uncommitted changes, submodules, and Git LFS. Each creates a `aibox/<instance-name>` branch.

<details>
<summary><strong>Copy mode details</strong></summary>

- **Git repo** — uses `git bundle` to clone tracked files (preserves history, excludes .gitignored files). Asks to include uncommitted changes.
- **Git subfolder** — asks whether to copy the full repo or just the current folder.
- **Non-git directory** — tars the folder (excluding `node_modules` and `.git`).

</details>

<details>
<summary><strong>Worktree mode details</strong></summary>

Creates a `git worktree` at `~/.config/aibox/worktrees/`. Near-instant, shares remotes with the main repo. Requires a git repository. Asks to include uncommitted changes.

</details>

### Clone from URL

```bash
aibox --repo https://github.com/user/project.git claude --yolo
aibox --repo git@github.com:user/project.git --branch dev claude
```

Repos cached at `~/.config/aibox/repos/` with submodules included.

### Port forwarding

Forward ports from a running container to the host — no restart needed:

```bash
aibox port-forward 3000              # host:3000 → container:3000
aibox port-forward 8080:3000         # host:8080 → container:3000
aibox port-forward 3000 5173         # multiple ports
aibox port-forward --list            # show active forwards
aibox port-forward --stop 3000       # stop one
aibox port-forward --stop-all        # stop all
```

Uses a lightweight sidecar container (`alpine/socat`) on the same Docker network. Cleaned up automatically on `aibox down`.

### Management

```bash
aibox status              # list all aibox containers
aibox volumes             # list copy volumes and worktrees
aibox disk                # show disk usage breakdown
aibox clean               # clean everything (containers, volumes, images, sessions)
aibox clean --volumes     # only orphaned volumes
aibox clean --containers  # only stopped containers
aibox clean --sessions 7  # only session data older than 7 days (default: 30)
aibox clean --docker      # only dangling images + build cache
aibox clean --force       # skip confirmation
aibox doctor              # diagnose common issues
aibox down --clean        # also remove copy volumes / worktrees
aibox down --all          # stop all containers for this project
aibox nuke                # remove ALL aibox containers
```

Containers auto-stop when the last `claude` or `shell` session exits.

## Security modes

| | `--yolo` | `--safe` (default) |
|---|---|---|
| **Permission prompts** | Skipped | Kept |
| **Sudo** | Full | Restricted (chown only) |
| **Network** | Unrestricted | Firewall (allowlist only) |

In safe mode, outbound traffic is restricted to Claude API, npm, GitHub, PyPI, DNS, and SSH. Add extra domains:

```bash
export AIBOX_EXTRA_DOMAINS="example.com,api.myservice.io"
```

## IDE integration

<details>
<summary><strong>JetBrains (WebStorm, IntelliJ, etc.)</strong></summary>

1. Install the [Claude Code plugin](https://plugins.jetbrains.com/plugin/claude-code)
2. Run `aibox init` in your project
3. Set the plugin's startup command to `aibox claude --yolo`

Node.js interpreter is also configured to use the container.

</details>

<details>
<summary><strong>VS Code</strong></summary>

1. Install the [Claude Code extension](https://marketplace.visualstudio.com/items?itemName=anthropic.claude-code)
2. Set the Claude Code startup command to `aibox claude --yolo`
3. Or use Dev Containers with the generated `compose.dev.yaml`

</details>

<details>
<summary><strong>Cursor / Windsurf / Other editors</strong></summary>

Set your agent's startup command to `aibox claude --yolo`. Works anywhere you can configure a shell command.

</details>

## Other agents

The container ships with Node.js 20, git, git-lfs, ripgrep, zsh, python3, and build tools. Claude Code is pre-installed, but you can run anything:

```bash
aibox shell    # then run: aider, codex, etc.
```

Customize the Dockerfile at `~/.config/aibox/Dockerfile`.

## CLI reference

| Short | Long | Description |
|-------|------|-------------|
| `-n` | `--name NAME` | Named instance (multiple containers per project) |
| `-d` | `--dir PATH` | Run in a different project directory |
| `-r` | `--repo URL` | Clone a git repo and run in it |
| `-b` | `--branch NAME` | Branch to checkout (with `--repo`) |
| `-i` | `--image NAME` | Override base Docker image |
| `-c` | `--copy` | Copy project into Docker volume (full isolation) |
| `-w` | `--worktree` | Use git worktree (lightweight isolation) |
| `-y` | `--yolo` | Skip prompts, full sudo, no firewall |
| `-s` | `--safe` | Keep prompts, restricted sudo, firewall on |
| | `--shared-modules` | Share node_modules between host and container |
| | `--all` | With `down`: stop all project containers |
| | `--clean` | With `down`: also remove copy volumes / worktrees |
| | `--force` | With `clean`: skip confirmation prompts |

## Config

Per-project settings in `.aibox`:

```
IMAGE=aibox:latest
SHARED_MODULES=false
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
