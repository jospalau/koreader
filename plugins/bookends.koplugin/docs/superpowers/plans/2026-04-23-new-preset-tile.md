# New Preset Tile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tappable tile to the end of the "My presets" card list that creates a blank preset and makes it active.

**Architecture:** One new pure-Lua helper module for name generation (testable via the existing `_test_*.lua` harness pattern). One new method on `PresetManagerModal` for the tap orchestration. One surgical change to `_renderLocalRows()` to append the synthetic tile as slot `(N+1)` — the existing `is_virtual` flag on `_addRow()` already suppresses description/author, so no changes to `_addRow()` are needed for layout.

**Tech Stack:** Lua 5.1 (KOReader's embedded runtime), KOReader widget primitives (`FrameContainer`, `InputContainer`, `TextWidget`), gettext via `_()` for i18n, `.po` files under `locale/`.

---

## File Structure

### Create

- `preset_naming.lua` — tiny pure-Lua module exporting `nextUntitledName(presets, stem)`. No KOReader dependencies, trivially unit-testable.
- `_test_preset_naming.lua` — standalone test runner following the `_test_conditionals.lua` pattern.

### Modify

- `menu/preset_manager_modal.lua` — add `_createBlankPreset()` method, append tile row in `_renderLocalRows()`.
- `locale/bookends.pot` — add two new strings.
- `locale/{bg_BG,de,en_GB,es,fr,it,pt_BR}.po` — fan out the two new strings with translations.

### Untouched

- `preset_manager.lua` — no changes. Existing `writePresetFile()`, `setActivePresetFilename()`, `applyPresetFile()` cover everything. Filename collision is already handled by `writePresetFile()` via its `_2.lua`, `_3.lua` counter at `preset_manager.lua:253-257`; our naming helper only prevents *display-name* collisions, not filename collisions.
- `main.lua`, `bookends_config.lua`, `bookends_tokens.lua` — untouched.

---

## Task 0: Create feature branch

**Files:** none

- [ ] **Step 1: Confirm a clean working tree from master**

Run: `git status && git rev-parse --abbrev-ref HEAD && git log --oneline -n 3`
Expected: branch `master`, worktree clean, HEAD includes `1eaeb46 Fix multi-line pixel truncation for list tokens (#27)`.

- [ ] **Step 2: Create and switch to the feature branch**

Run: `git checkout -b feat/new-preset-tile`
Expected: `Switched to a new branch 'feat/new-preset-tile'`.

No commit yet — the first commit lands in Task 1.

---

## Task 1: Naming helper + unit tests

**Files:**
- Create: `preset_naming.lua`
- Create: `_test_preset_naming.lua`

**Design:** `nextUntitledName(presets, stem)` accepts a list of `{name=...}` entries (the shape returned by `readPresetFiles()`) and a stem string. Returns the first unused `stem`, `stem 2`, `stem 3`, … Pure function, no I/O.

- [ ] **Step 1: Write the failing test file**

Create `_test_preset_naming.lua`:

```lua
-- Dev-box test runner for preset_naming.lua. Pure Lua, no KOReader deps.
-- Usage: cd into the plugin dir, then `lua _test_preset_naming.lua`.
-- Exits non-zero on failure.

local PresetNaming = dofile("preset_naming.lua")

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        pass = pass + 1
    else
        fail = fail + 1
        io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n")
    end
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "")
            .. " expected=" .. string.format("%q", tostring(expected))
            .. " got="      .. string.format("%q", tostring(actual)), 2)
    end
end

test("empty list returns bare stem", function()
    eq(PresetNaming.nextUntitledName({}, "Untitled"), "Untitled")
end)

test("unrelated presets do not block bare stem", function()
    local presets = { {name = "Minimal"}, {name = "Classic"} }
    eq(PresetNaming.nextUntitledName(presets, "Untitled"), "Untitled")
end)

test("bare stem taken returns numbered suffix", function()
    local presets = { {name = "Untitled"} }
    eq(PresetNaming.nextUntitledName(presets, "Untitled"), "Untitled 2")
end)

test("contiguous suffixes return next integer", function()
    local presets = {
        {name = "Untitled"},
        {name = "Untitled 2"},
        {name = "Untitled 3"},
    }
    eq(PresetNaming.nextUntitledName(presets, "Untitled"), "Untitled 4")
end)

test("gap in suffixes reclaims bare stem", function()
    local presets = { {name = "Untitled 5"} }
    eq(PresetNaming.nextUntitledName(presets, "Untitled"), "Untitled")
end)

test("gap at position 2 reclaims Untitled 2", function()
    local presets = { {name = "Untitled"}, {name = "Untitled 3"} }
    eq(PresetNaming.nextUntitledName(presets, "Untitled"), "Untitled 2")
end)

test("custom stem respected", function()
    local presets = { {name = "New"} }
    eq(PresetNaming.nextUntitledName(presets, "New"), "New 2")
end)

test("presets with similar-but-not-matching names ignored", function()
    local presets = {
        {name = "Untitled Saga"},
        {name = "My Untitled"},
        {name = "UntitledX"},
    }
    eq(PresetNaming.nextUntitledName(presets, "Untitled"), "Untitled")
end)

io.stdout:write(string.format("%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/andyhazz/projects/bookends.koplugin && lua _test_preset_naming.lua`
Expected: FAIL — `_test_preset_naming.lua:6: cannot open preset_naming.lua` or similar load error.

- [ ] **Step 3: Write the helper module**

Create `preset_naming.lua`:

```lua
-- Preset-name generator for the "+ New preset" tile.
-- Pure Lua, no KOReader dependencies — unit-testable via _test_preset_naming.lua.

local PresetNaming = {}

--- Return the first unused name in the sequence: stem, "stem 2", "stem 3", ...
--- Collisions are checked by exact string match against the `name` field of
--- every entry in `presets` (the shape produced by Bookends:readPresetFiles).
function PresetNaming.nextUntitledName(presets, stem)
    local taken = {}
    for _, p in ipairs(presets) do
        taken[p.name] = true
    end
    if not taken[stem] then return stem end
    local i = 2
    while taken[stem .. " " .. i] do
        i = i + 1
    end
    return stem .. " " .. i
end

return PresetNaming
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/andyhazz/projects/bookends.koplugin && lua _test_preset_naming.lua`
Expected: `8 passed, 0 failed`.

- [ ] **Step 5: Luac bytecode sanity check**

Run: `luac -p preset_naming.lua _test_preset_naming.lua`
Expected: no output (syntax clean).

- [ ] **Step 6: Commit**

```bash
git add preset_naming.lua _test_preset_naming.lua
git commit -m "feat(presets): add nextUntitledName helper + tests

Pure-Lua module that picks the next unused 'Untitled' name for
blank-preset creation. Collision is by display name, not filename —
writePresetFile still handles filename suffixing on disk.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `_createBlankPreset()` orchestrator

**Files:**
- Modify: `menu/preset_manager_modal.lua` (add new method, add `require`)

**Design:** A single method that builds a blank schema, writes it, activates it, and triggers the modal's existing rebuild path. No user-facing dialog.

- [ ] **Step 1: Require the naming helper at the top of the modal file**

Find the `require` block near the top of `menu/preset_manager_modal.lua`. Add, alphabetically with the other in-plugin requires:

```lua
local PresetNaming = require("preset_naming")
```

If unsure where the plugin's `require` block sits, run `grep -n 'require(' menu/preset_manager_modal.lua | head -20` — they live near the top. Place the new line alongside the other `require("bookends_...")` / `require("preset_...")` entries.

- [ ] **Step 2: Add the blank-schema builder (module-local function)**

Add this function near the top of `menu/preset_manager_modal.lua`, just below the `require` block and before the module table is declared:

```lua
--- Build the in-memory structure for a blank preset. Every position exists
--- (the loader expects all six) but each lines array is empty. Margins and
--- other defaults come from the shipped bookends_config defaults via a deep
--- copy performed by the caller's writePresetFile path — we pass only the
--- fields the user hasn't customised yet.
local function buildBlankPreset(name)
    return {
        name = name,
        description = "",
        author = "",
        positions = {
            tl = { lines = {} }, tc = { lines = {} }, tr = { lines = {} },
            bl = { lines = {} }, bc = { lines = {} }, br = { lines = {} },
        },
        progress_bars = {},
    }
end
```

Note: we intentionally do NOT set `defaults = {...}` here. The preset loader fills in any missing top-level fields from the shipped defaults when the preset is activated, so an absent `defaults` table is equivalent to "use shipped defaults". This keeps the on-disk file minimal.

- [ ] **Step 3: Add the orchestrator method**

Immediately below `_saveCurrentAsPreset` at `menu/preset_manager_modal.lua:788-817`, add:

```lua
function PresetManagerModal._createBlankPreset(self)
    local presets = self.bookends:readPresetFiles()
    local name = PresetNaming.nextUntitledName(presets, _("Untitled"))
    local preset = buildBlankPreset(name)
    local filename = self.bookends:writePresetFile(name, preset)
    self.bookends:setActivePresetFilename(filename)
    self.rebuild()
end
```

Notes for the implementer:
- `self.bookends:readPresetFiles()` returns the array of `{name, filename, preset}` entries. `nextUntitledName` only cares about the `name` field.
- `self.bookends:writePresetFile(name, preset)` handles filename sanitisation and on-disk collision via its `_2.lua` counter. Returns the chosen filename.
- `self.rebuild()` is the modal's existing rebuild path (see how `_saveCurrentAsPreset` calls it at line 811). It re-renders the "My presets" tab and — per `preset_manager_modal.lua:167` — jumps to the page containing the active preset, which is now the new card.

- [ ] **Step 4: Desktop smoke test — method wiring**

Desktop KOReader is installed on your laptop with the plugin symlinked (per the `reference_laptop_koreader.md` memory). Without yet rendering the tile, wire a temporary hotkey to call `_createBlankPreset` so the method can be verified:

Open `menu/preset_manager_modal.lua` and TEMPORARILY add a debug trigger inside the `buildFromCatalog` area (find any existing `onClose` or similar callback and add a one-off invocation) — OR open a Lua console in desktop KOReader via `Plus → Lua console` and run:

```lua
local modal = ...  -- however you get a handle; easiest is to open the preset manager first
modal:_createBlankPreset()
```

Expected: a new file `Untitled.lua` appears in `~/.config/koreader/settings/bookends_presets/`, its `name` field is `"Untitled"`, the active preset setting points to it, and the modal re-renders showing the new card (no tile yet — that's Task 3).

Cleanup: delete the test preset file and revert the active-preset setting before moving on.

- [ ] **Step 5: Commit**

```bash
git add menu/preset_manager_modal.lua
git commit -m "feat(presets): add _createBlankPreset orchestrator

Writes a blank preset (empty line arrays in every position) and
switches the active preset. No UI yet — next commit wires the tile.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Render the tile in `_renderLocalRows`

**Files:**
- Modify: `menu/preset_manager_modal.lua:535-563` (the page-slicing block inside `_renderLocalRows`)

**Design:** Treat the tile as the `(N+1)`th slot. Change the page math to account for it, render it whenever its 1-based index falls within the visible window, and pad short pages accordingly.

- [ ] **Step 1: Replace the page-slicing block**

Current code at `menu/preset_manager_modal.lua:535-563`:

```lua
    local presets = self.bookends:readPresetFiles()
    local ROWS_PER_PAGE = 5
    local total_pages = math.max(1, math.ceil(#presets / ROWS_PER_PAGE))
    if self.page > total_pages then self.page = total_pages end
    local start_idx = (self.page - 1) * ROWS_PER_PAGE + 1
    local end_idx = math.min(start_idx + ROWS_PER_PAGE - 1, #presets)
    for i = start_idx, end_idx do
        local p = presets[i]
        local has_colour = PresetManager.hasColour(p.preset) or false
        PresetManagerModal._addRow(self, vg, width, row_height, font_size, baseline, left_pad, {
            display = p.name,
            description = p.preset.description,
            author = p.preset.author,
            star_key = p.filename,
            has_colour = has_colour,
            on_preview = function() self.previewLocal(p) end,
            on_hold = function() PresetManagerModal._openOverflow(self, p) end,
            is_selected = (selected_key == p.filename),
        })
    end

    -- Pad out short pages so the modal height stays stable regardless of
    -- how many real presets fit the page. Each pad slot equals one card
    -- plus the 8px gap _addRow adds after every rendered card.
    local rendered = end_idx - start_idx + 1
    local card_slot_h = Screen:scaleBySize(64) + Screen:scaleBySize(8)
    for _ = rendered + 1, ROWS_PER_PAGE do
        table.insert(vg, VerticalSpan:new{ width = card_slot_h })
    end
```

Replace with:

```lua
    local presets = self.bookends:readPresetFiles()
    local ROWS_PER_PAGE = 5
    local TILE_SLOT = 1  -- the synthetic "+ New preset" tile after the last card
    local total_items = #presets + TILE_SLOT
    local total_pages = math.max(1, math.ceil(total_items / ROWS_PER_PAGE))
    if self.page > total_pages then self.page = total_pages end
    local start_idx = (self.page - 1) * ROWS_PER_PAGE + 1
    local end_idx = math.min(start_idx + ROWS_PER_PAGE - 1, total_items)
    for i = start_idx, end_idx do
        if i <= #presets then
            local p = presets[i]
            local has_colour = PresetManager.hasColour(p.preset) or false
            PresetManagerModal._addRow(self, vg, width, row_height, font_size, baseline, left_pad, {
                display = p.name,
                description = p.preset.description,
                author = p.preset.author,
                star_key = p.filename,
                has_colour = has_colour,
                on_preview = function() self.previewLocal(p) end,
                on_hold = function() PresetManagerModal._openOverflow(self, p) end,
                is_selected = (selected_key == p.filename),
            })
        else
            -- Synthetic tile: final slot on the last page.
            PresetManagerModal._addRow(self, vg, width, row_height, font_size, baseline, left_pad, {
                display = _("+ New preset"),
                is_virtual = true,
                on_preview = function() PresetManagerModal._createBlankPreset(self) end,
            })
        end
    end

    -- Pad out short pages so the modal height stays stable regardless of
    -- how many items fit the page. Each pad slot equals one card plus the
    -- 8px gap _addRow adds after every rendered card.
    local rendered = end_idx - start_idx + 1
    local card_slot_h = Screen:scaleBySize(64) + Screen:scaleBySize(8)
    for _ = rendered + 1, ROWS_PER_PAGE do
        table.insert(vg, VerticalSpan:new{ width = card_slot_h })
    end
```

Key differences:
- `total_items = #presets + 1` (tile always exists).
- Loop iterates over `total_items` instead of `#presets`.
- When `i == #presets + 1`, render the tile via `_addRow` with `is_virtual = true`. The existing logic in `_addRow` at lines 652 and 672 already suppresses the author tail and description row when `is_virtual` is true.
- The tile has no `star_key`, so `_addRow` falls through to the blank spacer accent column at line 774 — no star, no checkmark, no action.
- No `on_hold` — long-press on the tile does nothing.

- [ ] **Step 2: Luac syntax check**

Run: `luac -p menu/preset_manager_modal.lua`
Expected: no output.

- [ ] **Step 3: Desktop smoke test — empty list**

Ensure `~/.config/koreader/settings/bookends_presets/` is empty (back up any presets first). Launch desktop KOReader, open the preset manager modal, switch to the "My presets" tab.

Expected: page 1 shows the single "+ New preset" tile; pagination area reserved but inactive ("Page 1 of 1").

- [ ] **Step 4: Desktop smoke test — tap creates preset**

Tap the tile.

Expected: page re-renders, an "Untitled" card appears, the "+ New preset" tile moves below it. An `Untitled.lua` file exists on disk.

- [ ] **Step 5: Desktop smoke test — pagination boundary**

Create five presets via repeated tile taps (or manually copy preset files into the dir). Navigate to the last page.

Expected: page 1 shows 5 "Untitled N" cards; page 2 shows the "+ New preset" tile alone; pagination shows "Page 2 of 2" and the left-chevron is active.

- [ ] **Step 6: Desktop smoke test — tile jumps to active**

From a state with a mid-list preset active (tap a card on page 1), tap the "+ New preset" tile.

Expected: the new `Untitled N+1` preset becomes active, and the modal lands on the page containing its card (via the existing jump-to-active logic at `preset_manager_modal.lua:167`).

- [ ] **Step 7: Cleanup**

Delete any test presets (`rm ~/.config/koreader/settings/bookends_presets/Untitled*.lua`).

- [ ] **Step 8: Commit**

```bash
git add menu/preset_manager_modal.lua
git commit -m "feat(presets): render '+ New preset' tile at end of My presets

Tile participates in pagination as slot N+1. Empty list shows a single
tile on page 1; full pages push the tile to its own page. Uses the
existing is_virtual flag on _addRow to suppress description/author.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Tile styling — muted text and dashed border investigation

**Files:**
- Modify: `menu/preset_manager_modal.lua:618-786` (inside `_addRow`, only paths guarded by `opts.is_virtual`)

**Design:** Signal "this is an action slot" via muted title text and — if feasible — a dashed card border. Dashed borders are not a first-class `FrameContainer` option; if a thin wrapper around existing primitives doesn't land cleanly, fall back to solid + muted text only. Do NOT refactor `_addRow` structure; only branch on `opts.is_virtual` for the styling deltas.

- [ ] **Step 1: Muted title colour when is_virtual**

In `_addRow` at around line 642-650, change:

```lua
    local title_widget = TextWidget:new{
        text = opts.display,
        face = Font:getFace("cfont", 18),
        bold = opts.is_selected or false,
        forced_height = title_h,
        forced_baseline = title_bl,
        max_width = content_w,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
```

to:

```lua
    local title_widget = TextWidget:new{
        text = opts.display,
        face = Font:getFace("cfont", 18),
        bold = opts.is_selected or false,
        forced_height = title_h,
        forced_baseline = title_bl,
        max_width = content_w,
        fgcolor = opts.is_virtual and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK,
    }
```

- [ ] **Step 2: Centre the title for is_virtual cards**

The existing `content_row` uses `LeftContainer`. For the virtual tile only, centre the content. Find at around line 681-689:

```lua
    local content_group = VerticalGroup:new{ align = "left", title_line }
    if description_widget then
        table.insert(content_group, description_widget)
    end

    local content_row = LeftContainer:new{
        dimen = Geom:new{ w = content_w, h = card_height - 2 * Size.border.thin },
        content_group,
    }
```

Change to:

```lua
    local content_group = VerticalGroup:new{
        align = opts.is_virtual and "center" or "left",
        title_line,
    }
    if description_widget then
        table.insert(content_group, description_widget)
    end

    local content_row
    if opts.is_virtual then
        content_row = CenterContainer:new{
            dimen = Geom:new{ w = content_w, h = card_height - 2 * Size.border.thin },
            content_group,
        }
    else
        content_row = LeftContainer:new{
            dimen = Geom:new{ w = content_w, h = card_height - 2 * Size.border.thin },
            content_group,
        }
    end
```

`CenterContainer` is already required elsewhere in this file (search for `CenterContainer` to confirm the require is present — it is, used at line 604 and 757). No new require needed.

- [ ] **Step 3: Desktop smoke test — text styling**

Launch KOReader, open the modal. Confirm:
- Tile shows "+ New preset" centred and in dark gray.
- Real preset cards are unchanged (black, left-aligned).

- [ ] **Step 4: Investigate dashed border feasibility**

Run: `grep -rn 'dashed\|stroke_dash\|dash_pattern' /home/andyhazz/projects/bookends.koplugin /usr/share/koreader/frontend/ui/widget 2>/dev/null | head -20`

If KOReader's `FrameContainer` or any nearby widget supports a dash option, use it. If not, **skip dashed borders** — muted-text-only is the acceptable fallback per the spec ("Fall back to a solid border if KOReader's `FrameContainer` doesn't expose a dashed-stroke option cleanly").

Do NOT implement a custom dashed-paint routine. That's a disproportionate amount of e-ink paint code for a visual polish item.

- [ ] **Step 5: If dashed border is NOT available, no code change**

Skip to Step 7.

- [ ] **Step 6: If dashed border IS available, wire it in**

In `_addRow` at around lines 695-706, extend the `FrameContainer` construction with the dash option (exact field name depends on what Step 4 surfaced). Guard with `opts.is_virtual`:

```lua
    local card_frame = FrameContainer:new{
        bordersize = Size.border.thin,
        -- stroke_dash = opts.is_virtual and 4 or nil,  -- or whatever the field turns out to be
        radius = Size.radius.default,
        ...
    }
```

Smoke-test the tile border looks dashed, real cards are unchanged.

- [ ] **Step 7: Luac syntax check**

Run: `luac -p menu/preset_manager_modal.lua`
Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add menu/preset_manager_modal.lua
git commit -m "style(presets): muted centred text for '+ New preset' tile

Virtual tile uses DARK_GRAY centred label to read as an action slot
rather than a real card. Dashed border left out — FrameContainer has
no dash option and a custom paint routine is disproportionate polish.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

(Adjust the commit message body if dashed border WAS added.)

---

## Task 5: Add source strings to `bookends.pot`

**Files:**
- Modify: `locale/bookends.pot`

- [ ] **Step 1: Inspect pot header and current entry ordering**

Run: `head -20 locale/bookends.pot && echo --- && grep -c '^msgid' locale/bookends.pot`

Entries are sorted alphabetically by `msgid`. Identify where `+ New preset` and `Untitled` each fall.

- [ ] **Step 2: Add the two new msgids**

For each of the two strings, find the alphabetically correct insertion point and add:

```
msgid "+ New preset"
msgstr ""
```

```
msgid "Untitled"
msgstr ""
```

Both at global column 0, blank line above, blank line below, matching the existing entry formatting.

- [ ] **Step 3: Verify pot is well-formed**

Run: `msgfmt --check-format --output-file=/dev/null locale/bookends.pot`
Expected: no output. A non-zero exit with `msgfmt not found` means the tool isn't installed on this box — in that case, visually confirm the two new entries look identical in structure to neighbouring entries.

- [ ] **Step 4: Commit**

```bash
git add locale/bookends.pot
git commit -m "i18n: add strings for '+ New preset' tile

Two new msgids: '+ New preset' (tile label) and 'Untitled' (default
preset name stem). .po fanout in next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Fan out translations to all `.po` files

**Files:**
- Modify: `locale/bg_BG.po`, `locale/de.po`, `locale/en_GB.po`, `locale/es.po`, `locale/fr.po`, `locale/it.po`, `locale/pt_BR.po`

**Design:** Use the parallel-agent pattern noted in the `reference_translation.md` memory. Dispatch one agent per language to add both new entries with appropriate translations. `en_GB` is the easiest — "+ New preset" and "Untitled" need no translation except British spelling (neither word has one).

- [ ] **Step 1: Dispatch seven parallel translation agents**

Fire all seven in a single message. Each agent receives the same base prompt with the language substituted. Sample prompt (for `fr.po`):

> Working dir: /home/andyhazz/projects/bookends.koplugin. Add two new msgid entries to `locale/fr.po` matching the ones just added to `locale/bookends.pot`:
>
> ```
> msgid "+ New preset"
> msgstr "..."
>
> msgid "Untitled"
> msgstr "..."
> ```
>
> Provide natural French translations. The context is a small e-reader plugin; "+ New preset" is the label on a tile that creates a new blank preset configuration, and "Untitled" is the default name for the newly created preset. Keep the translations short — tile space is limited.
>
> Insert each entry in the alphabetically correct position (entries in this file are sorted by msgid). Match the existing entry formatting exactly (blank line above, blank line below, no wrapping).
>
> Finally, run `msgfmt --check-format --output-file=/dev/null locale/fr.po` to verify the file is well-formed. Report what you translated each string to and the msgfmt result.

Repeat with `de`, `es`, `it`, `pt_BR`, `bg_BG`, `en_GB`. For `en_GB`, note that the source English spellings are fine ("preset" and "untitled" have no British variants) — the agent should still add the entries with `msgstr` equal to the source `msgid` or an empty string, whichever matches the existing `en_GB.po` convention (instruct the agent to match neighbouring entries).

- [ ] **Step 2: Verify each .po compiles**

Run:

```bash
for f in locale/*.po; do
    msgfmt --check-format --output-file=/dev/null "$f" && echo "OK: $f" || echo "FAIL: $f"
done
```

Expected: `OK:` for all seven files. If msgfmt isn't available, visually inspect with `git diff locale/` instead.

- [ ] **Step 3: Commit**

```bash
git add locale/*.po
git commit -m "i18n: translate '+ New preset' and 'Untitled' across all locales

Fans out the two new strings to bg_BG, de, en_GB, es, fr, it, pt_BR.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: On-device verification on Kindle

**Files:** none

**Design:** Use tar-pipe push per the `feedback_scp_exclude_tools.md` memory; manual restart per `feedback_killall_doesnt_reload.md` — user restarts KOReader themselves.

- [ ] **Step 1: Push plugin to Kindle**

Run:

```bash
cd /home/andyhazz/projects/bookends.koplugin && \
tar --exclude='./.git' --exclude='./tools' --exclude='./docs' \
    --exclude='./_test_*.lua' -cf - . | \
    ssh kindle 'cd /mnt/us/koreader/plugins/bookends.koplugin && tar -xf -'
```

Expected: push completes in ~1s. No errors.

- [ ] **Step 2: Tell the user to restart KOReader on the Kindle**

SIGHUP does not reload the plugin. Ask the user to close and reopen KOReader on the device.

- [ ] **Step 3: On-device smoke tests**

Ask the user (or verify via `kindle-screenshot` skill if driving the device) to:
1. Open a book, open the preset manager, go to "My presets".
2. Confirm "+ New preset" tile appears after the last card.
3. Tap it → new "Untitled" card appears, becomes active.
4. Tap the new "Untitled" card → line editor opens; confirm all six positions are empty.
5. Add a line or two, back out — confirm it saves.
6. Create a second blank preset → "Untitled 2".
7. Delete the first, create a third → it should reclaim the bare "Untitled".
8. Fill the list to 5+ presets → confirm the tile moves to its own page.
9. Translate check: if KOReader is set to a non-English locale, confirm the tile label is translated.

- [ ] **Step 4: Fix any device-specific regressions**

If any step fails, debug on-device and return to the relevant earlier task. Common issues:
- Dashed border won't paint → fall back (already covered in Task 4).
- Tile tap creates but modal doesn't re-render → check `self.rebuild()` vs `self.buildFromCatalog()` — there may be a different rebuild entry point on device. Compare to how `_saveCurrentAsPreset` at `menu/preset_manager_modal.lua:788` triggers its rebuild.

- [ ] **Step 5: No commit at this step unless fixes were needed**

If fixes were needed, commit them individually with `fix:` prefix. Otherwise, the feature branch is ready.

---

## Task 8: Merge to master

**Files:** none

- [ ] **Step 1: Squash the feature branch commits**

The user's workflow (per `feedback_dev_workflow.md` memory) is "Iterative commits during dev, squash before release". Squash the feature branch into a single commit on master via interactive rebase or `git merge --squash`:

```bash
git checkout master
git merge --squash feat/new-preset-tile
git status    # confirm staged changes
git commit -m "feat(presets): blank-preset tile at end of My presets

Adds a synthetic '+ New preset' tile after the last card in the local
preset library. Tap creates an empty-lines preset named 'Untitled'
(or 'Untitled N' on collision) and activates it. The tile participates
in pagination as slot N+1; an empty library shows the tile alone on
page 1.

Introduces preset_naming.lua + _test_preset_naming.lua. Styles the
tile with muted centred text inside the existing card frame.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 2: Delete the feature branch**

```bash
git branch -D feat/new-preset-tile
```

- [ ] **Step 3: Confirm on master**

Run: `git status && git log --oneline -n 3`
Expected: clean tree on master with the new commit at HEAD.

---

## Self-review notes

Plan covers every spec section:

- **Tap flow** (spec §Behaviour/Tap flow) → Task 2 (`_createBlankPreset`) + Task 3 (tile render).
- **Pagination table** (spec §Pagination) → Task 3 step 5.
- **First-run** (spec §First-run) → Task 3 step 3.
- **Auto-naming algorithm** (spec §Naming/Algorithm) → Task 1.
- **Naming edge cases** (spec §Naming/Edge cases) → Task 1 test coverage.
- **Blank-slate schema** (spec §Blank-slate schema) → Task 2 step 2 (`buildBlankPreset`).
- **Visual** (spec §Visual) → Task 4 (muted text + dashed investigation + fallback).
- **Implementation surface — new code** (spec §Implementation surface) → Task 1 and Task 2.
- **Implementation surface — modified code** (spec §Implementation surface) → Task 3.
- **i18n** (spec §i18n) → Tasks 5 and 6.
- **Testing — happy path / naming / active-preset** (spec §Testing) → Task 3 desktop steps + Task 7 on-device steps.
- **Risks — blank overlay** (spec §Risks) → noted, no code path; verified manually in Task 7 step 3.4.
- **Risks — accidental tap** (spec §Risks) → tolerated; verified manually in Task 7.
- **Risks — double-tap race** (spec §Risks) → mitigated by the synchronous single-thread UI dispatch in KOReader (no code needed); verified manually in Task 7 step 3.6.
