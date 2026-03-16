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

### GitHub Release

```bash
git tag v0.1.0
git push origin v0.1.0
gh release create v0.1.0 --generate-notes
```

### npm

```bash
npm publish --access public
```

### Homebrew

1. Create a tap repo at `blitzdotdev/homebrew-tap` if it doesn't exist:
   ```bash
   gh repo create blitzdotdev/homebrew-tap --public
   ```

2. After creating a GitHub release, get the tarball sha256:
   ```bash
   curl -sL https://github.com/blitzdotdev/aibox/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
   ```

3. Copy `Formula/aibox.rb` into the tap repo, fill in the `sha256`, and push:
   ```bash
   # in the homebrew-tap repo
   mkdir -p Formula
   cp /path/to/aibox/Formula/aibox.rb Formula/
   # edit sha256, commit, push
   ```

Users can then install with:
```bash
brew install blitzdotdev/tap/aibox
```

### Version Bumps

1. Update `AIBOX_VERSION` in `bin/aibox`
2. Update `version` in `package.json`
3. Update `url` and `sha256` in `Formula/aibox.rb`
4. Commit, tag, release, publish npm, update tap
