# Customization guide

How to work on this ZMK config — written for coding agents, but equally usable as a reminder to
future me. For toolchain setup see [docs/build-env.md](docs/build-env.md).

## Ground rules

- **Verify keymap changes by building.** `just build all` builds every target in `build.yaml`;
  `just build <expr>` builds the ones matching a substring (`just list` shows the targets).
  Compiled firmware lands in `firmware/`.
- **Keep the key grids aligned**: `just fmt` re-aligns the `ZMK_BASE_LAYER` blocks so the source
  stays laid out like the keyboard. CI runs `just fmt --check`. It deliberately skips any row it
  can't group confidently (the Admin layer's `_BT_SEL_KEYS_`), so hand-align those.
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

The handwired board is the exception: it has its own shield, and therefore its own
`config/handwired_corne.keymap`, with no collision. Its name deliberately does *not* start with
`corne_` — shield-name prefixes are matched by stripping `_`-separated suffixes, so a shield called
`corne_hw_left` would also match `config/corne.conf` and inherit the wrong keyboard name.

## How the .conf files layer

ZMK applies **every** matching `<shield>.conf`, not just the first, and then the `<board>.conf`,
in that order — later files win. So:

| File                       | Applies to                        | Holds                          |
| -------------------------- | --------------------------------- | ------------------------------ |
| `config/nice_nano.conf`    | everything (all boards are nice!nano) | sleep, BT power            |
| `config/corne.conf`        | all three Corne PCBs              | `adrian_corne_6` name          |
| `config/nice_view.conf`    | nice!view builds only             | overrides name to `Corne View` |

The handwired board takes its name from its shield's `Kconfig.defconfig` instead, since nothing
overrides it. Keep `nice_nano.conf` to genuinely universal settings — being merged last, it would
silently beat any per-shield override.

## Where to change what

| Change                            | File                                        |
| --------------------------------- | ------------------------------------------- |
| Layers, thumb keys                | `config/base.keymap`                        |
| Combos                            | `config/combos.dtsi` (position diagram at top) |
| Outer columns on 6-column boards  | `config/corne.keymap` (`OUTER_T/M/B`)       |
| Per-board physical mapping        | `config/<board>.keymap`                     |
| Handwired matrix / pins           | `config/boards/shields/handwired_corne/`    |
| Settings for all keyboards        | `config/nice_nano.conf`                     |
| Corne-only / nice!view-only       | `config/corne.conf`, `config/nice_view.conf`|
| Build targets                     | `build.yaml`                                |
| Keymap diagram styling / legends  | `draw/config.yaml`                          |
| Which keyboards get drawn         | `Justfile` (`keyboards` array in `draw`)    |
| ZMK / module versions             | `config/west.yml` (then `just sync`)        |

## Adding another board

`config/boards/shields/handwired_corne/` is the worked example — a custom shield for hardware ZMK
doesn't know about. The steps:

1. Create `config/boards/shields/<name>/` with `Kconfig.shield`, `Kconfig.defconfig`, `<name>.dtsi`
   (kscan matrix + matrix transform + chosen physical layout) and
   `<name>_left.overlay` / `<name>_right.overlay` carrying the per-half GPIOs. Pick a name that
   isn't a suffix-extension of an existing one, per the `.conf` layering above. ZMK warns that
   `config/boards` is deprecated in favour of a module; fine for a one-off, but a module is the
   tidier long-term home.
2. Reuse a stock physical layout if one fits rather than hand-writing `key_physical_attrs`.
   `<layouts/foostan/corne/5column.dtsi>` is exactly 3x5+3 per half and its key order matches
   zmk-helpers' `36.h`, which is why the handwired board needs no adapter at all.
3. Create `config/<name>.keymap`: `#define CONFIG_WIRELESS`, the matching key-labels header, then
   `#include "base.keymap"`. A 36-key board needs no `ZMK_BASE_LAYER` — the fallback covers it.
4. Add `build.yaml` entries with `artifact-name`s, and an entry in the `keyboards` array of the
   `draw` recipe so it gets its own diagram.
5. Check the generated `.build/<target>/zephyr/zephyr.dts`: the `kscan` GPIOs, the transform's
   `columns`/`rows`/`col-offset`, and that the base layer has the expected number of bindings.
   That catches everything except whether the matrix matches the physical wiring, which only
   flashing can tell you.

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
