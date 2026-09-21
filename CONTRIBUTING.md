# Contributing

## Development

Clone the repo and use the script directly:

```bash
git clone https://github.com/blitzdotdev/aibox.git
cd aibox
./bin/aibox help
```

To test locally, symlink into your PATH:

```bash
ln -sf "$(pwd)/bin/aibox" /usr/local/bin/aibox
```

Dev-mode note: a checkout runs as version `dev`, so the image tag doesn't change between your edits — after modifying the embedded Dockerfile or entrypoint, force a rebuild with `docker rmi aibox:dev-node<version>` (releases bump the tag, so users get rebuilds automatically).

## Publishing

Publishing is fully automated. Pushing a version tag triggers CI which creates a GitHub release, publishes to npm, and updates the Homebrew tap.

```bash
# 1. Bump version in package.json, commit
# 2. Tag and push
npm run release
```

`npm run release` tags with the version from `package.json` and pushes the tag. CI (`.github/workflows/release.yml`) then:
- Creates a GitHub release with auto-generated notes
- Publishes to npm (`aibox-cli`)
- Updates `url` and `sha256` in [`blitzdotdev/homebrew-tap`](https://github.com/blitzdotdev/homebrew-tap)

### Version Bumps

1. Update `version` in `package.json`
2. Commit, then `npm run release` — CI handles the rest

Note: the Docker image tag is derived from the CLI version (`aibox:<version>-node<node_version>`), so any release automatically rebuilds users' images and recreates their containers on next run — sessions and login live in the `aibox-home` volume and are unaffected. In a git checkout (unstamped `__CLI_VERSION__`) the tag is `aibox:dev-node<version>`.

Two stamping caveats:
- The release workflow's sed must replace ONLY the `CLI_VERSION=` assignment — the script contains two more `__CLI_VERSION__` occurrences that are runtime dev-build sentinels and must survive stamping.
- The Homebrew formula installs from the raw git tag, which is unstamped. The tap formula should `inreplace` the same assignment during install; until it does, brew installs behave like dev builds (image `aibox:dev-*`, no update notice).
