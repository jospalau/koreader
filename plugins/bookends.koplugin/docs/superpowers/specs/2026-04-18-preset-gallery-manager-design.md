# Preset Gallery + Unified Preset Manager — design

## Motivation

Bookends' preset experience today is fragmented: a nested menu split into "Built-in presets" (three read-only bundled configs) and "Custom presets" (the user's saved `.lua` files in `bookends_presets/`). Users share presets informally (forum posts, gists), with no discovery or one-click install. A long-press gesture updates a custom preset with the current overlay — powerful but undiscoverable.

This feature consolidates preset UX into a single central-aligned modal ("Preset Manager") that replaces the existing menus and adds an online **Gallery** tab for browsing community presets from a GitHub-hosted catalog. Presets become "documents": applying one *opens* it for autosave, so overlay tweaks flow back to the preset file without an explicit save step.

## Scope

**In scope:**

1. New **Preset Manager modal** — central-aligned widget, tabbed Local / Gallery.
2. **Autosave editing model** — applying a preset makes it "active"; overlay edits write back to its file automatically.
3. **Virtual "(No overlay)" row** — star-able, cycle-includable, renders a blank overlay. Makes the existing `.blank` workaround unnecessary.
4. **Gallery tab** — fetches a GitHub-hosted `index.json`, lists remote presets, previews/installs on tap. Offline-graceful.
5. **Schema extensions** — optional `description` and `author` fields on preset files.
6. **Removal of `BUILT_IN_PRESETS`** — the three bundled presets go away; they can be downloaded from the gallery if wanted.
7. **"Basic bookends" starter preset** — single bundled preset, auto-provisioned on first run when `bookends_presets/` is empty.
8. **New gallery repo** — `AndyHazz/bookends-presets`, a static repo with `index.json` + `presets/*.lua`.
9. **New star-based cycle model** — cycle membership is explicit per preset (persisted list of filenames plus a sentinel for the blank slot).

**Out of scope:**

- Star ratings / votes. Schema reserves the slot; no collection mechanism this release.
- In-app submission flow. Contributors raise GitHub PRs manually via the gallery repo's instructions.
- Search, filter, tags in the Gallery list. Straight sorted list for v1.
- Per-book preset auto-switching.
- Thumbnails or screenshots — live preview renders on the user's own screen, so these aren't needed.

## Architecture

Two loosely-coupled pieces shipping together:

**Plugin-side (this repo):**

| File | Role |
|------|------|
| `preset_manager.lua` (existing) | Extend validator (description/author). Add `activePreset()`, `setActivePreset()`. Rename cycle settings. |
| `menu/preset_manager_modal.lua` (new, ~400 LOC) | The central modal UI. Tabs, rows, preview/install flow, overflow menu. |
| `preset_gallery.lua` (new, ~200 LOC) | HTTP + cache + index parsing. Public: `fetchIndex`, `downloadPreset`, `getCachedIndex`, `isOnline`. |
| `menu/presets_menu.lua` (existing) | Shrinks to a single entry that opens the modal. Sub-menus removed. |
| `main.lua` | Delete `BUILT_IN_PRESETS` (~80 LOC). Add `onFlushSettings` autosave hook, `onOpenPresetManager` event, virtual "(No overlay)" cycle handling, rewrite `onCycleBookendsPreset` to use the star list. First-run provisioning. Migration code. |
| `config.lua` | Add `preset_cycle`, `active_preset_filename`, `preset_manager_tip_shown` (first-time hint flag) to persisted settings whitelist. |
| `i18n.lua` / `.po` | New strings. |
| `basic_bookends.lua` (new, bundled asset) | Shipped-with-plugin minimal starter preset. |
| `README.md` | Rewrite Presets section; document Gallery relationship and autosave. |

**Repo-side (new, separate):**

| Path | Role |
|------|------|
| `AndyHazz/bookends-presets/index.json` | Catalog (schema version, updated-at, preset list). |
| `AndyHazz/bookends-presets/presets/<slug>.lua` | Preset files in the existing bookends preset format. |
| `AndyHazz/bookends-presets/README.md` | Contribution guide + schema link. |

No backend, no server, no GitHub Pages — raw content served from `raw.githubusercontent.com`.

## Components

### Preset Manager modal

Central-aligned, ~90% screen width/height (matching font picker proportions).

**Layout:**

```
┌────────────────────────────────────────────────┐
│ Preset Manager                [Local][Gallery] │  ← title + tabs
├────────────────────────────────────────────────┤
│ Currently editing: Rich Detail                 │  ← active preset (always shown if one is active)
│ Previewing: Minimalist                    [⋯]  │  ← preview state + contextual overflow (Personal only)
├────────────────────────────────────────────────┤
│ + Save current as preset                       │  ← Local tab, first row
│ ☆  (No overlay)                                │  ← virtual row, star-able
│ ★  Basic bookends — starter                    │
│ ☆  Rich Detail — andyhazz                      │
│ ★  My tweaks — me                              │
│ ...                                            │
├────────────────────────────────────────────────┤
│ [ ‹ ] [ › ]     Page 1 of 2                    │  ← pagination
├────────────────────────────────────────────────┤
│ [ Close ]                           [ Apply ]  │  ← footer (context-sensitive Apply/Install)
└────────────────────────────────────────────────┘
```

**Row tap zones:**

- **Star (★/☆)** on the left (~40px tap target): toggles cycle membership, no preview. Personal + virtual-blank only.
- **Rest of row**: previews the preset — applies to live settings, updates header, modal stays open.

**Button row:**

- `[ Close ]` — if previewing, revert live to the modal-open snapshot and close. Otherwise just close.
- `[ Apply ]` — only active when previewing. Label changes: **"Apply"** for Local, **"Install"** for Gallery.

**⋯ menu** (in header, only when previewing a Personal preset):

- Rename…
- Edit description…
- Duplicate
- Delete

No "Update with current overlay" — autosave handles it.

### Autosave editing model

**Semantics:** Personal presets behave like documents. "Applying" a preset opens it. While open, overlay changes write back to the preset file automatically.

**Mechanism:**

- Setting: `active_preset_filename` (string, persisted). Nil = no preset open.
- Flag: `_previewing` (in-memory, transient). True when the modal has applied a preset in preview mode.
- Hook: `onFlushSettings` — when KOReader flushes settings, bookends also serializes the current overlay config and writes to `bookends_presets/<active_preset_filename>` *unless* `_previewing` is true.
- Piggybacks on normal settings flush — no new per-setting instrumentation.

**Lifecycle:**

- User applies Rich Detail → `active_preset_filename = "rich_detail.lua"`. Live settings loaded from the file.
- User tweaks font size → normal settings flush → autosave writes the new config to `rich_detail.lua`.
- User opens manager, previews Minimalist → `_previewing = true`, live settings replaced with Minimalist's contents (in memory). Autosave skips.
- User taps Close → live settings restored from modal-open snapshot, `_previewing = false`. Autosave resumes with Rich Detail as target.
- User taps Apply on Minimalist → live settings kept, `active_preset_filename = "minimalist.lua"`, `_previewing = false`. Autosave now targets Minimalist.

### Virtual "(No overlay)" row

- Displayed in Local tab, positioned just below "+ Save current as preset".
- Not a file — synthesized in the UI layer.
- Preview/Apply: clears all position `lines` arrays (empty content) without touching fonts/defaults. Active preset = nil.
- Star-able. Cycle can include or skip it; when included, cycling hits a blank overlay state.
- Cannot be renamed or deleted (⋯ menu hidden when previewing).
- Cycle membership tracked via a `_empty` sentinel in the `preset_cycle` array.

### Gallery data layer (`preset_gallery.lua`)

**Public API:**

```lua
Gallery.fetchIndex(callback)         -- async: callback(index_table or nil, err)
Gallery.downloadPreset(slug, cb)     -- async: callback(preset_data or nil, err)
Gallery.getCachedIndex()             -- sync: cached index or nil
Gallery.getCacheTimestamp()          -- sync: os.time() of last successful fetch, or nil
Gallery.isOnline()                   -- sync: NetworkMgr:isWifiOn() and isConnected()
```

**HTTP:** mirrors `updater.lua` — LuaSocket with curl fallback, `KOReader-Bookends/<version>` user-agent.

**URLs:**

- Index: `https://raw.githubusercontent.com/AndyHazz/bookends-presets/main/index.json`
- Preset: `https://raw.githubusercontent.com/AndyHazz/bookends-presets/main/<preset_url-from-index>`

**Cache:**

- Dir: `<settings_dir>/bookends_gallery_cache/`
- `index.json` stored as-is, timestamp in sibling `index.timestamp`.
- TTL: 24h (after which stale-cache UI shows a refresh banner).
- Downloaded preset files are NOT cached on disk — they're either installed (written to `bookends_presets/`) or discarded on Close.
- In-memory session cache of downloaded preset data keyed by slug (prevents re-download on same-session re-preview).

### "Already installed" indicator on Gallery rows

Gallery row is marked with a `✓` prefix when **any** Local preset file's `name` field matches the Gallery entry's `name`. Match on `name`, not slug — users often rename locally, so slug-matching would give false negatives. This is a visual hint only; the install path still runs the full collision dialog (Overwrite / Rename / Cancel) so the user can confirm intent.

### Index schema

```json
{
  "schema_version": 1,
  "updated": "2026-04-18T18:20:00Z",
  "presets": [
    {
      "slug": "rich-detail",
      "name": "Rich Detail",
      "author": "andyhazz",
      "description": "Clock, battery, stats — the full kitchen sink",
      "added": "2026-04-18",
      "preset_url": "presets/rich-detail.lua"
    }
  ]
}
```

`preset_url` is relative to the repo root so the gallery repo can restructure internally without changing the live URL.

### Preset file schema additions

Extend `EXPECTED_TYPES` in `preset_manager.lua:validatePreset`:

```lua
local EXPECTED_TYPES = {
    name                  = "string",
    description           = "string",  -- new, optional
    author                = "string",  -- new, optional
    enabled               = "boolean",
    defaults              = "table",
    positions             = "table",
    progress_bars         = "table",
    bar_colors            = "table",
    tick_width_multiplier = "number",
    tick_height_pct       = "number",
}
```

Missing fields remain accepted (matches current forward-compat policy). Existing Personal presets are unaffected.

### Basic bookends starter preset

Bundled as `basic_bookends.lua` in the plugin dir. Provisioned into `bookends_presets/` on first run if the dir is empty.

**Content:**

```lua
-- Bookends preset: Basic bookends
return {
    name = "Basic bookends",
    description = "Minimal starter — page number and clock",
    author = "bookends",
    enabled = true,
    positions = {
        bc = { lines = { "Page %c of %t" } },
        tr = { lines = { "%k" } },
    },
    -- defaults inherit
}
```

Set as `active_preset_filename` on provisioning. Added to `preset_cycle`.

### Star-based cycle model

- Setting: `preset_cycle` — array of strings. Filenames (for Personal presets) or `"_empty"` (for the virtual blank row). Order preserved = insertion order (starring adds to the end). Reorder UI deferred to v2.
- `onCycleBookendsPreset`: flushes current settings first (so unsaved overlay tweaks autosave to the *departing* preset), then reads `preset_cycle`, finds current position based on `active_preset_filename`, advances to next. If current is `"_empty"` or not in list, starts from index 1.
- Virtual blank handling: when cycle hits `"_empty"`, clear position lines (same effect as Apply on the virtual row) and set `active_preset_filename = nil`.
- Editing cycle membership happens via the star toggle in the manager — no separate "Add to cycle" dialog.
- **Flush-before-cycle is critical**: without it, very-recent overlay edits that haven't reached their next scheduled flush would be overwritten when the next preset loads.

## Data flow

### Local preset apply

1. User taps row in Local tab → `preview(preset_data)`: live settings replaced in memory, `_previewing = true`.
2. User taps **Apply** → `setActivePreset(filename)`, `_previewing = false`. Autosave now targets the new preset.
3. User edits overlay (font size, etc.) → `onFlushSettings` fires → autosave writes current config back to file.

### Gallery preset install

1. User opens Gallery tab → `Gallery.fetchIndex()` (first open only per session). Shows list.
2. User taps row → `Gallery.downloadPreset(slug)` → preset data fetched, validated, applied as preview.
3. User taps **Install** → collision check against Local presets:
   - No collision: `writePresetFile(name, data)`, `setActivePreset(new_filename)`.
   - Collision: prompt Overwrite/Rename/Cancel, then proceed.
4. `_previewing = false`. Autosave engaged.

### Autosave flow

1. User tweaks setting (font size, position, tick width, etc.) in any menu.
2. Setting flushed via KOReader's normal settings persistence.
3. Bookends' `onFlushSettings` hook: if `active_preset_filename` is set AND `_previewing == false`, build a preset table from current live settings and call `writePresetContents(path, name, preset_data)`.

### Cycle gesture

1. User triggers cycle gesture.
2. `onCycleBookendsPreset` reads `preset_cycle`, finds next entry after `active_preset_filename`.
3. Either applies the preset file (load + set active) or clears positions (for `"_empty"` sentinel + nil active).
4. Notification shows the new preset name (existing behaviour).

## Error handling

| Scenario | Handling |
|---|---|
| No WiFi, no cache, Gallery tab opened | Empty state: *"Gallery requires an internet connection"* + [Retry] |
| No WiFi, cache exists | Cached list + banner: *"Offline — showing cached list"* |
| Index fetch fails (5xx, timeout) | If cache: show cached + banner "Could not refresh". If no cache: empty state + Retry. |
| Index JSON malformed | Log to crash.log, show empty state: *"Gallery data is temporarily unavailable"* |
| Preset download fails | Toast: *"Couldn't download '<name>'. Check connection and try again."* Preview doesn't activate. |
| Preset validates as nil | Toast: *"This preset appears invalid; skipping."* Log reason. |
| Install name collision | Dialog: Overwrite / Rename… / Cancel. |
| Disk write fails (disk full, permissions) | Toast: *"Couldn't save preset. <reason>"* Preview reverts. |
| Autosave write fails | Silent log (not toasted on every flush). Retries on next flush. |
| Active preset file deleted externally (sideloaded delete) | On next autosave, re-creates the file. Idempotent. |
| Preset file corrupted on load during cycle | Skip to next cycle member; notification: *"Preset '<name>' couldn't be loaded; skipping."* |

No new failure paths can crash the overlay. All errors degrade to readable UI + log + continue.

## Migration

One-time, idempotent, run on plugin init guarded by a `preset_manager_migration_done` flag.

1. **Rename `last_cycled_preset` → `active_preset_filename`**: if the former is set, look up a matching Personal preset filename (not the human name), set `active_preset_filename`, delete `last_cycled_preset`.
2. **Seed `preset_cycle`**: if unset, populate with all existing Personal preset filenames (preserves current implicit-all-cycle behaviour).
3. **First-run "Basic bookends" provisioning**: if `bookends_presets/` is empty, copy the bundled starter in. Set as active + add to cycle.
4. Set the `preset_manager_migration_done` flag to skip on subsequent runs.

Built-in presets (Rich Detail, Speed Reader, Classic Alternating) are *not* seeded into the user's Personal dir on upgrade. Users who had one applied retain its contents (already in live settings). Users who want those presets as files can download them from the gallery.

## Documentation

**`README.md` changes** in the plugin repo:

- Replace the current "Presets" section with a new one describing:
  - Preset Manager as the single entry point
  - Local vs Gallery tabs
  - Autosave behaviour ("edits write back automatically — no save step")
  - Star-based cycle model
  - Link to `AndyHazz/bookends-presets` for browsing online

**`AndyHazz/bookends-presets/README.md`**:

- File format reference (link to plugin's preset schema section).
- Contribution instructions: add `presets/<slug>.lua`, add entry to `index.json`, raise PR.
- Author-credit policy (keep it simple: just a string; no identity verification).

**Release notes**:

> New **Preset Manager** — a single central modal for browsing, previewing, starring for the cycle, and creating presets. Live preview applies any preset to your overlay before you commit. A new online **Gallery** lets you browse community presets, installed with one tap. Overlay edits now autosave to the active preset — no separate save step.

## Testing

Manual only — no test suite. Five buckets:

1. **Local tab basics**: open modal → rows render → star persists → + saves snapshot → preview/revert works → Apply commits → autosave persists overlay edits after close.
2. **Gallery tab basics**: tab-switch fetches index once → preview downloads + applies → Install saves + makes active → collision prompt works.
3. **Offline paths**: WiFi off + fresh install (empty state), WiFi off + cached (cached + banner), mid-session WiFi loss doesn't crash.
4. **Migration**: upgrade with (a) no local presets, (b) local presets only, (c) `last_cycled_preset` set, (d) no existing active overlay — all must produce coherent state.
5. **Edge cases**: delete active preset (next Local becomes active; if none, virtual blank becomes active), star virtual blank and cycle (blank state hit), preview a Gallery preset already installed (✓ indicator), close during preview reverts cleanly.

## Commit plan

Branch: `feature/preset-manager` from master. Iterative commits during development; squash before tagging. This is a large enough change to justify tagging a new release on merge (unlike the prior two features which we deferred).

Final squashed commit message:

> `feat: unified Preset Manager with Gallery browser and autosave editing`

The separate `bookends-presets` repo is seeded at the same time, with at minimum the three old built-ins (Rich Detail, Speed Reader, Classic Alternating) and Basic bookends so users migrating find something familiar in the Gallery from day one.
