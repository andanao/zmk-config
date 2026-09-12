# Local build environment

`just` is the entry point for everything — run it with no arguments to list the recipes. It needs
`west` + the Zephyr SDK (to compile), and `keymap-drawer` + python-`yq` (to draw). There are two
ways to get those.

> You don't need either one just to get firmware: pushing to GitHub builds every target in
> `build.yaml` via `.github/workflows/build.yml` and attaches the `.uf2` files to the run.

## Option A — uv + Homebrew (no Nix)

This is what is currently set up on this machine, and what the build in this repo was verified
with. No `sudo`, nothing outside `$HOME` and Homebrew.

```bash
brew install just ninja dtc gperf cmake wget

# Tools that need to be on PATH
uv tool install --python 3.12 keymap-drawer
uv tool install --python 3.12 yq   # python-yq, NOT the Go `yq` — see `just _check_yq_version`

# A venv holding west + Zephyr's build-time Python dependencies
uv venv .venv --python 3.12
uv pip install --python .venv/bin/python -r zephyr/scripts/requirements-base.txt west patool
```

`west` lives in the venv, but you don't need to activate anything — the `Justfile` prepends
`.venv/bin` to `PATH` itself:

```bash
just init          # first time only: bootstraps the west workspace
just build all
```

Do **not** also `uv tool install west`. That gives you a second, bare `west` on `PATH` without
Zephyr's build dependencies, and whichever one wins the `PATH` race decides whether the build
works — the failure mode is a confusing `ModuleNotFoundError: No module named 'elftools'` partway
through. One `west`, in the venv.

The Zephyr SDK is a one-time download into `~/zephyr-sdk` (~1 GB for the ARM toolchain alone).
`west sdk` is an extension shipped by the `zephyr` repo, so this only works after `just init`:

```bash
source .venv/bin/activate   # needed here: this invokes west directly, not through just
west sdk install -t arm-zephyr-eabi --install-dir "$HOME/zephyr-sdk"
~/zephyr-sdk/setup.sh -t arm-zephyr-eabi -c   # registers the SDK with CMake; needs wget
deactivate
```

## Option B — Nix + direnv

Mirrors [urob/zmk-config](https://github.com/urob/zmk-config), which is what this repo is modelled
on. The upside is that `flake.lock` pins the Zephyr SDK, `west`, `keymap-drawer` and python-`yq` to
one continuously-tested combination, and the environment activates automatically on `cd`.

**The `flake.nix` / `flake.lock` / `nix/` files in this repo have not been exercised on this
machine** — Nix isn't installed here. They're a trimmed copy of urob's, which is CI-tested on Linux
and macOS, so they should work, but Option A is the verified path today.

1. Install Nix (needs `sudo`; creates the `/nix` APFS volume):

   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
   ```

2. Install [`direnv`](https://direnv.net/) and hook it into zsh:

   ```bash
   brew install direnv nix-direnv
   echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
   mkdir -p ~/.config/direnv
   echo 'source $(brew --prefix)/share/nix-direnv/direnvrc' >> ~/.config/direnv/direnvrc
   ```

3. From the repo root: `direnv allow` (slow the first time), then `just init`.

Bonus: installing Nix also makes the nix-darwin flake in `~/git/nix` usable again.

## Usage

```bash
just              # list all recipes
just list         # list build targets
just build all    # build every target into firmware/
just build view   # build only targets matching "view"
just build all -p # pristine rebuild (or `just clean`)
just draw         # regenerate draw/*.svg from the keymaps
just sync         # re-sync the workspace after editing config/west.yml
```

Flashing is drag-and-drop: double-tap reset on a half and copy the matching `.uf2` from `firmware/`
onto the USB mass-storage device. (`just flash` exists for boards without UF2 support; none of the
current targets need it.)

## Which firmware goes on which keyboard

| Keyboard                        | Firmware                                        |
| ------------------------------- | ----------------------------------------------- |
| 6-column Corne, no display (x2) | `corne6_left.uf2` / `corne6_right.uf2`          |
| 5-column Corne with nice!view   | `corne5_view_left.uf2` / `corne5_view_right.uf2`|
| handwired 5-column Corne        | not yet — see AGENTS.md                         |

The 6-column and nice!view builds share the same keymap; they differ only in the display support
compiled in, and the Bluetooth name (`adrian_corne_6` vs `Corne View`) so they can be told apart
when pairing.
