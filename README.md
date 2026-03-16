# aibox

Run AI coding agents in isolated Docker containers. Mount your project, skip permission prompts safely, run multiple instances in parallel.

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
# first time (once)
aibox build

# in any project directory
aibox up                    # start container
aibox claude --yolo         # no prompts, full sudo, no firewall
aibox claude --safe         # keep prompts, restricted sudo, firewall on
aibox claude                # asks you each time
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

By default, named instances share the project directory. For true isolation:

```bash
# Full isolation — copy repo into a Docker volume
aibox --name refactor --copy claude --yolo

# Lightweight — git worktree on host
aibox --name feat --worktree claude --yolo
```

`--copy` uses `git bundle` to clone tracked files into a volume (excludes .gitignored files, preserves history). Changes stay inside the container until pushed. Best for automation and parallel agents.

`--worktree` creates a `git worktree` at `~/.config/aibox/worktrees/`. Near-instant, shares remotes with the main repo. Best for feature branches and quick experiments.

Both create a new branch `aibox/<instance-name>` automatically.

### Management

```bash
aibox status              # list all aibox containers
aibox volumes             # list copy volumes and worktrees
aibox down                # stop current container
aibox down --clean        # also remove copy volumes / worktrees
aibox down --all          # stop all containers for this project
aibox nuke                # remove ALL aibox containers
```

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
   npx aibox claude --yolo
   ```

The Node.js interpreter is also configured to use the container, so running/debugging from the IDE uses the same sandboxed environment.

### VS Code

1. Install the [Claude Code extension](https://marketplace.visualstudio.com/items?itemName=anthropic.claude-code)
2. Set the Claude Code startup command to `aibox claude --yolo`
3. Or use Dev Containers with the generated `compose.dev.yaml`

### Cursor / Windsurf / Other Editors

Set your agent's startup command to `aibox claude --yolo`. Works anywhere you can configure a shell command.

## Other Agents

The container ships with Node.js 20, git, ripgrep, zsh, python3, and build tools. Claude Code is pre-installed, but you can run anything:

```bash
aibox shell
# inside container:
aider
codex
# etc.
```

Customize the Dockerfile at `~/.config/aibox/Dockerfile`.

## How It Works

- **Build**: Creates a Docker image with Node.js, Claude Code, and dev tools
- **Up**: Starts a container with your project bind-mounted
- **Claude**: Opens Claude Code inside the container, optionally skipping permission prompts
- **Modes**: `--yolo` gives full access; `--safe` enables firewall + restricted sudo
- **Auth**: A shared Docker volume persists Claude authentication across containers
- **Isolation**: Each project gets its own container and isolated `node_modules`
- **Safety**: Refuses to run in `$HOME`, `/tmp`, or other dangerous directories

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
| `-i` | `--image NAME` | Override base Docker image |
| `-c` | `--copy` | Copy repo into Docker volume (full isolation) |
| `-w` | `--worktree` | Use git worktree (lightweight isolation) |
| `-y` | `--yolo` | Skip prompts, full sudo, no firewall |
| `-s` | `--safe` | Keep prompts, restricted sudo, firewall on |
| | `--shared-modules` | Share node_modules between host and container |
| | `--all` | With `down`: stop all project containers |
| | `--clean` | With `down`: also remove copy volumes / worktrees |

## License

MIT
