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

Note: `AIBOX_VERSION` in `bin/aibox` is separate — it tracks the Docker image format and only needs bumping when the Dockerfile or entrypoint changes (triggers automatic image rebuild for users).
