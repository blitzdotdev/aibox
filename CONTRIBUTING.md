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

Publishing is automated. When you create a GitHub release, CI publishes to npm and updates the Homebrew tap automatically.

```bash
git tag v0.3.0
git push origin v0.3.0
gh release create v0.3.0 --generate-notes
```

This triggers `.github/workflows/release.yml` which:
- Publishes to npm (`aibox-cli`)
- Updates `url` and `sha256` in [`blitzdotdev/homebrew-tap`](https://github.com/blitzdotdev/homebrew-tap)

Users install with:
```bash
brew install blitzdotdev/tap/aibox
```

### Version Bumps

1. Update `AIBOX_VERSION` in `bin/aibox`
2. Update `version` in `package.json`
3. Commit, tag, and create a GitHub release — npm and brew are updated automatically
