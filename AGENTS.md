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

## The shape of the keymap

**34 keys: 3x5 plus two thumbs per side, and almost everything else is a combo.** Four layers
became three, six thumbs became four, and 43 combos absorbed the difference. The driver was that
multiple layers and a third thumb felt clunky after two years; the target is the 34-key Pocket
Keyboard being built, with the Cornes as transitional hardware carrying dead keys.

```
Base    Q W E R T / Y U I O P …        thumbs: Shift  Tab/Num │ Nav  Spc
Nav     arrows on hjkl                 nothing else
Num     numpad right, Tab/S-Tab thumbs
Admin   BT profiles, F-keys, media, sys_reset
```

Everything else — every modifier, Esc, Enter, Bspc, Del, the paging cluster, and every symbol
outside the numpad — is a combo. See `config/combos.dtsi`.

### Why modifiers are combos rather than home-row mods

A **vertical** combo is two keys in one column, so one finger covers both. Normal typing rolls
*across* columns, never down them, so a vertical pair cannot be triggered by accident — it is safe
by construction, with no timing to tune. That gives a modifier for roughly the cost of one
keypress, which is most of what home-row mods buy, without hold-tap timing and without colliding
with the combos that already sit on the home row.

Mods are mirrored and allocated by finger strength: index Ctrl, middle Gui, ring Alt, pinky Shift.
A consequence worth knowing: **a modifier cannot be used with a letter in its own column**, because
one finger would have to press both. That is why `Ctrl+V` and `Alt+X` have dedicated combos — V is
in Ctrl's column, X is in Alt's.

### Placing a new combo

- **Vertical pairs need no check.** Same column, same finger.
- **Horizontal pairs must be measured**: `python3 scripts/bigrams.py fg tg zx`. Under ~1.5 per 10k
  is safe; 1.5–6 has worked in practice (`d+s` at 5.9 never misfires); above 6 do not. The whole
  top row right of `y+u` is unusable — `io` is 30, `op` 34, `re` 144.
- **Skip-one pairs** have a risk the bigram misses: rolling through the key between them puts both
  down. Measure the three-key run, not just the pair.
- **The index finger owns two columns**, so `f+g`, `v+b` and their mirrors are one-finger
  horizontals and safe like verticals. Of the 26 one-finger pairs, 25 are taken and the last
  (`r+t`) is unusable at 38 per 10k. Anything further goes on a two-finger pair.

### Per-board adapters

`base.keymap` deliberately includes **no** key-labels header. Each board has a small entry keymap
that, in this order: optionally `#define CONFIG_WIRELESS` (enables the Bluetooth keys on Admin),
defines a `ZMK_BASE_LAYER(name, LT, RT, LM, RM, LB, RB, LH, RH)` macro placing the eight 34-key
blocks onto its physical grid, includes the matching key-labels header from
[zmk-helpers](https://github.com/urob/zmk-helpers), then `#include "base.keymap"`.

Labels are `LT0`–`LT4`, `LM0`–`LM4`, `LB0`–`LB4` and `LH0`–`LH1`, mirrored with `R`.
**Column `0` is the innermost (index), `4` the outermost (pinky).** A true 34-key board needs no
adapter — `base.keymap` has a pass-through fallback, and `draw/base34.keymap` is exactly that.

## Why all three Corne PCBs share one keymap

ZMK resolves the keymap by shield-name prefix (see `zmk/app/boards/post_boards_shields.cmake`):
`corne_left`, `corne_right` and the `corne_* nice_view_adapter nice_view` variants *all* resolve to
`config/corne.keymap`. Rather than fight that with `-DKEYMAP_FILE` overrides, all three build
against the default 42-key `foostan_corne_6col_layout`. On the 5-column boards the outer-column
switches physically don't exist, so those bindings are simply never triggered — and the outer
thumbs have been physically removed from every board, so `corne.keymap` pads in two directions.

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
| Outer columns / thumbs padding    | `config/corne.keymap` (`OUTER_T/M/B/TH`)    |
| Per-board physical mapping        | `config/<board>.keymap`                     |
| Handwired matrix / pins           | `config/boards/shields/handwired_corne/`    |
| Settings for all keyboards        | `config/nice_nano.conf`                     |
| Corne-only / nice!view-only       | `config/corne.conf`, `config/nice_view.conf`|
| Build targets                     | `build.yaml`                                |
| Keymap diagram styling / legends  | `draw/config.yaml`                          |
| Which keyboards get drawn         | `Justfile` (`keyboards` array in `draw`)    |
| Combo misfire risk                | `scripts/bigrams.py <pair>...`              |
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
   zmk-helpers' `36.h`.
3. Create `config/<name>.keymap`: `#define CONFIG_WIRELESS`, the matching key-labels header, then
   `#include "base.keymap"`. A 34-key board needs no `ZMK_BASE_LAYER` — the fallback covers it;
   anything larger needs the macro to pad.
4. Add `build.yaml` entries with `artifact-name`s, and an entry in the `keyboards` array of the
   `draw` recipe so it gets its own diagram.
5. Check the generated `.build/<target>/zephyr/zephyr.dts`: the `kscan` GPIOs, the transform's
   `columns`/`rows`/`col-offset`, and that the base layer has the expected number of bindings.
   That catches everything except whether the matrix matches the physical wiring, which only
   flashing can tell you.

## Home-row mods: considered and rejected

Not a future step — a decision. Vertical combos already give a one-finger modifier, so HRMs would
buy little, and **28 of the combos sit on home-row keys**, every one of which an HRM would overlap.
Making that work needs the hold-tap-inside-a-combo hack from
[urob's config](https://github.com/urob/zmk-config#timeless-homerow-mods). Not worth the risk here.

If that ever gets revisited, the structure still supports it: `KEYS_L` / `KEYS_R` / `THUMBS` come
from the per-board key-labels header, so positional trigger positions would adapt to every board
for free.
