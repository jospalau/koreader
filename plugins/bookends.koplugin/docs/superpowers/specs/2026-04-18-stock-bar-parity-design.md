# Stock KOReader status-bar parity — design

## Motivation

GitHub comment on koreader/koreader#15235 notes that bookends, while useful, does not cover all items in KOReader's built-in status bar — specifically calling out the *page-turning inverted* indicator. An audit of `frontend/apps/reader/modules/readerfooter.lua` confirms one genuinely missing feature (page-turn direction) plus small gaps in annotation-count granularity, picker visibility, and glyph availability.

Goal: close every meaningful gap so a user migrating from the stock bar can reproduce it 1-to-1, and document the mapping so the parity is discoverable.

## Scope

In scope:

1. New token `%V` — page-turn direction indicator.
2. New conditional state key `invert` — truthy when any page-turn direction is flipped.
3. New token `%X` — total annotations (bookmarks + highlights + notes), matching stock's `bookmark_count` generator.
4. Expose existing `%M` (RAM in MiB) in the token picker — already implemented, undocumented.
5. Add three missing glyphs to the icon picker: `⥖`, `⤻` (chapter-time-to-read), `💡` (frontlight warmth).
6. New README section "Coverage of KOReader's stock status bar" with full mapping table.

Out of scope:

- `dynamic_filler` — bookends' six-zone positional model makes this unnecessary.
- `additional_content` — this is a plugin-extension hook with no 1-to-1 analogue; the overlay itself serves this role via free-form format strings.
- `custom_text` — the overlay content is already free-form text; no separate token needed.
- Changes to existing tokens' semantics.

## Architecture

Additive only — no new modules, no changes to existing module boundaries. Three files touched:

| File | Change |
|------|--------|
| `tokens.lua` | Extend `state` table with `invert` key; extend `replace` table with `%V` and `%X`; gated by `needs()`. |
| `menu/token_picker.lua` | Surface `%V`, `%X`, `%M` in `TOKEN_CATALOG`; add `[if:invert=yes]...[/if]` to `CONDITIONAL_CATALOG` examples and reference. |
| `icon_picker.lua` | Add three glyph rows: `⥖` and `⤻` under Arrows, `💡` under Device. |
| `README.md` | Add collapsible "Coverage of KOReader's stock status bar" section with mapping table. |

No changes to `main.lua`, `overlay_widget.lua`, `preset_manager.lua`, `line_editor.lua`, `dialog_helpers.lua`, `utils.lua`, `config.lua`, `updater.lua`, `i18n.lua`, `_meta.lua`, or any other menu file.

## Components and data

### `%V` — page-turn direction

**Expansion rule:** `⇄` (U+21C4) if any of four flags is truthy, otherwise empty string.

**Four-flag OR (matches stock's logic exactly, readerfooter.lua:379):**

```lua
local G = G_reader_settings
local inverted =
       G:isTrue("input_invert_page_turn_keys")
    or G:isTrue("input_invert_left_page_turn_keys")
    or G:isTrue("input_invert_right_page_turn_keys")
    or (ui.view and ui.view.inverse_reading_order)
```

**Rationale for empty-when-normal:** matches bookends' existing convention for `%B` and `%W` — dynamic tokens render only when their state is noteworthy. Users who want always-present dual-state behaviour can write `[if:invert=yes]⇄[else]⇉[/if]`.

**Guard:** computed only when `needs("V")` is true, or when `invert` appears as a conditional key (see next component).

### `invert` — conditional state key

Added to the `state` table in `tokens.lua` (currently around lines 133–137 alongside `batt`, `charging`, `light`).

**Value:** `"yes"` when the four-flag OR is truthy, else `"no"`. String form is consistent with `charging`, `light`, `wifi` — parser handles `[if:invert=yes]`, `[if:invert=no]`, and truthy `[if:invert]` automatically.

**Computed:** once per paint, in the shared condition-state build. Leverages the existing per-paint cache (commit `51e867e`) — no duplicate work if the same state is read by multiple `Tokens.expand` calls in one paint.

### `%X` — total annotations

**Expansion rule:** `tostring(ui.annotation:getNumberOfAnnotations())`, nil-safe (if `ui.annotation` is absent for any reason, return `""`).

**Behaviour:**
- `%X` is the sum — matches stock `bookmark_count`.
- `%x` (bookmarks), `%q` (highlights), `%Q` (notes) retain existing semantics.
- Included in `always_content` so the token counts as content even when it resolves to `"0"` — consistent with how `%c`, `%t`, `%p` etc. behave.

**Guard:** gated by `needs("X")`.

### Picker additions (`menu/token_picker.lua`)

In `TOKEN_CATALOG`:

- **Metadata** category: add `{ "%X", _("Total annotations (all bookmarks, highlights, notes)") }`.
- **Device** category: add `{ "%V", _("Page-turn direction (shows when inverted)") }` and `{ "%M", _("RAM used (MiB)") }`.

In `CONDITIONAL_CATALOG`:

- **Examples**: `{ "[if:invert=yes]⇄[/if]", _("Show arrows when page-turn direction is flipped") }`.
- **Reference**: `{ "[if:invert=yes]...[/if]", _("invert — yes / no (page-turn direction)") }`.

### Icon picker additions (`icon_picker.lua`)

Under the **Arrows** category:

- `{ "\xE2\xA5\x96", _("Left harpoon with right arrow") }` — U+2956
- `{ "\xE2\xA4\xBB", _("Curved back arrow") }` — U+293B

Under the **Device** category:

- `{ "\xF0\x9F\x92\xA1", _("Lightbulb emoji") }` — U+1F4A1

### README — coverage section

New collapsible `<details>` block placed after the Conditionals section, before Installation. Title: *"Coverage of KOReader's stock status bar"*.

Preamble (one sentence):
> Bookends covers the same information as KOReader's built-in status bar, often with finer granularity. This table maps each stock footer item to the bookends token(s) that produce the same information.

Table (abbreviated — full list in implementation):
- Page/chapter progress items → `%c %t %g %G %p %P %L %l`
- Time items → `%k %K %h %H`
- Device items → `%b %B %W %f %F %m %M`
- Metadata items → `%T %A %C %C1-9 %x %q %Q %X`
- Page-turn direction → `%V`, conditional `invert`

Footer note:
> Bookends' six-zone positioning model replaces stock's `dynamic_filler` layout and `additional_content` plugin hook — those aren't separate tokens because the overlay itself fills that role.

## Data flow

Token-expansion flow (unchanged from current architecture):

1. User edits format string via line editor → saved to settings.
2. On paint, `main.lua` calls `Tokens.expand(format_str, ui, session_elapsed, session_pages, ...)`.
3. `tokens.lua` builds `state` table once per paint (cached for same-paint repeat calls).
4. Conditional pre-processor evaluates `[if:...]` blocks using `state`.
5. Token substitution replaces `%X` patterns from `replace` table.
6. Symbol-color wrapping applied post-expansion.
7. `overlay_widget.lua` renders result.

New plumbing: zero. Both new tokens and the new conditional key slot into steps 3 and 5.

## Error handling

- `ui.annotation` may be nil in rare bootstrapping windows — guard with `ui.annotation and ui.annotation:getNumberOfAnnotations() or 0`.
- `G_reader_settings:isTrue(...)` returns false for nil values, so missing keys are safe.
- `ui.view.inverse_reading_order` is nil-checked (`ui.view and ui.view.inverse_reading_order`).
- No new exception paths. Existing `pcall` wrappers in `tokens.lua` not needed for these additions — all operations are already safe.

## State invalidation

Three scenarios reviewed:

1. **Per-book `inverse_reading_order` toggled mid-session.** Writes to `ui.view.inverse_reading_order` in memory. Next page turn triggers repaint; `state.invert` recomputes from live value. ✓ works.
2. **Global `input_invert_*_keys` toggled via settings or dispatcher.** Writes to `G_reader_settings`. No automatic overlay repaint. Overlay stays stale until next paint-triggering event (page turn, gesture). *Acceptable*: the setting is a hardware-button binding you toggle and then use — the usage itself re-paints. Document as "updates on next interaction" if anyone notices.
3. **Annotation added/removed while `%X` is rendered.** `getNumberOfAnnotations()` is a live read per paint; no cache. Annotation add/remove paths already trigger reader repaint. ✓ works.

No new event subscriptions required.

## Testing

No automated test suite exists in this repo. Manual validation follows the standard workflow: `luac -p` lint → SCP push to Kindle → load book → verify.

| Check | Method | Expected |
|---|---|---|
| `%V` absent by default | Fresh book, default settings | Empty render |
| `%V` responds to `inverse_reading_order` | Reader menu → Settings → Taps & gestures → Invert page turn direction | `⇄` appears on next paint |
| `%V` responds to hardware-key invert | Toggle via Device > Keys menu (or `input_invert_page_turn_keys`) | `⇄` appears on next paint |
| `[if:invert=yes]...[else]...[/if]` branch selection | Same toggles | Branch flips correctly |
| `%X` equals sum | 2 bookmarks + 1 highlight → `%X` = 3, `%x` = 2, `%q` = 1 | Arithmetic holds |
| `%M` visible in picker | Open token picker → Device category | `%M` row present with MiB label |
| New icons visible in picker | Open icon picker → Arrows / Device | `⥖`, `⤻`, `💡` present |
| Unused-token zero cost | Add `print` in `invert` branch, verify fires only when `%V` or `invert` is in format string | Gated correctly |

## Release notes

Single bundled entry:

> Full coverage of KOReader's stock status bar — new `%V` (page-turn direction), `%X` (total annotations), and `%M` (RAM in MiB, previously undocumented) tokens, an `invert` conditional key, and three new glyphs in the icon picker.

## Commit plan

Per the established dev workflow: iterate on a `feature/stock-bar-parity` branch with small commits, squash before tagging.

Final squashed commit message:

> `feat: full coverage of KOReader stock status bar tokens`

Branch cut from `master` at `51e867e` (current `origin/master`). No dependency on the parked `feature/bluetooth-status` branch.
