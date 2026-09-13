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
uv pip install --python .venv/bin/python -r zephyr/scripts/requirements-base.txt west patool protobuf
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

just fmt          # re-align the key grids in the keymaps (--check to verify)
just debug <t>    # build <t> with USB logging, to debug matrix wiring
just settings-reset  # firmware that wipes stored BLE bonds
just studio <t>   # build <t> with ZMK Studio enabled (opt-in)
```

## ZMK Studio

Studio is realtime keymap editing with no reflash. It is **not** in the daily firmware — enable it
per-build:

```bash
just studio corne6_left      # -> firmware/corne6_left-studio.uf2
```

Only the *central* half (the left one) needs it; the peripheral holds no keymap. The artifact is
suffixed so it never overwrites the daily firmware.

Two things to know before leaning on it:

- **Studio writes to the device's settings, not this repo.** Nothing it changes appears in
  `base.keymap` or the diagrams, and `just settings-reset` wipes it. Treat it as a scratchpad: try
  a layout, then port what sticks back into `base.keymap`. Editing four keyboards independently in
  Studio throws away the single-source-of-truth this repo is built around.
- **Locking is disabled in this build.** The alternative is binding `&studio_unlock` to a key, but
  keymaps cannot see Kconfig symbols, so that binding would also have to exist in the normal
  firmware, where the behavior has a devicetree node but no driver behind it.

Studio needs `nanopb` for its protobuf RPC. Zephyr ships nanopb in its `optional` group, which its
own manifest disables, so `config/west.yml` pins it explicitly — and the build needs the `protobuf`
Python package in the venv (included in the setup above).

## Debugging

`just debug <target>` builds with ZMK's USB logging snippet. Flash a half, plug it in over USB and
attach a serial monitor:

```bash
screen /dev/tty.usbmodem* 115200      # ctrl-a k to quit
```

Every key press logs its matrix row, column and resolved key position. That tells apart the three
things that look identical from the keyboard:

| Symptom on press          | Cause                                          |
| ------------------------- | ---------------------------------------------- |
| nothing logged            | open circuit — switch, solder joint, or diode   |
| unexpected row/col        | wire landed on the wrong line                   |
| right row/col, wrong key  | matrix transform is wrong                       |

## Bluetooth pairing with more than one keyboard

ZMK has no per-keyboard identifier for split pairing: an unbonded central bonds to the first
peripheral it finds advertising the split service. With two identical 6-column boards powered on
together for their first pairing, the left half of one can bond to the right half of the other.

So bring up **one pair at a time** — keep the other keyboards powered off until the first has
bonded and is typing. The same applies to host pairing, since both 6-column boards advertise as
`adrian_corne_6`.

To recover from a bad bond: `just settings-reset`, flash `firmware/settings_reset.uf2` to **both**
halves, then flash the normal firmware back.

Flashing is drag-and-drop: double-tap reset on a half and copy the matching `.uf2` from `firmware/`
onto the USB mass-storage device. (`just flash` exists for boards without UF2 support; none of the
current targets need it.)

## Which firmware goes on which keyboard

| Keyboard                        | Firmware                                        |
| ------------------------------- | ----------------------------------------------- |
| 6-column Corne, no display (x2) | `corne6_left.uf2` / `corne6_right.uf2`          |
| 5-column Corne with nice!view   | `corne5_view_left.uf2` / `corne5_view_right.uf2`|
| handwired 5-column Corne        | `handwired_left.uf2` / `handwired_right.uf2`    |

The 6-column and nice!view builds share the same keymap; they differ only in the display support
compiled in, and the Bluetooth name so they can be told apart when pairing: `adrian_corne_6`,
`Corne View` and `adrian_corne_hw` respectively.
