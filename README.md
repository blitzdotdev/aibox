# aibox

Run AI coding agents in isolated Docker containers. Mount your project, skip permission prompts safely, run multiple instances in parallel.

## Install

```bash
# npm
npm install -g @blitzdev/aibox

# brew
brew install blitzdotdev/tap/aibox
```

### Prerequisites

Docker must be available. On macOS, aibox works with [Colima](https://github.com/abiosoft/colima) or [OrbStack](https://orbstack.dev). If Docker isn't installed, aibox will offer to install it via Homebrew.

## Usage

```bash
# first time (once)
aibox build

# in any project directory
aibox up                    # start container
aibox claude --yolo         # Claude Code, no permission prompts (sandboxed)
aibox claude --safe         # Claude Code, keep permission prompts
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

### Management

```bash
aibox status              # list all aibox containers
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
   /usr/local/bin/aibox claude --yolo
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
- **Auth**: A shared Docker volume persists Claude authentication across containers
- **Isolation**: Each project gets its own container and isolated `node_modules`
- **Safety**: Refuses to run in `$HOME`, `/tmp`, or other dangerous directories

## Config

Per-project settings in `.aibox`:

```
IMAGE=aibox:latest
SHARED_MODULES=false
```

## All Flags

| Flag | Description |
|------|-------------|
| `--name NAME` | Named instance (multiple containers per project) |
| `--image NAME` | Override base Docker image |
| `--shared-modules` | Share node_modules between host and container |
| `--yolo` | Skip permission prompts (no ask) |
| `--safe` | Keep permission prompts (no ask) |
| `--all` | With `down`: stop all project containers |

## License

MIT
