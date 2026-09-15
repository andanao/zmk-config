# Spec: 34-key redesign

Migrate from 36 keys / 5 layers / 3 thumbs to 34 keys / 4 layers / 2 thumbs, with
modifiers on vertical combos. Driver: multiple layers and the third thumb have felt
clunky for over a year, and the next board (Pocket Keyboard, in progress) is 34 keys.

## Requirements

1. **Base becomes 34 keys** (3x5 + 2 thumbs). `config/base.keymap` uses
   `zmk-helpers/key-labels/34.h`. Adapters pad up: the 5-column boards gain a
   thumb-only adapter they don't have today; `corne.keymap` pads both outer
   columns and the third thumb.

2. **Thumbs**, outer pair dropped:

   | | left outer | left inner | right inner | right outer |
   |---|---|---|---|---|
   | now | `Esc`/`Alt` | `Shift` | `Lower` | `Space` |
   | after | `Shift` | `Tab`/`Num` | `Nav` | `Space` |

3. **Modifiers move to vertical combos**, mirrored, allocated by finger strength.
   A vertical pair is same-column/same-finger, so it cannot be rolled into
   accidentally:

   | | left | right | finger |
   |---|---|---|---|
   | Ctrl | `f+r` | `j+u` | index |
   | Gui | `d+e` | `k+i` | middle |
   | Alt | `s+w` | `l+o` | ring |
   | Shift | — | `;+p` | pinky |
   | Esc | `a+q` | — | pinky |

   `l_ctrl` and `r_ctrl` both emit `LCTRL`; the L/R distinction is meaningless here.

4. **Layers reduce to Nav, Num, Admin.** `Lower` and `Raise` dissolve. Their
   duplicated left hand existed only to reach a modifier while on a layer, which
   requirement 3 removes.
   - **Nav** (right thumb): arrows stay on `hjkl` positions — a decade of vim
     muscle memory, non-negotiable. Left hand keeps `PgUp/PgDn/Home/End`.
   - **Num** (left thumb): numpad on the right hand; the infrequent symbols
     (`! @ # $ % ^ \`) take the left hand, which is empty today.
   - **Admin**: unchanged except what moves out per requirement 6.

5. **Frequent symbols become combos.** Settled placements:

   | symbol | keys | shape | risk |
   |---|---|---|---|
   | `[` | `m+,` | horizontal | 0.8 / 10k |
   | `]` | `,+.` | horizontal | 0.3 / 10k |
   | `(` | `k+,` | vertical | safe by construction |
   | `)` | `l+.` | vertical | safe by construction |
   | `_` | `h+n` | vertical | safe by construction |

   Remaining frequent symbols (`{ } > & |`) need placement; see open questions.

6. **Per-half reset combos**, 5 keys each so they can't misfire:
   - left: `q + e + t + z + left inner thumb`
   - right: `y + i + p + / + right inner thumb`

   Reset behaviours run on the half where pressed, so each half resets alone.
   Combos are processed on the central, so the right-hand one still needs the
   halves connected. Remove `&bootloader`/`&sys_reset` from the Num layer once
   these exist — `D+S` then `W` is currently a live footgun.

7. **Delete `caps_word`.** Never used, and it is the only 4-key combo and the
   only subset-overlap with `r_ctrl`.

8. **Add a dedicated `Cmd+Space` combo.** The one Cmd shortcut worth a binding.

9. **Horizontal combos must be checked against bigram frequency** before being
   placed. `scripts/bigrams.py` (to be added) measures candidate pairs against
   ~6M chars of Adrian's own org/markdown. Empirical threshold: `ds` at 5.9 per
   10k works with no misfires; `io` at 30.1 and `op` at 34.5 are unusable. Verticals
   need no check.

10. **Diagrams and docs follow.** `just draw` regenerated; `AGENTS.md`'s home-row-mod
    migration section rewritten to describe combo-mods, which is the direction
    actually chosen.

## Non-goals

- **No home-row mods.** Vertical combos already give a one-finger modifier, and
  HRMs would collide with the 14-of-18 combos that touch the home row.
- **No changes outside `~/git/zmk-config`.** The AeroSpace workspace-letter
  bindings are a separate unit of work in a literate config repo; hand over the
  lines to paste instead.
- **6-column targets stay.** The boards exist and still build, they just leave
  the outer columns and third thumb unbound.
- **Not touching** the clipboard cluster (`c_x`/`c_c`/`c_v`), `Enter`/`Bspc`/`Del`
  combos, or arrow positions. All working, all load-bearing.

## Resolved

- **`.` on Num** replaces `+` at the inner bottom-right. Free: `+` is already the
  `n+m` combo, live on every layer. Same holds for `-` (`h+j`) and `*` (`y+u`),
  so Num's inner column duplicates combos throughout.
- **Reset combos emit `&bootloader`** — the flashing use case. `&sys_reset` stays
  on Admin.
- **`{ } > & |` go to the Num layer's left hand** with the other infrequent symbols.
- **Keypad codes normalise to plain** (`PLUS`, `MINUS`, `SLASH`, `ASTERISK`).
  `KP_` variants are distinct keycodes that Emacs and app shortcuts bind
  separately; nothing here wants them.
- **Volume/media stay on Admin.**

## Sequencing

Staged so each commit is flashable and any stage can be backed out:

1. **Add the mod combos** while the thumbs still exist. Purely additive, nothing
   lost, and it makes the one unverifiable thing — whether vertical mod combos
   feel right — testable before anything is removed.
2. Drop to 34 keys: remove the outer thumbs, rebase `base.keymap` on `34.h`, add
   the thumb adapters.
3. Dissolve `Lower`/`Raise` into `Nav`; move symbols onto Num's left hand.
4. Symbol combos, reset combos, `Cmd+Space`, delete `caps_word`, normalise keycodes.
5. Diagrams and docs.

## Done criteria

- `just build all` produces all six artifacts.
- `just fmt --check` passes; `just draw` regenerates cleanly and reproducibly.
- Every horizontal combo in `combos.dtsi` measures under 6 per 10k.
- Generated devicetree shows 34 bindings per layer in the base, correctly padded
  to 36 and 42 by the adapters.
- Adrian flashes and confirms the mod combos feel right — the one thing not
  checkable from here.

## Must not touch

- `~/git/konfig` and anything it tangles to, including `~/.config/aerospace/aerospace.toml`.
- No pushing to GitHub without explicit go-ahead.

## Standing constraints

- Extend `base.keymap` / `combos.dtsi` / the adapters; no parallel keymap.
- Simplest thing that works; no speculative behaviours.
- Logical commits, squashed on merge, messages describing the change.
- Never assert a frequency or count without measuring it.
