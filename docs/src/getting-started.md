# Getting started

Shoals is a [Reef](https://github.com/Chelis-Lang/chelis) package. Work from a
**Shoals source checkout**: the commands below use `reef.toml` and the
executable tests in `tests/`. The package, compiler, and dependency versions
are declared in `reef.toml`.

## Install the pinned toolchain and dependencies

Install the pinned Chelis compiler and published package dependencies. The
[Chelis installation guide](https://github.com/Chelis-Lang/chelis/blob/main/docs/book/src/install.md)
covers supported platforms and `chelisup` setup.

```sh
git clone https://github.com/Chelis-Lang/shoals.git
cd shoals
chelisup install 0.19.0
```

Install the Nautilus, Coral, and Shoreleave release tags declared in
`reef.toml` with `chelis reef install --from-github`, passing each exact tag
as `chelis-lang/<name>@v<version>`. Then lock and build:

```sh
chelis reef update --offline
chelis reef build
```

`chelisup install 0.19.0` installs the compiler pinned by `reef.toml`.
Install each published dependency release declared in `reef.toml` with
`chelis reef install --from-github chelis-lang/NAME@vVERSION` before updating.
`reef update --offline` records their exact versions and hashes in `reef.lock`.
`chelis reef build` checks Shoals and produces its Reef artifacts from that
locked graph. Run the commands from the checkout root.

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
