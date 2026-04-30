# Bookends Library Modal — design

## Motivation

Bookends has three discoverable user journeys that all live on different UI substrates today:

| Journey | Substrate | Issue |
|---|---|---|
| Pick a preset | `menu/preset_manager_modal.lua` (custom modal, ~1,800 lines) | Works well, but the chrome is bespoke and not reused. |
| Pick a status-bar icon | `bookends_icon_picker.lua` (KOReader Menu wrapper, ~280 lines) | Surfaces only ~70 curated glyphs. The bundled font ships ~3,700 — preset authors who want a specific Nerd Font glyph have to manually edit the saved file. |
| Pick a token or conditional | `menu/token_picker.lua` (KOReader Menu wrapper, ~260 lines) | Conditionals are buried inside a sub-menu (`If/Else conditional tokens →`). Browsing tokens is OK at current scale but doesn't scale. |

The first journey already proves the modal substrate works (tabs, sort chips, per-row info, paginated list, footer actions). The other two are stuck on stock Menu and can't grow comfortably.

This feature unifies the three pickers onto a shared modal substrate (`BookendsLibraryModal`) and adds a name-based search affordance to all of them. The motivating preset PR (#36 by `logwet`, where the author hand-edited PUA codepoints into their preset file) goes away once the icon picker can search 3,700 named glyphs by typing.

## Scope

**In scope:**

1. New shared widget `BookendsLibraryModal` lifted from the chrome of the existing preset manager modal. Tabs (optional), search input (mandatory, above chips), chip strip (optional, with two-row wrap when needed), paginated result area (list mode OR grid mode, configurable per-domain), footer action buttons.
2. Three sibling modals consuming the shared widget:
   - **Preset library** — refactored from existing `preset_manager_modal.lua` to consume `BookendsLibraryModal` instead of containing the chrome inline. List mode.
   - **Icons library** — new modal replacing `bookends_icon_picker.lua`. Grid mode (4 columns at Paperwhite width, 3 on narrower devices).
   - **Tokens library** — new modal replacing `menu/token_picker.lua`. Conditionals migrate from sub-menu to an `If/else` chip on the Tokens chip strip. List mode.
3. Submit-then-show search: user types a query, taps Search, modal repaints with filtered results. Search input persists for refinement.
4. Uniform two-line row template across the list-mode modals (presets, tokens); preset rows additionally use a right-edge installed-flag and a top-right corner colour-flag (preserved as-is). Icons render as a glyph + label grid (cells, not rows).
5. Build-time data deliverable for icon search: `tools/build_nerdfont_names.py` script + generated `bookends_nerdfont_names.lua` data file (~3,700 glyph-name → codepoint pairs intersecting KOReader's bundled `nerdfonts/symbols.ttf`).
6. Deletion of the legacy `IconPicker.showPickerMenu` wrapper and its callers.
7. Preserve all existing preset-modal behaviours during refactor: tabs (My presets / Gallery), sort chips per tab (Latest/Starred for My presets; Latest/Popular for Gallery), gallery empty-state help panel, refresh-on-chip-tap when stale, install ✓ flag, colour 🎨 flag, overflow actions on long-tap, footer Close / Manage… / Install.

**Out of scope:**

- Universal/cross-domain search palette ("type anywhere, find anything"). Per-domain modals only.
- Live filter as the user types. Submit-then-show only — Kindle keyboard latency makes live-filter feel chaotic.
- Preset-card layout changes. The card structure is preserved bit-for-bit; only the surrounding modal chrome is generalised.
- Token catalog content changes. Existing token entries and their categories carry over verbatim. No new tokens, no token renames.
- Conditional catalog content changes. Existing conditionals carry over.
- Auto-fetch of upstream `glyphnames.json` during build. The script accepts a path argument; the maintainer downloads the file once and re-runs as needed.
- CI/automation. Build script is run-on-demand from the maintainer's laptop; the generated `.lua` is committed.
- Visual companion / browser mockups. Designed entirely against KOReader's existing widget toolkit.

## Architecture

One new shared widget, one new data file, one new build script, three thinned-down domain modules.

| File | Change |
|---|---|
| `menu/library_modal.lua` | **New.** The shared `BookendsLibraryModal` widget. Provides chrome (header, optional tabs, optional chip strip, search input, paginated row list, footer). Parameterised by per-domain configuration table. |
| `menu/preset_manager_modal.lua` | **Refactored.** Becomes a thin wrapper that builds a domain config and instantiates `BookendsLibraryModal`. All chrome rendering moves to the shared widget. Preset-specific row renderer, gallery empty-state panel, per-tab chip strips, and footer actions remain as preset-domain config. |
| `menu/icons_library.lua` | **New.** Builds the icons domain config; instantiates `BookendsLibraryModal`. Wires up the line editor's icon-picker entry. |
| `menu/tokens_library.lua` | **New.** Builds the tokens domain config; instantiates `BookendsLibraryModal`. Wires up the line editor's token-picker entry. Includes the `If/else` chip that scopes the result list to conditionals. |
| `bookends_icon_picker.lua` | **Deleted.** Functionality replaced by `menu/icons_library.lua`. Callers updated. |
| `menu/token_picker.lua` | **Deleted.** Functionality replaced by `menu/tokens_library.lua`. Callers updated. |
| `bookends_line_editor.lua` | Updated. Two call sites swap from old picker entry points to new modals. |
| `main.lua` | Updated. Removes `require("menu.token_picker")(Bookends)` registration. |
| `bookends_nerdfont_names.lua` | **New, generated.** Pure data: alphabetised array of `{name, code}` pairs. ~3,700 entries, ~150KB. Loaded lazily by the icons modal when the search input is submitted. |
| `tools/build_nerdfont_names.py` | **New.** Build script. CLI: `--symbols-ttf <path>` (defaults to `/usr/lib/koreader/fonts/nerdfonts/symbols.ttf`), `--glyphnames-json <path>` (required). Reads font cmap, intersects with upstream JSON, writes the `.lua` data file sorted alphabetically by name. |

## Components

### `BookendsLibraryModal` (`menu/library_modal.lua`)

The shared chrome widget. Receives a domain config and renders accordingly.

**Domain config shape:**

```lua
{
    title              = "Icons library",       -- header text
    tabs               = nil,                   -- or { {key="local", label="My presets"}, ... }
    on_tab_change      = function(tab_key) ... end,
    chip_strip         = function(active_tab)   -- returns chips for current tab
        return {
            { key="all",      label="All",      is_active=is_active },
            { key="dynamic",  label="Dynamic",  is_active=is_active },
            ...
        }
    end,
    on_chip_tap        = function(chip_key) ... end,
    search_placeholder = function()             -- dynamic count baked in
        return T(_("Search %1 icons by name…"), 3695)
    end,
    on_search_submit   = function(query) ... end,

    -- Result rendering: configure either list mode OR grid mode, not both.
    -- LIST MODE (presets, tokens, conditionals):
    rows_per_page      = 5,                     -- preset uses 5; tokens uses 6
    row_renderer       = function(item, slot_dimen) ... end,
    -- GRID MODE (icons):
    cells_per_page     = function(content_w) ... end,  -- returns total cells per page
    cell_renderer      = function(item, cell_dimen) ... end,
    cell_long_tap      = function(item) ... end,        -- optional; e.g. show name tooltip

    item_count         = function() return n end,
    item_at            = function(idx) return item end,
    empty_state        = function(width, height) ... end,  -- or nil; rendered only when item_count() == 0
    footer_actions     = {
        { key="close",  label="Close",    on_tap=function() ... end },
        { key="manage", label="Manage…",  on_tap=function() ... end, enabled_when=function() return ... end },
        { key="install", label="Install", on_tap=function() ... end, primary=true },
    },
}
```

The widget owns: layout math, tab-bar rendering, chip-strip rendering (with two-row wrap when needed), search input rendering and keyboard, pagination state and chevrons, footer button row, modal frame (title separator, dimensions, dismiss-on-outside-tap behaviour). Does not own: anything specific to a domain's data. The row/cell renderer receives a fixed slot dimension and returns a widget filling it.

**Search input behaviour:**

- The input is a `FocusManager`-aware input field positioned above the chip strip, immediately below the title bar.
- Tapping the input opens KOReader's keyboard. Per the project's "no keyboard on open" preference for line editors, the *modal* opens without keyboard, but the search input itself opens with keyboard up when tapped — single-purpose intent justifies it.
- Submitting (keyboard's Search button or a paired Search button next to the input) calls `on_search_submit(query)` on the domain.
- Domain config decides what to do: typically it re-runs the matcher against its data, sets `item_count`/`item_at` to point at the filtered array, and invokes the modal's `refresh()`.
- Empty input (≤1 char) → `on_search_submit` is not called; modal stays in browse mode.
- A "Clear search" affordance (small × inside the input) returns to browse mode.

**State the widget manages:**

- Active tab (if tabs configured).
- Active chip (if chip strip configured).
- Current page number.
- Current search query (or nil if not searching).
- Cached page-content widgets (rebuilt on tab/chip/search/page change, not on every paint).

### Icons modal (`menu/icons_library.lua`)

**Data sources (two layers):**

1. The existing curated catalogue from `bookends_icon_picker.lua` — categories Dynamic, Device, Reading, Time, Status, Symbols, Arrows, Progress blocks, Separators. ~70 entries. Always available without network/file load.
2. The full Nerd Font names data file (`bookends_nerdfont_names.lua`) — ~3,700 entries. Loaded lazily on first search submit. Keeps the modal-open path fast for users who don't search.

**Chips:**

`All` `Dynamic` `Device` `Reading` `Time` `Status` `Symbols` `Arrows` `Progress` `Separators`

`All` is the default. Tapping any chip filters the *curated* catalogue to that category. The full Nerd Font set is only consulted when the user searches.

**Search:**

- Placeholder: `Search 3,695 icons by name…` with the count derived from the loaded data file (`#nerdfont_names`).
- On submit: lazy-require `bookends_nerdfont_names`, run multi-term substring AND match against each entry's `name`, take matches in encounter order (already alphabetical-by-name in the file), cap at 200, return.

**Result rendering — grid layout:**

Icons render as a grid, not a list. Each cell shows the glyph (large, centred) with a small label underneath. The grid lets users scan visually rather than reading top-to-bottom — which suits icons specifically because the glyph IS the primary identifier (the label is supplementary).

- **Cells per row:** target 4 columns on a 1248px Paperwhite (each cell ~290px wide), reducing to 3 columns on narrower devices. Calculated from modal content width / target cell width.
- **Rows per page:** target 6 rows, giving 18-24 cells per page depending on width. Pagination chevrons advance/retreat one page at a time as in list mode.
- **Cell content:**
  - Curated catalogue items: glyph (centred, ~36-44px) + label below (the existing description like `Bookmark (filled)`, possibly truncated for narrower cells).
  - Search results: glyph + name suffix below (the part after `nf-{set}-`, e.g. `bookmark` for `nf-fa-bookmark`). The full canonical name (`nf-fa-bookmark`) is shown on long-tap as a tooltip / brief notification.
- **Cell tap:** insert the bare PUA glyph at the cursor; close the modal.
- **Cell long-tap:** show a brief notification with the full canonical name and codepoint (`nf-fa-bookmark · U+F02E`) — useful for users referencing presets that hard-code codepoints.

**Footer:** `Close`. No primary action button — tap-on-cell is the action.

**Migration touchpoint:** `bookends_line_editor.lua:351` (the `self:showTokenPicker(...)` call site is the *token* picker, not icons; the icon picker's call site is wherever `IconPicker:show(...)` is invoked from the line editor). Both swap to the new modals.

### Tokens modal (`menu/tokens_library.lua`)

**Data sources:**

- The existing token catalogue from `menu/token_picker.lua` — ~100 entries across categories Book, Chapter, Time, Battery, Frontlight, Format, etc.
- The existing conditional catalogue (`Bookends.CONDITIONAL_CATALOG`) — ~30 entries.

**Chips:**

`All` `Book` `Chapter` `Time` `Battery` `Frontlight` `Format` … `If/else`

`All` shows the union of token + conditional entries. `If/else` shows only conditionals. Other chips show their corresponding token category.

**Search:**

- Placeholder: `Search tokens…` (no count — the catalog is small enough that a count would be noise).
- On submit: multi-term substring AND match against `description`, `token`, and (for conditionals) `expression`. Match across both tokens AND conditionals — search is global within the domain. Take matches in encounter order, cap at 200.

**Row template (description-first, per project preference for prioritising readable content):**

| | Line 1 (primary) | Line 2 |
|---|---|---|
| Token | description (e.g. `Book percentage`) | `%book_pct → 62%` (live expansion against current book) |
| Conditional | description (e.g. `Show only after 11pm`) | `[if:time>=23]…[/if]` (the bare expression) |

The live expansion for tokens uses the existing `Tokens.expand(...)` machinery against the current book's metadata, same as today's two-line Menu rendering does.

**Row tap:** insert the token text or conditional expression at the cursor; close the modal.

**Footer:** `Close`. No primary action.

**Conditional sub-menu retirement:** the `If/Else conditional tokens →` entry from `menu/token_picker.lua:231` ceases to exist. Conditionals are now first-class chip-filtered content alongside tokens.

### Preset modal refactor (`menu/preset_manager_modal.lua`)

Becomes a thin domain configuration. The 1,784-line file shrinks substantially — most chrome rendering (tabs, segment chips, modal frame, pagination, action footer) moves to the shared widget. What remains:

- Preset-specific data fetch and state (gallery index, install counts, approval queue, online check).
- Per-tab chip-strip definition (My presets → Latest/Starred; Gallery → Latest/Popular).
- Tab-switch logic (refresh-on-chip-tap when stale).
- Gallery empty-state help panel (`Discover more presets` + intro + share invitation + CTA), preserved as `empty_state` callback.
- Preset row renderer (the bold name + author + description + ✓ + 🎨 layout, exactly as today).
- Footer actions (`Close`, `Manage…` with overflow conditionals, `Install` as primary).
- Long-tap handler for overflow actions on Local-tab rows (rename / edit description / duplicate / delete).

**Behaviour preserved exactly:**

- Modal opens at the page containing the active preset.
- Cold gallery state shows neither chip highlighted (per current "user hasn't engaged yet" rule).
- Refresh-on-chip-tap when stale, no explicit refresh button.
- ✓ flag for installed gallery presets, 🎨 flag for colour-using presets.
- Approval queue count in status text when present.
- Empty-state height matches populated layout (5 card slots + pagination), so the modal doesn't resize on Refresh.

**Search added to both tabs:**

- My presets: `Search my presets by name…` — filters the local list by name match against `name` field.
- Gallery: `Search gallery presets by name…` — filters the gallery index by name match.

### Build script (`tools/build_nerdfont_names.py`)

```
usage: build_nerdfont_names.py [-h] [--symbols-ttf PATH]
                               --glyphnames-json PATH
                               [--output PATH]
```

**Behaviour:**

1. Parse the symbols TTF cmap with `fontTools`. Collect every codepoint in the PUA range U+E000–U+F8FF that has a glyph.
2. Parse the upstream Nerd Fonts `glyphnames.json` — a flat object keyed by canonical name, each entry containing `{char, code, ...}` where `code` is the hex codepoint as a string.
3. Intersect: keep only entries whose `code` is in the font's PUA cmap.
4. Sort alphabetically by canonical name (the JSON key).
5. Emit `bookends_nerdfont_names.lua` with a header comment recording: source paths, glyph count, font cmap range, generation timestamp; followed by `local M = { {name="…", code=0x…}, ... } return M`.

**Determinism:** same inputs always produce identical output. Diffs after a regen reflect real upstream changes.

**Maintenance cadence:** re-run only when KOReader bumps its bundled `symbols.ttf` (rare, major releases) or when the maintainer wants to pick up new Nerd Fonts naming entries. The generated `.lua` is committed to the plugin repo.

### Generated data file (`bookends_nerdfont_names.lua`)

```lua
-- Generated by tools/build_nerdfont_names.py — do not edit by hand.
-- Source: nerdfonts/symbols.ttf  (cmap PUA range: U+E000–U+F4A9, 3695 glyphs)
-- Source: glyphnames.json from Nerd Fonts <version/path>
-- Generated: 2026-MM-DD

local M = {
    {name="nf-cod-account", code=0xEA77},
    {name="nf-cod-archive", code=0xEA78},
    ...
    {name="nf-weather-yahoo", code=0xE389},
}
return M
```

Total file size estimate: ~150KB. Loaded lazily — only when the icons modal's first search submits.

## Layout details

### Search input placement

The search input sits **above** the chip strip, immediately below the title bar / tab row. This positions search as the more general filter (often the first thing the user wants to do) and the chips as a refinement layer beneath it. The chip strip stays close to the result list it scopes, while search is visually paired with the modal-level title.

Full-width, with internal padding matching the card padding so it visually parallels the rows below it. A horizontal-rule separator line sits between the search input and the chip strip, distinguishing the two filter layers.

### Chip-strip overflow

For domains with many chips (icons has 10, tokens has 8), a single horizontal row may overflow on narrower devices. The widget handles overflow by **wrapping into a second row** rather than scrolling.

- Chips are rendered greedily left-to-right; when the next chip would exceed the modal's content width, it starts a new row beneath.
- Maximum two rows. (No domain currently needs more, and three rows of chips would visually dominate the modal.)
- All chips are always visible — no scroll, no off-screen chips, no chevrons. The user always sees the complete filter set.
- Vertical cost: roughly one extra chip row's height (~28px scaled). Modal height adjusts accordingly when the second row is needed.

Two-row wrap is preferred over horizontal scrolling because (a) it keeps the entire chip set discoverable without gestural exploration, and (b) it avoids the chevron-and-window-state complexity of a scrollable strip — important on e-ink where animation feels laggy.

### Search interaction with chips

Chips and search **compose AND-style**. Activating a chip narrows the visible content set; submitting a search filters that narrowed set further. Both filters can be active simultaneously.

- To clear the chip filter: tap the `All` chip (or whatever the domain's "everything" chip is named).
- To clear the search filter: clear the input and submit empty.
- Activating a different chip while a search is active leaves the search query in place; it just re-applies against the new chip's scope. The user has to clear the search input explicitly if they want to drop it.

This keeps the model simple and predictable: every filter the user has applied stays applied until the user removes it.

### No-match state

After a search submit returns zero results, the result area shows a centred message:

```
No matches for "<query>"

Try a different word, or tap All to clear category filters.
```

The search input retains the query for editing.

### Capped-results state

When >200 entries match, show the first 200 paginated as normal, and append a final non-tappable row at the end of the last page:

```
Showing 200 of N matches — refine your search.
```

The 200 cap exists because (a) past 200 entries the user is unlikely to be scanning by eye anyway, and (b) keeping the result count bounded helps page-render performance on Kindle.

### Footer

Three-button row with separator dividers between buttons. Buttons are configurable per domain. Primary action (when defined) is rendered with bold weight; others are regular. Disabled buttons render in grey and don't accept taps.

| Domain | Footer |
|---|---|
| Presets | `Close` ` | ` `Manage…` ` | ` **`Install`** |
| Icons | `Close` |
| Tokens | `Close` |

For the icons and tokens modals, the footer is a single full-width Close button (no dividers).

## Per-domain configurations

### Presets

```lua
{
    title = _("Preset library"),
    tabs = {
        { key="local",   label=_("My presets") },
        { key="gallery", label=_("Gallery") },
    },
    on_tab_change = function(tab_key)
        if tab_key == "gallery" and galleryIsStale() then
            -- existing refresh logic
        end
    end,
    chip_strip = function(active_tab)
        if active_tab == "local" then
            return {
                { key="latest",  label=_("Latest"),  is_active=mySort=="latest" },
                { key="starred", label=_("Starred"), is_active=mySort=="starred" },
            }
        else
            return {
                { key="latest",  label=_("Latest"),  is_active=gallerySort=="latest" },
                { key="popular", label=_("Popular"), is_active=gallerySort=="popular" },
            }
        end
    end,
    search_placeholder = function(active_tab)
        if active_tab == "local" then
            return _("Search my presets by name…")
        else
            return _("Search gallery presets by name…")
        end
    end,
    rows_per_page = 5,
    row_renderer = renderPresetCard,            -- existing card renderer
    empty_state = function(w, h)
        if active_tab == "gallery" and gallery_index == nil then
            return galleryHelpPanel(w, h)        -- existing "Discover more presets" panel
        end
        return nil
    end,
    footer_actions = {
        { key="close",   label=_("Close"),    on_tap=close },
        { key="manage",  label=_("Manage…"),  on_tap=manage,  enabled_when=hasPresetSelected },
        { key="install", label=_("Install"),  on_tap=install, primary=true, enabled_when=hasGalleryPresetSelected },
    },
}
```

### Icons

```lua
{
    title = _("Icons library"),
    tabs = nil,
    chip_strip = function()
        return {
            { key="all",        label=_("All"),        is_active=activeChip=="all" },
            { key="dynamic",    label=_("Dynamic"),    is_active=activeChip=="dynamic" },
            { key="device",     label=_("Device"),     is_active=activeChip=="device" },
            { key="reading",    label=_("Reading"),    is_active=activeChip=="reading" },
            { key="time",       label=_("Time"),       is_active=activeChip=="time" },
            { key="status",     label=_("Status"),     is_active=activeChip=="status" },
            { key="symbols",    label=_("Symbols"),    is_active=activeChip=="symbols" },
            { key="arrows",     label=_("Arrows"),     is_active=activeChip=="arrows" },
            { key="progress",   label=_("Progress"),   is_active=activeChip=="progress" },
            { key="separators", label=_("Separators"), is_active=activeChip=="separators" },
        }
    end,
    search_placeholder = function()
        local n = #(require("bookends_nerdfont_names"))
        return T(_("Search %1 icons by name…"), formatThousands(n))
    end,
    cells_per_page = function(content_w)         -- icons render as a grid, not a list
        local cols = math.max(3, math.floor(content_w / scaleBySize(290)))
        return cols * 6                            -- 6 rows of cells
    end,
    cell_renderer = renderIconCell,                -- glyph + label below per cell
    cell_long_tap = renderIconNameTooltip,
    footer_actions = {
        { key="close", label=_("Close"), on_tap=close },
    },
}
```

### Tokens

```lua
{
    title = _("Tokens library"),
    tabs = nil,
    chip_strip = function()
        return {
            { key="all",        label=_("All"),        is_active=activeChip=="all" },
            { key="book",       label=_("Book"),       is_active=activeChip=="book" },
            { key="chapter",    label=_("Chapter"),    is_active=activeChip=="chapter" },
            { key="time",       label=_("Time"),       is_active=activeChip=="time" },
            { key="battery",    label=_("Battery"),    is_active=activeChip=="battery" },
            { key="frontlight", label=_("Frontlight"), is_active=activeChip=="frontlight" },
            { key="format",     label=_("Format"),     is_active=activeChip=="format" },
            { key="ifelse",     label=_("If/else"),    is_active=activeChip=="ifelse" },
        }
    end,
    search_placeholder = function() return _("Search tokens…") end,
    rows_per_page = 6,
    row_renderer = renderTokenRow,              -- handles both tokens and conditionals
    footer_actions = {
        { key="close", label=_("Close"), on_tap=close },
    },
}
```

## Search behaviour

### Match function

```lua
local function matches(entry_text, query)
    if #query < 2 then return false end
    local lc_text = entry_text:lower()
    for term in query:lower():gmatch("%S+") do
        if not lc_text:find(term, 1, true) then return false end
    end
    return true
end
```

`true` substring match (Lua's `find` with the plain flag) — no regex, no fuzzy match. Multi-term AND.

### Per-domain search field

| Domain | Field(s) matched |
|---|---|
| Presets | `name` only. Author and description are not matched (avoids "find me presets by Mido" surfacing too many tangentially-related rows). |
| Icons | `name` (the full `nf-{set}-{descriptive}` form). User can type `bookmark` (matches across all sets) or `nf-fa` (matches FontAwesome 4 only) or `nf-mdi-book-open` (specific). |
| Tokens | `description`, `token`, and (for conditionals) `expression`. The user might think in any of these terms. |

### Result ordering

Already sorted alphabetically in the source data; matches preserved in encounter order. No re-sort step.

For the Nerd Font names file specifically, alphabetical-by-full-name produces automatic two-tier grouping in results: by source set (because the `nf-{set}-` prefix dominates the sort), then by descriptive name within each set. So a search for `clock` returns `nf-cod-clock`, `nf-fa-clock_o`, `nf-md-clock`, `nf-md-clock_outline` in that order — set-grouped and concept-grouped together.

## Data dependencies

### Bundled symbols font

KOReader ships `nerdfonts/symbols.ttf` at `koreader/fonts/nerdfonts/symbols.ttf`. The bundled font's PUA cmap range is U+E000–U+F4A9, with 3,695 glyphs. The build script intersects with this exact font version.

If KOReader bumps the bundled font (e.g. picks up a newer Nerd Fonts release), the maintainer regenerates `bookends_nerdfont_names.lua` from the new font + corresponding `glyphnames.json`. Diff review reveals which names changed.

### Upstream Nerd Fonts `glyphnames.json`

The maintainer downloads from the Nerd Fonts repo on demand. URL or commit SHA recorded in the build script's header comment for traceability. Not auto-fetched (avoids brittle network dependency in a build that rarely runs).

### No runtime network access

The icons modal reads the committed `bookends_nerdfont_names.lua` lazily. No network calls at search time. The plugin's existing "no automatic network requests" preference (per project memory) is preserved.

## Migration plan

Single release. Three sequential phases on a feature branch.

### Phase 1: Extract chrome from preset modal

1. Create `menu/library_modal.lua` with the chrome rendering lifted from the existing preset modal: tabs, segment chips, modal frame, pagination, footer.
2. Refactor `menu/preset_manager_modal.lua` to consume `BookendsLibraryModal`. The preset modal becomes a domain-config builder.
3. Verify byte-for-byte visual parity on Kindle: same tab labels, same chip strip, same row layout, same empty-state panel, same pagination chevrons, same footer buttons. No user-visible regressions.
4. Verify behavioural parity: tab switch refresh logic, chip tap refresh-when-stale, install ✓ flag, colour 🎨 flag, overflow actions on long-tap, footer Close / Manage… / Install enable rules.
5. Land Phase 1 alone if needed; otherwise continue.

This phase is the highest-risk because it changes the most code with the least new functionality. Doing it first proves the substrate before building anything new on top.

### Phase 2: Build icons modal

1. Write `tools/build_nerdfont_names.py` and run it against the laptop's KOReader install + a downloaded `glyphnames.json`. Commit the generated `bookends_nerdfont_names.lua`.
2. Create `menu/icons_library.lua` consuming `BookendsLibraryModal`. Port the existing curated catalogue from `bookends_icon_picker.lua` into the chip-scoped browse mode.
3. Wire the line editor's icon-picker call site to open `icons_library` instead of `IconPicker:show()`.
4. Implement the lazy-loaded full-search path against `bookends_nerdfont_names`.
5. Delete `bookends_icon_picker.lua`. Search the codebase for any remaining `IconPicker.showPickerMenu` callers; the token picker is one — those still get migrated in Phase 3, but they keep working in the meantime via a temporary shim or by reordering Phase 2 and Phase 3.

### Phase 3: Build tokens modal

1. Create `menu/tokens_library.lua` consuming `BookendsLibraryModal`.
2. Port both the existing token catalogue and `Bookends.CONDITIONAL_CATALOG` from `menu/token_picker.lua`. Conditionals get the `If/else` chip; tokens get their existing categories as chips.
3. Wire the line editor's token-picker call site to open `tokens_library` instead of `Bookends:showTokenPicker()`.
4. Delete `menu/token_picker.lua`. Remove its registration from `main.lua`.
5. Verify the conditional-insertion flow: tapping a conditional row inserts the bare `[if:…]…[/if]` expression at the cursor position, same as today.

### Build order rationale

Presets first because it's where the chrome originates — proving the refactor preserves behaviour is the highest-confidence first step. Icons second because the build-script + data-file dependency adds the biggest unknown. Tokens last because it's the most straightforward port (similar to icons but smaller, no big data file).

### Migration safety

- All three phases happen on a single feature branch.
- The branch tar-pipes to Kindle for in-situ visual verification at each phase.
- The legacy modules (`bookends_icon_picker.lua`, `menu/token_picker.lua`) stay in place until their successors fully replace them, then deletions happen in their respective phases.
- No backwards-compatibility shims after the merge: the legacy `IconPicker.showPickerMenu` wrapper is fully gone in the released version.
- Existing user data (saved presets, line text with tokens, icon glyphs already inserted into lines) is unaffected — none of this work touches the data layer for line content. Only the picker UIs change.

## Open questions

1. **Search-and-chip interaction (post-release validation).** The spec uses AND-composition: chip narrows the searchable set; search filters within the narrowed set. Both filters stay active until the user removes them. This is the simpler model and makes search above chips feel hierarchical. If users in practice find "search clears chip" more intuitive (they don't realise they're scoped to a category), revisit.

2. **Grid cell width tuning.** The spec targets 4 columns at 1248px Paperwhite width and 3 columns on narrower devices, but the exact pixel target for cell width and the grid's vertical spacing are ergonomic decisions best made against on-device renders, not in the spec. Phase 2 implementation will iterate against actual Kindle screenshots.

3. **Long-tap tooltip on icon cells.** The spec calls for a brief notification showing the canonical name + codepoint on long-tap. The tooltip's exact rendering (Notification widget? brief overlay? in-line text?) is an implementation detail; pick whichever fits naturally with KOReader's existing patterns during Phase 2.

## Future work (deferred)

- **Universal search palette** — type once, search across presets/icons/tokens at the same time. Considered and rejected for this release because the per-domain user journeys are distinct (you don't want preset matches when picking a token mid-line-edit). Could revisit if cross-domain discovery proves valuable.
- **Live filter as user types** — viable on faster e-ink hardware (Boox, Kobo Libra Colour) but feels janky on Kindles. Could be conditionalised on device type later.
- **Recent / favourite icons** — like a "recently used" chip. Would need persistent state per-domain.
- **Multi-select for batch operations** (e.g. delete multiple presets in one go). Currently overflow actions are per-row.
