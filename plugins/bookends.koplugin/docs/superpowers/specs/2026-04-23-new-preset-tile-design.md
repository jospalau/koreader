# New preset tile — "My presets"

## Summary

Add a synthetic tile to the end of the "My presets" card list in the preset library. Tapping it creates a blank preset on disk, switches the active preset to it, and re-renders the modal so the user can start editing.

The tile participates in pagination as the `(N+1)`th item using the existing page math. When no presets exist, it appears alone on page 1 as a first-run onboarding affordance.

## Motivation

Today there is no UI path to create a preset from scratch. Every preset in the library is either shipped, imported from the Browse tab, or a copy of another preset. Users who want a blank canvas — especially during exploratory layout work, where the name only takes shape once the design does — have no way to get one.

An unused `_saveCurrentAsPreset()` function exists at `menu/preset_manager_modal.lua:788-817` but snapshots the running state, not a blank slate. This spec covers blank creation specifically; snapshot-of-current remains a separate (and currently unused) concern.

## Scope

### In scope

- A tappable tile rendered after the last local preset card, paginated as slot N+1.
- A new `_createBlankPreset()` method that writes a blank schema to disk, marks it active, and re-renders.
- An auto-naming helper that picks the next unused `Untitled` / `Untitled 2` / `Untitled 3` name.
- First-run state: when the user has zero presets, the tile stands alone on page 1 with the same tap behaviour.
- Two new i18n strings (`_("Untitled")` and `_("+ New preset")`) wired through the existing translation workflow.

### Out of scope

- Snapshot-of-current-state creation. The existing dormant `_saveCurrentAsPreset` can be wired up separately.
- Any change to the Browse tab.
- Renaming UX changes — the existing card rename flow handles later naming.
- Adding the blank preset to the preset cycle. A blank preset in the rotation would flash an empty overlay.

## Behaviour

### Tap flow

1. User taps the tile.
2. `_createBlankPreset()` runs:
   - Calls `_nextUntitledName()` to produce an unused name (see Naming below).
   - Builds the blank schema (see Schema below).
   - Persists via the existing `preset_manager.writePresetFile()` code path.
   - Sets the new preset as active via the existing active-preset setter.
3. The modal re-renders. The existing logic at `preset_manager_modal.lua:167` jumps the view to the page containing the active preset, which is now the new card.
4. The user taps the new card to begin editing, using the standard line-editor entry.

No confirmation dialog. No name prompt. Tapping once creates exactly one file.

### Pagination

The tile counts as the `(N+1)`th slot, where `N` is the number of local presets.

| Preset count | Page 1             | Page 2             | Page 3 |
|--------------|--------------------|--------------------|--------|
| 0            | [tile]             | —                  | —      |
| 1–4          | [cards…][tile]     | —                  | —      |
| 5            | [5 cards]          | [tile]             | —      |
| 6–9          | [5 cards][cards…][tile] | —             | —      |
| 10           | [5 cards][5 cards] | [tile]             | —      |

The tile is always the last item in the list. Pagination math requires no change: the renderer appends one extra synthetic slot to the list before the existing pager does its arithmetic.

### First-run

When `readPresetFiles()` returns an empty list, the tile is the only item on page 1. The label text is unchanged — `_("+ New preset")` — because the same affordance serves both cases.

## Naming

### Algorithm

```
candidates = ["Untitled", "Untitled 2", "Untitled 3", ...]
pick the first candidate whose display name does not collide
with any existing preset's name
```

- Collision check is against the `name` field of presets returned by `readPresetFiles()`, not against filenames. The existing `writePresetFile()` handles filename sanitisation.
- The bare `"Untitled"` is always tried first. If the user deletes an `Untitled`, the next create reclaims the bare name rather than skipping to `Untitled 2`.
- `Untitled` (the bare form and the stem) is passed through `_()` once. Numeric suffixes are appended in code: `_("Untitled")`, `_("Untitled") .. " 2"`, etc.

### Edge cases

- User has a preset named exactly `"Untitled"` that they manually created (unlikely but possible via rename): next create returns `"Untitled 2"`. Works naturally.
- Two rapid taps on the tile: the second tap sees the first preset on disk and picks `Untitled 2`. No collision.
- Deleting `Untitled 5` while `Untitled`, `Untitled 2`, `Untitled 3`, `Untitled 4` exist: the next create returns `Untitled 5` (first unused). Fine.

## Blank-slate schema

```lua
{
    name = "Untitled",            -- or "Untitled 2", etc.
    description = "",
    author = "",
    defaults = { ... },            -- deep copy of bookends_config defaults
    positions = {
        tl = { lines = {} },
        tc = { lines = {} },
        tr = { lines = {} },
        bl = { lines = {} },
        bc = { lines = {} },
        br = { lines = {} },
    },
    progress_bars = {},
}
```

Every position key is present (the loader expects all six, per `bookends_config.lua:22-29`) but every `lines` array is empty. `defaults` is a deep copy of the shipped defaults so the new preset opens with sensible margins, font sizes, etc.

`progress_bars`, `bar_colors`, and the tick multipliers are intentionally absent — they inherit from defaults through the existing preset-merge path.

## Visual

Reuses the existing card primitives to stay visually coherent with real cards:

- `FrameContainer` with the same border weight, radius, and 64px fixed height as existing cards (`preset_manager_modal.lua:618-786`).
- `InputContainer` wrapper with a `TapSelect` gesture calling `_createBlankPreset()`.
- Single centred text line: `_("+ New preset")`. No description row.
- No accent column — matches the blank spacer path at `preset_manager_modal.lua:774` (no star, no checkmark).

Preferred styling: **dashed border** to signal "this is an action slot, not a real preset". Fall back to a solid border (matching existing cards) if KOReader's `FrameContainer` doesn't expose a dashed-stroke option cleanly; investigate during implementation. Text styling is muted/secondary-weight where easy, otherwise default. The guiding constraint is that the tile should read as "part of the same surface" as real cards, not as a foreign UI element.

## Implementation surface

### New code

- `PresetManagerModal:_createBlankPreset()` — orchestrator. Generates a unique name, builds the schema, writes the file, sets active, re-renders.
- `PresetManagerModal:_nextUntitledName()` — collision-checked name picker. Pure helper.

### Modified code

- `PresetManagerModal:_renderLocalRows()` (`menu/preset_manager_modal.lua:497-569`) — append the synthetic tile row as the final card slot before pagination slicing.
- No changes to `preset_manager.lua` or `main.lua`. No changes to `bookends_config.lua`.

### External dependencies

None. The design uses only existing helpers: `readPresetFiles()`, `writePresetFile()`, the active-preset setter, and the modal's existing re-render path.

## i18n

Two new strings, added to `i18n/en.pot` then fanned out to every `i18n/*.po` via the existing translation workflow (same process as every prior user-facing string addition — update the `.pot`, mirror new entries into each `.po` with the language-appropriate translation or leave blank for later):

- `Untitled` — default name stem.
- `+ New preset` — tile label.

The numeric suffix (`" 2"`, `" 3"`) is appended in code, not translated, to avoid combinatorial explosion in `.po` files.

## Testing

Manual, on-device. No automated tests — the codebase has none for the preset-manager modal.

### Happy path

- Empty list → single `+ New preset` tile on page 1.
- 1–4 presets → tile sits below the last card on page 1.
- Exactly 5 presets → page 1 is full of cards, tile alone on page 2.
- 6+ presets → tile always last; pagination navigates cleanly to the page containing it.
- Tap → new `Untitled` card appears, becomes active, modal lands on the correct page.

### Naming

- Create twice → `Untitled`, `Untitled 2`.
- Delete `Untitled` then create → reclaims bare `Untitled`.
- Rename `Untitled` to `Minimal`, create again → `Untitled` again (not `Minimal 2`).
- Create ten times without deleting → `Untitled` through `Untitled 10`, all unique.

### Active-preset interaction

- Create → overlay immediately switches to the new blank preset. Since positions have no lines, the overlay is empty (expected).
- Switch to a different preset via the card tap → overlay re-populates as normal.
- Switch back to `Untitled` before adding any lines → still empty, no crashes.

### First-run

- Fresh install (zero presets) → tile shown alone on page 1. Tap → first preset created.

## Risks

- **Blank overlay on creation.** The moment the new preset becomes active, the overlay clears (no lines in any position). This is intentional but may surprise users the first time. Mitigation: users landing on the new card tap it to edit, and the empty state of the line editor is the expected starting point.
- **Accidental tap on the tile.** No confirmation dialog means misclicks create junk presets. Users clean up via the existing delete flow; the auto-naming ensures they don't overwrite anything. Tolerated.
- **Double-tap race.** Two taps in quick succession both read the same pre-create list and both pick `Untitled`. The second `writePresetFile()` call would overwrite the first. Mitigation: make `_createBlankPreset()` read-then-write synchronously (it already is — KOReader is single-threaded for UI handlers), and rely on the fact that the second call sees the first file on disk. If this turns out to flake, add a short in-memory lock.
