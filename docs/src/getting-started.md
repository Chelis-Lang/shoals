# Getting started

Shoals is a [Reef](https://github.com/Chelis-Lang/chelis) package. Work from a
**Shoals source checkout**: the commands below use `reef.toml` and the
executable tests in `tests/`. The package, compiler, and dependency versions
are declared in `reef.toml`.

## Install the pinned toolchain and dependencies

Install the pinned Chelis compiler and published package dependencies with an
authenticated [GitHub CLI](https://cli.github.com/). The
[Chelis installation guide](https://github.com/Chelis-Lang/chelis/blob/main/docs/book/src/install.md)
covers supported platforms.

```sh
gh auth login                      # once, if needed
gh release download --repo Chelis-Lang/chelis --pattern chelisup.sh --output - | sh
export PATH="$HOME/.chelis/bin:$PATH"
gh repo clone Chelis-Lang/shoals
cd shoals
chelisup install 0.18.13
chelis reef install --from-github chelis-lang/nautilus@v0.7.48
chelis reef install --from-github chelis-lang/coral@v0.7.45
chelis reef install --from-github chelis-lang/shoreleave@v0.1.0
chelis reef update --offline
chelis reef build
```

`chelisup install 0.18.13` installs the compiler pinned by `reef.toml`.
The three `reef install` commands fetch the published dependency artifacts;
`reef update --offline` records their exact versions and hashes in `reef.lock`.
`chelis reef build` checks Shoals and produces its Reef artifacts from that
locked graph. If you already have `chelisup`, begin with the clone and keep
the pinned compiler installation step. Run the remaining commands from the
checkout root.

## Price a call

The exported `Shoals.Pricing.bs_call_scalar` takes spot, strike, continuously compounded risk-free rate, volatility, and maturity in years, all as `f32`. It prices a European call on a non-dividend-paying underlying. This is the call in `tests/pricing.ch`:

```chelis
px = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
```

The expected price is approximately **10.4506**. Run its complete source test with:

```sh
chelis test tests/pricing.ch --filter test_bs_call_atm --timeout 120 --suite-timeout 180 --jobs 1
```

`tests/pricing.ch` imports the module, calls the pricer, and checks the result. The code above is an excerpt from that test; the command is the runnable example. The companion test `test_bs_put_atm` checks a put price of approximately 5.5735:

```sh
chelis test tests/pricing.ch --filter test_bs_put_atm --timeout 120 --suite-timeout 180 --jobs 1
```

To inspect the full exported API, start with [Pricing](pricing.md), then [Working with tensors and keys](conventions.md). These chapters distinguish standalone commands from excerpts that require the surrounding module and imports.
