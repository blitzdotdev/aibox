# aibox

Instant sandbox containers for local files. One command to go from bare project to fully isolated Claude Code session.

AI agents need broad filesystem and network access to be useful — but giving that to an unsandboxed process on your host is risky. aibox runs each agent session inside a Docker container with your current directory bind-mounted in, so changes sync both ways while the agent stays sandboxed. Skip permission prompts safely, let agents run wild, tear everything down when you're done.

- **Zero config** — don't even need Docker installed. Detects your machine, auto-installs Colima/Docker, builds an Alpine image with Claude Code + dev tools, and sets up your project on first run
- **Safe by default** — network firewall (allowlisted domains only), restricted sudo, sensitive file detection (`.env`, credentials), disk space checks. `--yolo` to unlock everything
- **Full isolation** — `--copy` snapshots your repo into a Docker volume (works with or without git), `--worktree` creates a lightweight git worktree. Both handle uncommitted changes, submodules, and LFS automatically
- **Parallel agents** — run multiple named instances on the same project, each with its own container and optional isolation
- **Editor integration** — generates `compose.dev.yaml`, auto-configures JetBrains Node.js interpreter, forwards IDE plugin connections for VS Code and Cursor
- **Clone and run** — point at any git URL with `--repo` and aibox clones, sets up, and launches an agent session
- **Just a shell script** — no daemon, no runtime dependencies beyond Docker, easy to fork and customize

### tldr

```bash
cd myproject && aibox claude --yolo
```

That's the whole workflow. Docker handles the rest.

## Install

```bash
# npm
npm install -g aibox-cli

# brew
brew install blitzdotdev/tap/aibox
```

### Prerequisites

On macOS, if Docker isn't installed, aibox will offer to install [Colima](https://github.com/abiosoft/colima) + Docker via Homebrew automatically. It also works with [Docker Desktop](https://www.docker.com/products/docker-desktop/) or [OrbStack](https://orbstack.dev) if you already have them.

## Usage

```bash
# in any project directory
aibox up                    # start container (auto-builds image on first run)
aibox claude --yolo         # no prompts, full sudo, no firewall
aibox claude --safe         # keep prompts, restricted sudo, firewall on
aibox claude                # asks you each time
aibox claude --resume       # resume most recent conversation
aibox claude --print "explain this code"  # extra args passed to claude
aibox shell                 # zsh inside the container
aibox shell ls -la          # run a command inline
aibox down                  # stop and remove
```

### Named Instances

Run multiple containers for the same project:

```bash
aibox --name refactor claude --yolo
aibox --name tests claude --safe
aibox --name refactor down
```

### Isolated Instances

By default, named instances share the project directory via bind mount. For true isolation:

```bash
# Full isolation — copy into a Docker volume
aibox --name refactor --copy claude --yolo

# Lightweight — git worktree on host
aibox --name feat --worktree claude --yolo
```

`--copy` works with or without a git repo:
- **Git repo**: uses `git bundle` to clone tracked files (preserves history, excludes .gitignored files). Asks if you want to include uncommitted changes.
- **Git subfolder**: asks whether to copy the full repo or just the current folder. Folder-only copies use `git ls-files` to respect `.gitignore` while including uncommitted changes.
- **Non-git directory**: tars the folder (excluding `node_modules` and `.git`).

`--worktree` creates a `git worktree` at `~/.config/aibox/worktrees/`. Near-instant, shares remotes with the main repo. Requires a git repository. Asks if you want to include uncommitted changes.

Both create a new branch `aibox/<instance-name>` automatically. Submodules and Git LFS objects are initialized automatically when detected.

### Management

```bash
aibox status              # list all aibox containers
aibox volumes             # list copy volumes and worktrees
aibox down                # stop current container
aibox down --clean        # also remove copy volumes / worktrees
aibox down --all          # stop all containers for this project
aibox nuke                # remove ALL aibox containers
aibox version             # show version
```

### From a Git Repo

Start directly from a repo URL — aibox clones it and runs:

```bash
aibox --repo https://github.com/user/project.git claude --yolo
aibox --repo git@github.com:user/project.git --branch dev claude
```

Repos are cloned to `~/.config/aibox/repos/` with `--recursive` (submodules included). On subsequent runs, the existing clone is reused.

### Custom Image

```bash
aibox --image myteam/devbox:v2 up
aibox build --image custom:latest
```

## IDE Integration

aibox generates a `compose.dev.yaml` and configures your IDE on `aibox init` (or automatically on first `aibox up`).

### JetBrains (WebStorm, IntelliJ, etc.)

1. Install the [Claude Code plugin](https://plugins.jetbrains.com/plugin/claude-code)
2. Run `aibox init` in your project
3. Set the plugin's startup command to:
   ```
   aibox claude --yolo
   ```

The Node.js interpreter is also configured to use the container, so running/debugging from the IDE uses the same sandboxed environment.

### VS Code

1. Install the [Claude Code extension](https://marketplace.visualstudio.com/items?itemName=anthropic.claude-code)
2. Set the Claude Code startup command to `aibox claude --yolo`
3. Or use Dev Containers with the generated `compose.dev.yaml`

### Cursor / Windsurf / Other Editors

Set your agent's startup command to `aibox claude --yolo`. Works anywhere you can configure a shell command.

## Other Agents

The container ships with Node.js 20, git, git-lfs, ripgrep, zsh, python3, and build tools. Claude Code is pre-installed, but you can run anything:

```bash
aibox shell
# inside container:
aider
codex
# etc.
```

Customize the Dockerfile at `~/.config/aibox/Dockerfile`.

## How It Works

Run `aibox` from any project directory. It builds a lightweight Alpine container with Node.js, Claude Code, git, and dev tools, then bind-mounts your current directory into it. Changes sync both ways — edits inside the container appear on your host and vice versa. Authentication persists in a shared Docker volume across sessions.

**Two modes** control the security posture:

| | `--yolo` | `--safe` (default) |
|---|---|---|
| Permission prompts | Skipped | Kept |
| Sudo | Full | Restricted (chown only) |
| Network | Unrestricted | Firewall (allowlist only) |

The container is disposable — `aibox down` removes it completely. Your project files and auth survive.

## Network Firewall

In safe mode, outbound traffic is restricted to Claude API, npm, GitHub, PyPI, DNS, and SSH. Add extra domains:

```bash
export AIBOX_EXTRA_DOMAINS="example.com,api.myservice.io"
aibox claude --safe
```

## Config

Per-project settings in `.aibox`:

```
IMAGE=aibox:latest
SHARED_MODULES=false
```

## All Flags

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

## License

MIT
