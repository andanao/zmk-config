# Customization guide

How to work on this ZMK config — written for coding agents, but equally usable as a reminder to
future me. For toolchain setup see [docs/build-env.md](docs/build-env.md).

## Ground rules

- **Verify keymap changes by building.** `just build all` builds every target in `build.yaml`;
  `just build <expr>` builds the ones matching a substring (`just list` shows the targets).
  Compiled firmware lands in `firmware/`.
- **Regenerate the diagrams after any layout change**: `just draw`. The SVGs under `draw/` are
  committed, and CI (`.github/workflows/draw.yml`) will regenerate them anyway — but committing
  them yourself keeps the history clean.
- `config/west.yml` pins `zmk` and `zmk-helpers` by commit SHA. Bumping means editing the
  revision and running `just sync`; don't float them back to `main`.
- Pushing to GitHub builds every target through
  `.github/workflows/build.yml` (the stock `zmkfirmware/zmk` reusable workflow) — no local setup
  needed for a firmware artifact, just the Actions tab.

## How the multi-board layout works

`config/base.keymap` defines all five layers exactly once, for 36 keys (3x5+3), using the
standardized key labels from [zmk-helpers](https://github.com/urob/zmk-helpers): `LT0`–`LT4`,
`LM0`–`LM4`, `LB0`–`LB4` and `LH0`–`LH2` for the left top/middle/bottom rows and thumbs, mirrored
with `R` on the right. **Column `0` is the innermost (index finger), `4` the outermost (pinky).**
Combos (`config/combos.dtsi`) are written against these labels, so they adapt to any board
automatically.

`base.keymap` intentionally includes **no** key-labels header itself. Each board has a small entry
keymap that must, in this order:

1. optionally `#define CONFIG_WIRELESS` (enables the Bluetooth keys on the Admin layer),
2. define a `ZMK_BASE_LAYER(name, LT, RT, LM, RM, LB, RB, LH, RH)` macro placing the eight 36-key
   blocks onto the board's full physical grid, filling leftover keys with `&none` or extras,
3. include the matching key-labels header from zmk-helpers,
4. `#include "base.keymap"`.

A board with exactly 36 keys needs no adapter — `base.keymap` has a pass-through fallback.

## Why all three Corne PCBs share one keymap

ZMK resolves the keymap by shield-name prefix (see `zmk/app/boards/post_boards_shields.cmake`):
`corne_left`, `corne_right` and the `corne_* nice_view_adapter nice_view` variants *all* resolve to
`config/corne.keymap`. Rather than fight that with `-DKEYMAP_FILE` overrides, all three build
against the default 42-key `foostan_corne_6col_layout`. On the 5-column boards the outer-column
switches physically don't exist, so those bindings are simply never triggered.

The same cmake logic applies **every** matching `<shield>.conf`, not just the first — which is why
`config/nice_view.conf` can override the keyboard name for the nice!view board only, on top of the
shared `config/corne.conf`.

## Where to change what

| Change                            | File                                        |
| --------------------------------- | ------------------------------------------- |
| Layers, thumb keys                | `config/base.keymap`                        |
| Combos                            | `config/combos.dtsi` (position diagram at top) |
| Outer columns on 6-column boards  | `config/corne.keymap` (`OUTER_T/M/B`)       |
| Per-board physical mapping        | `config/<board>.keymap`                     |
| Shared Corne settings (BT, sleep) | `config/corne.conf`                         |
| nice!view-only settings           | `config/nice_view.conf`                     |
| Build targets                     | `build.yaml`                                |
| Keymap diagram styling / legends  | `draw/config.yaml`                          |
| Which keyboards get drawn         | `Justfile` (`keyboards` array in `draw`)    |
| ZMK / module versions             | `config/west.yml` (then `just sync`)        |

## Adding the handwired board

The handwired 5-column Corne needs a shield definition, because its matrix wiring doesn't match
foostan's. Once the pin mapping is known:

1. Create `config/boards/shields/<name>/` with `Kconfig.shield`, `Kconfig.defconfig`,
   `<name>.dtsi` (kscan matrix, physical layout, matrix transform) and
   `<name>_left.overlay` / `<name>_right.overlay`. ZMK warns that `config/boards` is deprecated in
   favour of a module; that's fine for a one-off shield, but a sibling module repo is the tidier
   long-term home.
2. Create `config/<name>.keymap` as a 36-key pass-through adapter:
   `#define CONFIG_WIRELESS`, `#include <zmk-helpers/key-labels/36.h>`, `#include "base.keymap"`.
   No `ZMK_BASE_LAYER` needed — the fallback covers it.
3. Create `config/<name>.conf` if it needs anything beyond the defaults.
4. Add two `build.yaml` entries (`<name>_left` / `<name>_right`) with `artifact-name`s.
5. Add `"<name>|-d config/boards/shields/<name>/<name>.dtsi"` to the `keyboards` array in the
   `draw` recipe so it gets its own diagram.

## Migrating to home-row mods

Deliberately not done yet. When the time comes it is a single edit to `config/base.keymap`:

```c
#define MAKE_HRM(NAME, HOLD, TAP, TRIGGER_POS)                                 \
  ZMK_HOLD_TAP(NAME, bindings = <HOLD>, <TAP>; flavor = "balanced";            \
               tapping-term-ms = <280>; quick-tap-ms = <175>;                  \
               require-prior-idle-ms = <150>; hold-trigger-on-release;         \
               hold-trigger-key-positions = <TRIGGER_POS>;)

MAKE_HRM(hml, &kp, &kp, KEYS_R THUMBS) // Left-hand HRMs.
MAKE_HRM(hmr, &kp, &kp, KEYS_L THUMBS) // Right-hand HRMs.
```

then swap the home-row `&kp` bindings for `&hml <mod> <key>` / `&hmr <mod> <key>`. Every board picks
it up automatically, because `KEYS_L` / `KEYS_R` / `THUMBS` come from the per-board key-labels
header. No extra modules are required — `require-prior-idle-ms` and `hold-trigger-on-release` are
both upstream ZMK. See [urob's write-up](https://github.com/urob/zmk-config#timeless-homerow-mods).
