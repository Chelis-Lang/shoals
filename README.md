# Shoals

Quantitative finance shell for the
[Chelis](https://github.com/Chelis-Lang/chelis) programming language.
Ships as a reef package under the `Shoals` module prefix.

## Toolchain

Pinned to `chelis v0.1.3` in `reef.toml`:

```toml
compiler = "=0.1.3"
```

## Build

Download and extract the pinned tarball, then run check on the sources:

```sh
gh release download v0.1.3 \
  --repo Chelis-Lang/chelis \
  --pattern 'chelis-v0.1.3-linux-x86_64.tar.gz'
tar xzf chelis-v0.1.3-linux-x86_64.tar.gz
./chelis-v0.1.3-linux-x86_64/chelis check src/core.ch
```

CI authenticates to the sibling private `Chelis-Lang/chelis` releases via
the repo secret `CHELIS_RELEASE_TOKEN` (a PAT with `contents: read`).

## License

MIT
