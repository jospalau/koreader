# Preset Gallery + Unified Preset Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace bookends' split Presets menu with a single central modal (Local + Gallery tabs). Personal presets become "open documents" that autosave overlay edits. Gallery tab browses `AndyHazz/bookends-presets` on GitHub and installs presets with one tap.

**Architecture:** Additive module structure — a new modal widget (`menu/preset_manager_modal.lua`), a new HTTP/cache module (`preset_gallery.lua`), and extensions to the existing `preset_manager.lua`. The autosave hook piggybacks on KOReader's existing `onFlushSettings` call. `BUILT_IN_PRESETS` is removed entirely; a single `basic_bookends.lua` bundled asset seeds fresh installs.

**Tech Stack:** Lua 5.1 (KOReader runtime). HTTP via LuaSocket + curl fallback (same pattern as `updater.lua`). No test framework — validation via `luac -p` for syntax and manual SCP-to-Kindle for behaviour. A new public repo `AndyHazz/bookends-presets` hosts the gallery data as static files.

---

## File Structure

| File | Responsibility | Change |
|------|---------------|--------|
| `preset_manager.lua` | Preset I/O + validation | Extend schema (description/author), add active-preset helpers, autosave write-through |
| `menu/preset_manager_modal.lua` | The central modal UI | Create new (~400 LOC) |
| `preset_gallery.lua` | HTTP + cache + index parsing | Create new (~200 LOC) |
| `menu/presets_menu.lua` | Menu entry point | Shrink to single entry opening modal |
| `main.lua` | Plugin-level integration | Remove BUILT_IN_PRESETS, add autosave hook, rewrite cycle handler, register gesture, first-run seeding |
| `config.lua` | Persisted-settings whitelist | Add new keys |
| `basic_bookends.lua` | Bundled starter preset asset | Create new (bundled with plugin) |
| `README.md` | User docs | Rewrite Presets section |
| `i18n.lua` / `locale/*.po` | Translation strings | Extract new strings post-implementation |

---

## Phase 1 — Preset Manager + autosave (gallery-free, self-contained)

Tasks 1–13. Ship-able on its own. Gallery tab can be hidden or showing "coming soon" until Phase 2.

## Task 1: Branch setup

**Files:** None (git state only).

- [ ] **Step 1: Verify clean tree on master**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin status --short --branch
```
Expected: `## master...origin/master` with only `.claude/` untracked.

- [ ] **Step 2: Create feature branch**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin checkout -b feature/preset-manager
```
Expected: `Switched to a new branch 'feature/preset-manager'`.

---

## Task 2: Extend preset validator schema

**Files:** Modify `preset_manager.lua:82-91`

- [ ] **Step 1: Add description and author to EXPECTED_TYPES**

Edit `preset_manager.lua`. Find:

```lua
    local EXPECTED_TYPES = {
        name = "string",
        enabled = "boolean",
        defaults = "table",
        positions = "table",
        progress_bars = "table",
        bar_colors = "table",
        tick_width_multiplier = "number",
        tick_height_pct = "number",
    }
```

Replace with:

```lua
    local EXPECTED_TYPES = {
        name = "string",
        description = "string",
        author = "string",
        enabled = "boolean",
        defaults = "table",
        positions = "table",
        progress_bars = "table",
        bar_colors = "table",
        tick_width_multiplier = "number",
        tick_height_pct = "number",
    }
```

- [ ] **Step 2: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/preset_manager.lua
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add preset_manager.lua
git commit -m "$(cat <<'EOF'
feat(preset-manager): extend validator schema with description/author

Optional string fields that propagate through the existing validator.
Missing fields remain accepted, keeping existing Personal presets
valid without migration.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Active-preset helpers

**Files:** Modify `preset_manager.lua`

- [ ] **Step 1: Add `getActivePresetFilename` and `setActivePresetFilename`**

Edit `preset_manager.lua`. Find the end of `PresetManager.attach(Bookends)` (just before the closing `end`, around line 260 — after `migratePresetsToFiles`). Insert before that closing `end`:

```lua
    --- Read the filename of the currently-open Personal preset, or nil.
    function Bookends:getActivePresetFilename()
        return self.settings:readSetting("active_preset_filename")
    end

    --- Set (or clear with nil) the active preset file. Does not touch live settings.
    function Bookends:setActivePresetFilename(filename)
        if filename then
            self.settings:saveSetting("active_preset_filename", filename)
        else
            self.settings:delSetting("active_preset_filename")
        end
    end

    --- Given a preset filename, load it + set it active. Returns true on success.
    function Bookends:applyPresetFile(filename)
        local path = self:presetDir() .. "/" .. filename
        local data, err = loadPresetFile(path)
        if not data then return false, err end
        data = validatePreset(data)
        if not data then return false, "validation failed" end
        local ok, lerr = pcall(self.loadPreset, self, data)
        if not ok then return false, lerr end
        self:setActivePresetFilename(filename)
        return true
    end

    --- Serialize current overlay state and write to the active preset file.
    --- No-op if there's no active preset or if previewing.
    function Bookends:autosaveActivePreset()
        if self._previewing then return end
        local filename = self:getActivePresetFilename()
        if not filename then return end
        local path = self:presetDir() .. "/" .. filename
        local lfs = require("libs/libkoreader-lfs")
        if lfs.attributes(path, "mode") ~= "file" then
            -- Active preset file was deleted externally. Recreate it.
            self:ensurePresetDir()
        end
        local preset_data = self:buildPreset()
        -- Preserve the existing name + metadata from the on-disk file if present.
        local existing = loadPresetFile(path)
        if existing then
            preset_data.name = existing.name or preset_data.name
            preset_data.description = existing.description
            preset_data.author = existing.author
        end
        writePresetContents(path, preset_data.name or filename, preset_data)
    end
```

- [ ] **Step 2: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/preset_manager.lua
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add preset_manager.lua
git commit -m "$(cat <<'EOF'
feat(preset-manager): add active-preset helpers

getActivePresetFilename / setActivePresetFilename read and write the
new active_preset_filename setting. applyPresetFile loads + activates
in one call. autosaveActivePreset serializes current overlay config
back to the active preset file unless the plugin is previewing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add persisted-settings keys to config

**Files:** Modify `config.lua`

- [ ] **Step 1: Add new keys to LEGACY_GLOBAL_KEYS whitelist (they are new, not legacy, but the list governs what's persistable)**

Actually, inspect `config.lua` first — there's no generic "allowed settings" whitelist, only a legacy-migration list. The new keys are written directly via `self.settings:saveSetting(key, val)`. The only change needed in config.lua is documenting the new keys.

Edit `config.lua`. Find:

```lua
--- Legacy G_reader_settings keys migrated into the plugin's own settings
--- file on first run. Only read once; safe to extend without breaking users.
Config.LEGACY_GLOBAL_KEYS = {
    "enabled", "font_face", "font_size", "font_bold", "font_scale",
    "margin_top", "margin_bottom", "margin_left", "margin_right",
    "overlap_gap", "truncation_priority", "presets", "last_cycled_preset",
}
```

Immediately after that block, add:

```lua

--- Settings keys introduced by the Preset Manager. Documented here so all
--- persistence-related settings are visible in one place. No runtime use.
Config.PRESET_MANAGER_KEYS = {
    "active_preset_filename",   -- string: filename of the currently-open preset
    "preset_cycle",             -- array of filenames (and "_empty" sentinel for the virtual blank row)
    "preset_manager_tip_shown", -- boolean: first-time long-press tip shown
    "preset_manager_migration_done", -- boolean: one-time migration ran
}
```

- [ ] **Step 2: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/config.lua
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add config.lua
git commit -m "$(cat <<'EOF'
feat(config): document preset-manager setting keys

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Create basic_bookends.lua starter asset

**Files:** Create `basic_bookends.lua`

- [ ] **Step 1: Write the file**

Create `/home/andyhazz/projects/bookends.koplugin/basic_bookends.lua` with contents:

```lua
-- Bookends preset: Basic bookends
return {
    name = "Basic bookends",
    description = "Minimal starter — page number and clock",
    author = "bookends",
    enabled = true,
    positions = {
        tl = { lines = {} },
        tc = { lines = {} },
        tr = { lines = { "%k" }, line_font_size = { [1] = 14 } },
        bl = { lines = {} },
        bc = { lines = { "Page %c of %t" }, line_font_size = { [1] = 14 } },
        br = { lines = {} },
    },
}
```

- [ ] **Step 2: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/basic_bookends.lua
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add basic_bookends.lua
git commit -m "$(cat <<'EOF'
feat(preset): bundle Basic bookends starter asset

Minimal overlay (page number + clock) shipped with the plugin and
auto-provisioned into the user's preset directory on first run
when no other presets exist.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: First-run provisioning + migration

**Files:** Modify `main.lua` — add migration in the plugin init path.

- [ ] **Step 1: Find plugin init**

Grep for where the plugin finishes initial settings setup (existing `setupPresets` or similar). Look for the init tail:

```bash
grep -n 'migratePresetsToFiles\|setupPresets\|function Bookends:init' /home/andyhazz/projects/bookends.koplugin/main.lua | head -5
```

Expected: a call to `self:migratePresetsToFiles()` somewhere in `init`. Add our migration right after it.

- [ ] **Step 2: Add migration function**

Edit `main.lua`. Find `function Bookends:migratePresetsToFiles` area — we want to add a new method. Find this line somewhere in `main.lua` (probably around existing migration code):

```lua
function Bookends:init()
```

Near any other init-time migration, add new method `runPresetManagerMigration`. Place it anywhere in the file (ideally near existing migration-related code). Insert:

```lua
--- One-time migration + first-run provisioning for the Preset Manager.
--- Idempotent — gated by a boolean setting.
function Bookends:runPresetManagerMigration()
    if self.settings:isTrue("preset_manager_migration_done") then
        return
    end

    local lfs = require("libs/libkoreader-lfs")

    -- 1. Rename last_cycled_preset (human name) → active_preset_filename (file)
    local last_name = self.settings:readSetting("last_cycled_preset")
    if last_name and last_name ~= "" then
        local presets = self:readPresetFiles()
        for _, p in ipairs(presets) do
            if p.name == last_name then
                self.settings:saveSetting("active_preset_filename", p.filename)
                break
            end
        end
        self.settings:delSetting("last_cycled_preset")
    end

    -- 2. Seed preset_cycle with all existing Personal presets (preserves current behaviour)
    if not self.settings:readSetting("preset_cycle") then
        local presets = self:readPresetFiles()
        local cycle = {}
        for _, p in ipairs(presets) do
            table.insert(cycle, p.filename)
        end
        self.settings:saveSetting("preset_cycle", cycle)
    end

    -- 3. First-run: provision Basic bookends if bookends_presets/ is empty
    self:ensurePresetDir()
    local dir = self:presetDir()
    local has_any = false
    for f in lfs.dir(dir) do
        if f:match("%.lua$") then
            has_any = true
            break
        end
    end
    if not has_any then
        local DataStorage = require("datastorage")
        local source = DataStorage:getDataDir() .. "/plugins/bookends.koplugin/basic_bookends.lua"
        local dest = dir .. "/basic_bookends.lua"
        local src_file = io.open(source, "rb")
        if src_file then
            local dst_file = io.open(dest, "wb")
            if dst_file then
                dst_file:write(src_file:read("*a"))
                dst_file:close()
                -- Set active and add to cycle
                if not self.settings:readSetting("active_preset_filename") then
                    self.settings:saveSetting("active_preset_filename", "basic_bookends.lua")
                end
                local cycle = self.settings:readSetting("preset_cycle") or {}
                table.insert(cycle, "basic_bookends.lua")
                self.settings:saveSetting("preset_cycle", cycle)
            end
            src_file:close()
        end
    end

    self.settings:saveSetting("preset_manager_migration_done", true)
    self.settings:flush()
end
```

- [ ] **Step 3: Call it from init**

Find where `self:migratePresetsToFiles()` is called. Add `self:runPresetManagerMigration()` on the next line:

```bash
grep -n 'migratePresetsToFiles()' /home/andyhazz/projects/bookends.koplugin/main.lua
```

At each call site (typically one, inside `init` or `setupPresets`), add immediately after:

```lua
    self:runPresetManagerMigration()
```

- [ ] **Step 4: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/main.lua
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add main.lua
git commit -m "$(cat <<'EOF'
feat(preset-manager): first-run provisioning + one-time migration

Runs once per install (gated by preset_manager_migration_done flag):
1. Translates last_cycled_preset (human name) to active_preset_filename
2. Seeds preset_cycle with all existing Personal preset filenames
3. Provisions basic_bookends.lua when the preset directory is empty

Idempotent — safe to run on every plugin load; flag prevents redundant
work. Matches the spec's migration section.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Autosave hook in onFlushSettings

**Files:** Modify `main.lua:1172-1176`

- [ ] **Step 1: Extend the existing onFlushSettings**

Edit `main.lua`. Find:

```lua
function Bookends:onFlushSettings()
    if self.settings then
        self.settings:flush()
    end
end
```

Replace with:

```lua
function Bookends:onFlushSettings()
    if self.settings then
        self.settings:flush()
        -- Autosave the active preset with the current overlay state.
        -- No-op if _previewing or no active preset set.
        local ok, err = pcall(self.autosaveActivePreset, self)
        if not ok then
            require("logger").warn("bookends: autosave failed:", err)
        end
    end
end
```

- [ ] **Step 2: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/main.lua
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add main.lua
git commit -m "$(cat <<'EOF'
feat(preset-manager): autosave active preset on settings flush

Extends the existing onFlushSettings hook. When the active preset is
set and the plugin isn't currently previewing, the current overlay
config is serialized and written back to the preset file. Autosave
failures log to the KOReader log but don't surface to the user or
block the flush.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Rewrite cycle handler with star list + flush-before-cycle

**Files:** Modify `main.lua:238-260`

- [ ] **Step 1: Replace onCycleBookendsPreset**

Edit `main.lua`. Find:

```lua
function Bookends:onCycleBookendsPreset()
    local presets = self:readPresetFiles()
    if #presets == 0 then return true end

    local idx = 1
    local last = self.settings:readSetting("last_cycled_preset")
    if last then
        for i, entry in ipairs(presets) do
            if entry.name == last then
                idx = (i % #presets) + 1
                break
            end
        end
    end

    self.settings:saveSetting("last_cycled_preset", presets[idx].name)
    local ok, err = pcall(self.loadPreset, self, presets[idx].preset)
    if not ok then
        local Notification = require("ui/widget/notification")
        Notification:notify(T(_("Preset error: %1"), tostring(err)))
```

Read forward to the closing `end` of this function — it ends around line 260 with something like:

```bash
sed -n '238,260p' /home/andyhazz/projects/bookends.koplugin/main.lua
```

Replace the entire function with:

```lua
function Bookends:onCycleBookendsPreset()
    -- Flush first so unsaved overlay edits autosave to the departing preset
    -- before we load the next one.
    if self.settings then self.settings:flush() end
    local ok, err = pcall(self.autosaveActivePreset, self)
    if not ok then require("logger").warn("bookends: pre-cycle autosave failed:", err) end

    local cycle = self.settings:readSetting("preset_cycle") or {}
    if #cycle == 0 then return true end

    -- Find current position
    local active = self:getActivePresetFilename()
    local idx = 1
    for i, entry in ipairs(cycle) do
        if entry == active or (active == nil and entry == "_empty") then
            idx = (i % #cycle) + 1
            break
        end
    end

    local next_entry = cycle[idx]
    local Notification = require("ui/widget/notification")

    if next_entry == "_empty" then
        -- Virtual blank: clear all position lines, detach from any preset
        for _, pos in pairs(self.positions) do pos.lines = {} end
        self:setActivePresetFilename(nil)
        self:markDirty()
        Notification:notify(_("(No overlay)"))
        return true
    end

    -- Real preset file
    local ok2, err2 = self:applyPresetFile(next_entry)
    if not ok2 then
        Notification:notify(T(_("Preset error: %1"), tostring(err2)))
        return true
    end
    self:markDirty()
    -- Look up human name for the toast
    local presets = self:readPresetFiles()
    local name = next_entry
    for _, p in ipairs(presets) do
        if p.filename == next_entry then name = p.name; break end
    end
    Notification:notify(T(_("Preset: %1"), name))
    return true
end
```

- [ ] **Step 2: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/main.lua
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add main.lua
git commit -m "$(cat <<'EOF'
feat(preset-manager): star-based cycle with virtual blank support

Cycle now iterates preset_cycle (an ordered list of filenames plus
an "_empty" sentinel for the virtual No-overlay slot) instead of
all Personal presets. Pre-cycle flush protects unsaved tweaks on
the departing preset. When cycle hits "_empty", all position lines
are cleared and the active preset is detached.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Delete BUILT_IN_PRESETS from main.lua

**Files:** Modify `main.lua` — remove the large `Bookends.BUILT_IN_PRESETS = { ... }` block.

- [ ] **Step 1: Find the block boundaries**

Run:
```bash
grep -n 'BUILT_IN_PRESETS' /home/andyhazz/projects/bookends.koplugin/main.lua
```
Note the line number for `Bookends.BUILT_IN_PRESETS = {` (~line 1281). The block continues until its matching closing `}` — read around line 1281–1365 to confirm.

- [ ] **Step 2: Delete the block**

Use Edit tool to replace the entire block with an empty string. The pattern matches from `Bookends.BUILT_IN_PRESETS = {` through the closing `}` that ends the assignment (including the preceding comment lines documenting Nerd Font icons). Leave any unrelated code after it untouched.

Full block (verify line boundaries by reading file first):

```lua
Bookends.BUILT_IN_PRESETS = {
    -- Nerd Font icon references used in presets:
    -- ...all preset entries...
}
```

Delete this entire assignment. The file should flow from whatever comes before to whatever comes after with no gap.

- [ ] **Step 3: Verify no remaining references in main.lua**

Run:
```bash
grep -n 'BUILT_IN_PRESETS' /home/andyhazz/projects/bookends.koplugin/main.lua
```
Expected: no output (all references deleted).

- [ ] **Step 4: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/main.lua
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add main.lua
git commit -m "$(cat <<'EOF'
refactor(main): remove BUILT_IN_PRESETS table

The three bundled presets (Classic Alternating, Rich Detail, Speed
Reader) are moving to the new bookends-presets gallery repo. Users
who want them can download from the Gallery tab; users who had one
applied keep its contents in live settings.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Create the Preset Manager modal (scaffolding + Local tab, no gallery yet)

**Files:** Create `menu/preset_manager_modal.lua`

This is the largest single file in the plan. It provides the modal widget with Local tab only for now; Gallery tab placeholder shows "Gallery coming soon" until Phase 2.

- [ ] **Step 1: Create the file**

Create `/home/andyhazz/projects/bookends.koplugin/menu/preset_manager_modal.lua` with contents:

```lua
--- Preset Manager: central-aligned modal with Local/Gallery tabs.
-- Local tab renders Personal presets + virtual "(No overlay)" row,
-- supports preview/apply, star toggle for cycle membership, and
-- overflow actions (rename/edit description/duplicate/delete).
-- Gallery tab is a stub until Phase 2.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Notification = require("ui/widget/notification")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local util = require("util")
local _ = require("i18n").gettext
local T = require("ffi/util").template

local Screen = Device.screen

local PresetManagerModal = {}

-- Rows-per-page
local ROWS_PER_PAGE = 9

--- Open the manager modal. Single entry point from menu / gesture.
function PresetManagerModal.show(bookends)
    local self = {
        bookends = bookends,
        tab = "local",        -- "local" or "gallery"
        page = 1,
        previewing = nil,     -- { kind = "local"|"gallery"|"blank", name, filename, data }
        original_settings = nil,  -- deep copy of live settings at modal-open
        modal_widget = nil,
    }

    -- Snapshot live settings so Close can revert a preview
    self.original_settings = util.tableDeepCopy({
        enabled   = bookends.enabled,
        positions = bookends.positions,
        defaults  = bookends.defaults,
        active_filename = bookends:getActivePresetFilename(),
    })

    self.rebuild = function() PresetManagerModal._rebuild(self) end
    self.close = function(restore) PresetManagerModal._close(self, restore) end
    self.setTab = function(tab)
        if self.tab ~= tab then self.tab = tab; self.page = 1; self.rebuild() end
    end
    self.previewLocal = function(p) PresetManagerModal._previewLocal(self, p) end
    self.previewBlank = function() PresetManagerModal._previewBlank(self) end
    self.applyCurrent = function() PresetManagerModal._applyCurrent(self) end
    self.toggleStar = function(filename) PresetManagerModal._toggleStar(self, filename) end
    self.openOverflow = function() PresetManagerModal._openOverflow(self) end

    self.rebuild()
end

function PresetManagerModal._close(self, restore)
    if restore and self.previewing then
        -- Revert live settings to the snapshot
        local snap = self.original_settings
        self.bookends.enabled   = snap.enabled
        self.bookends.positions = util.tableDeepCopy(snap.positions)
        self.bookends.defaults  = util.tableDeepCopy(snap.defaults)
        self.bookends:setActivePresetFilename(snap.active_filename)
    end
    self.bookends._previewing = false
    self.previewing = nil
    if self.modal_widget then
        UIManager:close(self.modal_widget)
        self.modal_widget = nil
    end
    self.bookends:markDirty()
end

function PresetManagerModal._previewLocal(self, entry)
    -- Apply preset data to live settings in memory, mark previewing
    self.bookends._previewing = true
    local ok = pcall(self.bookends.loadPreset, self.bookends, entry.preset)
    if not ok then
        Notification:notify(_("Could not preview preset"))
        self.bookends._previewing = false
        return
    end
    self.previewing = { kind = "local", name = entry.name, filename = entry.filename, data = entry.preset }
    self.bookends:markDirty()
    self.rebuild()
end

function PresetManagerModal._previewBlank(self)
    self.bookends._previewing = true
    for _, pos in pairs(self.bookends.positions) do pos.lines = {} end
    self.previewing = { kind = "blank", name = _("(No overlay)") }
    self.bookends:markDirty()
    self.rebuild()
end

function PresetManagerModal._applyCurrent(self)
    if not self.previewing then return end
    if self.previewing.kind == "local" then
        self.bookends:setActivePresetFilename(self.previewing.filename)
    elseif self.previewing.kind == "blank" then
        self.bookends:setActivePresetFilename(nil)
    end
    -- Gallery kind is handled in Phase 2 (Task 16)
    self.bookends._previewing = false
    self.previewing = nil
    if self.modal_widget then
        UIManager:close(self.modal_widget)
        self.modal_widget = nil
    end
    self.bookends:markDirty()
end

function PresetManagerModal._toggleStar(self, entry_key)
    local cycle = self.bookends.settings:readSetting("preset_cycle") or {}
    local found_idx
    for i, f in ipairs(cycle) do if f == entry_key then found_idx = i; break end end
    if found_idx then
        table.remove(cycle, found_idx)
    else
        table.insert(cycle, entry_key)
    end
    self.bookends.settings:saveSetting("preset_cycle", cycle)
    self.rebuild()
end

function PresetManagerModal._isStarred(self, entry_key)
    local cycle = self.bookends.settings:readSetting("preset_cycle") or {}
    for _, f in ipairs(cycle) do if f == entry_key then return true end end
    return false
end

function PresetManagerModal._rebuild(self)
    if self.modal_widget then
        UIManager:close(self.modal_widget)
        self.modal_widget = nil
    end

    local width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
    local row_height = Screen:scaleBySize(42)
    local font_size = 18
    local baseline = math.floor(row_height * 0.65)
    local left_pad = Size.padding.large

    local vg = VerticalGroup:new{ align = "left" }

    -- Title + tab switcher
    local title_face = Font:getFace("infofont", 20)
    local title = TextWidget:new{
        text = _("Preset Manager"),
        face = title_face,
        bold = true,
        forced_height = row_height,
        forced_baseline = baseline,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local tabs_text = "[" .. (self.tab == "local" and "Local" or " Local ") .. "] [" ..
                      (self.tab == "gallery" and "Gallery" or " Gallery ") .. "]"
    local tabs = TextWidget:new{
        text = tabs_text,
        face = Font:getFace("infofont", 16),
        forced_height = row_height,
        forced_baseline = baseline,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    -- Click tabs to switch
    local tabs_ic = InputContainer:new{
        dimen = Geom:new{ w = tabs:getWidth(), h = row_height },
        tabs,
    }
    tabs_ic.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = tabs_ic.dimen } },
    }
    tabs_ic.onTapSelect = function()
        self.setTab(self.tab == "local" and "gallery" or "local")
        return true
    end

    table.insert(vg, LeftContainer:new{
        dimen = Geom:new{ w = width, h = row_height },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = left_pad },
            title,
            HorizontalSpan:new{ width = Screen:scaleBySize(20) },
            tabs_ic,
        },
    })
    table.insert(vg, LineWidget:new{
        background = Blitbuffer.COLOR_BLACK,
        dimen = Geom:new{ w = width, h = Size.line.thick },
    })

    -- State header
    local active_fn = self.bookends:getActivePresetFilename()
    local active_name = _("(No overlay)")
    if active_fn then
        local presets = self.bookends:readPresetFiles()
        for _, p in ipairs(presets) do
            if p.filename == active_fn then active_name = p.name; break end
        end
    end
    local state_line = T(_("Currently editing: %1"), active_name)
    if self.previewing then
        state_line = state_line .. "  //  " .. T(_("Previewing: %1"), self.previewing.name)
    end
    table.insert(vg, LeftContainer:new{
        dimen = Geom:new{ w = width, h = row_height },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = left_pad },
            TextWidget:new{
                text = state_line,
                face = Font:getFace("cfont", 14),
                forced_height = row_height,
                forced_baseline = baseline,
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
    })

    -- Body: rows
    if self.tab == "local" then
        PresetManagerModal._renderLocalRows(self, vg, width, row_height, font_size, baseline, left_pad)
    else
        -- Gallery stub (Phase 2 will replace this)
        table.insert(vg, LeftContainer:new{
            dimen = Geom:new{ w = width, h = row_height * 3 },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = left_pad },
                TextWidget:new{
                    text = _("Gallery — coming soon"),
                    face = Font:getFace("infofont", 16),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            },
        })
    end

    -- Footer buttons
    local btn_close = TextWidget:new{
        text = _("Close"),
        face = Font:getFace("infofont", 16),
        forced_height = row_height,
        forced_baseline = baseline,
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local btn_close_ic = InputContainer:new{
        dimen = Geom:new{ w = math.floor(width / 2), h = row_height },
        CenterContainer:new{
            dimen = Geom:new{ w = math.floor(width / 2), h = row_height },
            btn_close,
        },
    }
    btn_close_ic.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = btn_close_ic.dimen } },
    }
    btn_close_ic.onTapSelect = function() self.close(true); return true end

    local apply_text = _("Apply")
    if self.previewing and self.previewing.kind == "gallery" then
        apply_text = _("Install")
    end
    local btn_apply = TextWidget:new{
        text = apply_text,
        face = Font:getFace("infofont", 16),
        forced_height = row_height,
        forced_baseline = baseline,
        bold = true,
        fgcolor = self.previewing and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
    }
    local btn_apply_ic = InputContainer:new{
        dimen = Geom:new{ w = math.floor(width / 2), h = row_height },
        CenterContainer:new{
            dimen = Geom:new{ w = math.floor(width / 2), h = row_height },
            btn_apply,
        },
    }
    btn_apply_ic.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = btn_apply_ic.dimen } },
    }
    btn_apply_ic.onTapSelect = function()
        if self.previewing then self.applyCurrent() end
        return true
    end

    table.insert(vg, LineWidget:new{
        background = Blitbuffer.COLOR_BLACK,
        dimen = Geom:new{ w = width, h = Size.line.thick },
    })
    table.insert(vg, HorizontalGroup:new{ btn_close_ic, btn_apply_ic })

    -- Outer frame + center
    local frame = FrameContainer:new{
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        vg,
    }
    local wc = CenterContainer:new{
        dimen = Screen:getSize(),
        frame,
    }
    self.modal_widget = wc
    UIManager:show(wc)
end

function PresetManagerModal._renderLocalRows(self, vg, width, row_height, font_size, baseline, left_pad)
    -- "+ Save current as preset" row
    local plus = TextWidget:new{
        text = "+ " .. _("Save current as preset"),
        face = Font:getFace("infofont", 16),
        forced_height = row_height,
        forced_baseline = baseline,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local plus_ic = InputContainer:new{
        dimen = Geom:new{ w = width, h = row_height },
        HorizontalGroup:new{ HorizontalSpan:new{ width = left_pad }, plus },
    }
    plus_ic.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = plus_ic.dimen } } }
    plus_ic.onTapSelect = function() PresetManagerModal._saveCurrentAsPreset(self); return true end
    table.insert(vg, plus_ic)

    -- Virtual "(No overlay)" row
    PresetManagerModal._addRow(self, vg, width, row_height, font_size, baseline, left_pad, {
        display = _("(No overlay)"),
        star_key = "_empty",
        on_preview = function() self.previewBlank() end,
        is_virtual = true,
    })

    -- Real presets
    local presets = self.bookends:readPresetFiles()
    for _, p in ipairs(presets) do
        local by = p.preset.author and (" — " .. p.preset.author) or ""
        PresetManagerModal._addRow(self, vg, width, row_height, font_size, baseline, left_pad, {
            display = p.name .. by,
            star_key = p.filename,
            on_preview = function() self.previewLocal(p) end,
            is_virtual = false,
            entry = p,
        })
    end
end

function PresetManagerModal._addRow(self, vg, width, row_height, font_size, baseline, left_pad, opts)
    local starred = PresetManagerModal._isStarred(self, opts.star_key)
    local star_widget = TextWidget:new{
        text = starred and "\xE2\x98\x85" or "\xE2\x98\x86",  -- ★ or ☆
        face = Font:getFace("infofont", 18),
        forced_height = row_height,
        forced_baseline = baseline,
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local star_width = Screen:scaleBySize(40)
    local star_ic = InputContainer:new{
        dimen = Geom:new{ w = star_width, h = row_height },
        CenterContainer:new{ dimen = Geom:new{ w = star_width, h = row_height }, star_widget },
    }
    star_ic.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = star_ic.dimen } } }
    local key = opts.star_key
    star_ic.onTapSelect = function() self.toggleStar(key); return true end

    local name_widget = TextWidget:new{
        text = opts.display,
        face = Font:getFace("cfont", font_size),
        forced_height = row_height,
        forced_baseline = baseline,
        max_width = width - 2 * left_pad - star_width,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local name_ic = InputContainer:new{
        dimen = Geom:new{ w = width - 2 * left_pad - star_width, h = row_height },
        name_widget,
    }
    name_ic.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = name_ic.dimen } } }
    name_ic.onTapSelect = function() opts.on_preview(); return true end

    table.insert(vg, HorizontalGroup:new{
        HorizontalSpan:new{ width = left_pad },
        star_ic,
        name_ic,
    })
end

function PresetManagerModal._saveCurrentAsPreset(self)
    local dlg
    dlg = InputDialog:new{
        title = _("Save preset"),
        input = "",
        input_hint = _("Preset name"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local name = dlg:getInputText()
                if name and name ~= "" then
                    local preset = self.bookends:buildPreset()
                    preset.name = name
                    local filename = self.bookends:writePresetFile(name, preset)
                    self.bookends:setActivePresetFilename(filename)
                    -- Add to cycle by default
                    local cycle = self.bookends.settings:readSetting("preset_cycle") or {}
                    table.insert(cycle, filename)
                    self.bookends.settings:saveSetting("preset_cycle", cycle)
                end
                UIManager:close(dlg)
                self.rebuild()
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

return PresetManagerModal
```

- [ ] **Step 2: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/menu/preset_manager_modal.lua
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add menu/preset_manager_modal.lua
git commit -m "$(cat <<'EOF'
feat(preset-manager): create central modal widget (Local tab)

New menu/preset_manager_modal.lua provides the central-aligned modal
with Local + Gallery tabs. Local tab is functional; Gallery is stubbed
for Phase 2.

Features shipped:
- Title + tab switcher, context-aware state header
- "+ Save current as preset" row
- Virtual "(No overlay)" row with star toggle
- Personal preset rows with star + tap-to-preview
- Snapshot + revert on Close
- Apply commits active_preset_filename
- Footer button label switches to "Install" for Gallery previews

Overflow actions (rename/edit/duplicate/delete) ship in a follow-up
task so this file stays reviewable.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Shrink presets_menu.lua to single entry point

**Files:** Modify `menu/presets_menu.lua`

- [ ] **Step 1: Replace the entire file**

Overwrite `menu/presets_menu.lua` with:

```lua
--- Single Presets menu entry — opens the Preset Manager modal.
local _ = require("i18n").gettext

return function(Bookends)

function Bookends:buildPresetsMenu()
    return {
        {
            text = _("Preset Manager…"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                if touchmenu_instance then
                    UIManager = require("ui/uimanager")
                    UIManager:close(touchmenu_instance)
                end
                local PresetManagerModal = require("menu/preset_manager_modal")
                PresetManagerModal.show(self)
            end,
        },
    }
end

end
```

- [ ] **Step 2: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/menu/presets_menu.lua
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add menu/presets_menu.lua
git commit -m "$(cat <<'EOF'
refactor(menu): replace Presets sub-menu with Preset Manager entry

The nested Built-in/Custom structure is gone. A single "Preset
Manager..." entry opens the new central modal.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Register onOpenPresetManager dispatcher action

**Files:** Modify `main.lua`

- [ ] **Step 1: Find the existing dispatcher action registration**

Run:
```bash
grep -n 'onDispatcherRegisterActions\|ToggleBookends\|CycleBookendsPreset' /home/andyhazz/projects/bookends.koplugin/main.lua | head -10
```

The existing registration adds "Toggle bookends" and "Cycle preset". Add "Open preset manager" alongside.

- [ ] **Step 2: Add the dispatcher action**

Find `function Bookends:onDispatcherRegisterActions()` (typically around line 148). Read the function body. It calls `Dispatcher:registerAction` for each gesture-able event. Add a new registration for `OpenPresetManager`:

```lua
    Dispatcher:registerAction("bookends_open_manager", {
        category = "none",
        event = "OpenPresetManager",
        title = _("Open preset manager"),
        general = true,
    })
```

Insert this near the existing registerAction calls.

- [ ] **Step 3: Add the event handler**

Add anywhere in `main.lua` (near other on-event handlers):

```lua
function Bookends:onOpenPresetManager()
    local PresetManagerModal = require("menu/preset_manager_modal")
    PresetManagerModal.show(self)
    return true
end
```

- [ ] **Step 4: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/main.lua
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add main.lua
git commit -m "$(cat <<'EOF'
feat(preset-manager): register 'Open preset manager' gesture action

Users can now bind a gesture to open the modal directly. Registered
alongside the existing 'Toggle bookends' and 'Cycle preset' actions
via the standard KOReader dispatcher.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Overflow menu actions (rename / edit description / duplicate / delete)

**Files:** Modify `menu/preset_manager_modal.lua`

- [ ] **Step 1: Add ⋯ button when previewing a Personal preset**

Edit `menu/preset_manager_modal.lua`. In `_rebuild`, the state header currently shows "Currently editing / Previewing". Extend the state row to include a tappable `⋯` when `self.previewing.kind == "local"`.

Find:

```lua
    local state_line = T(_("Currently editing: %1"), active_name)
    if self.previewing then
        state_line = state_line .. "  //  " .. T(_("Previewing: %1"), self.previewing.name)
    end
    table.insert(vg, LeftContainer:new{
        dimen = Geom:new{ w = width, h = row_height },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = left_pad },
            TextWidget:new{
                text = state_line,
                face = Font:getFace("cfont", 14),
                forced_height = row_height,
                forced_baseline = baseline,
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
    })
```

Replace with:

```lua
    local state_line = T(_("Currently editing: %1"), active_name)
    if self.previewing then
        state_line = state_line .. "  //  " .. T(_("Previewing: %1"), self.previewing.name)
    end
    local state_group = HorizontalGroup:new{
        HorizontalSpan:new{ width = left_pad },
        TextWidget:new{
            text = state_line,
            face = Font:getFace("cfont", 14),
            forced_height = row_height,
            forced_baseline = baseline,
            fgcolor = Blitbuffer.COLOR_BLACK,
        },
    }
    if self.previewing and self.previewing.kind == "local" then
        local overflow = TextWidget:new{
            text = "  \xE2\x8B\xAF",  -- ⋯
            face = Font:getFace("infofont", 18),
            forced_height = row_height,
            forced_baseline = baseline,
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        local overflow_ic = InputContainer:new{
            dimen = Geom:new{ w = Screen:scaleBySize(40), h = row_height },
            overflow,
        }
        overflow_ic.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = overflow_ic.dimen } } }
        overflow_ic.onTapSelect = function() self.openOverflow(); return true end
        table.insert(state_group, overflow_ic)
    end
    table.insert(vg, LeftContainer:new{
        dimen = Geom:new{ w = width, h = row_height },
        state_group,
    })
```

- [ ] **Step 2: Implement `_openOverflow`**

Add this function definition in `preset_manager_modal.lua`, before the `return PresetManagerModal` line:

```lua
function PresetManagerModal._openOverflow(self)
    if not self.previewing or self.previewing.kind ~= "local" then return end
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    local entry = self.previewing
    local dlg
    dlg = ButtonDialogTitle:new{
        title = entry.name,
        title_align = "center",
        buttons = {
            {{ text = _("Rename…"), callback = function()
                UIManager:close(dlg)
                PresetManagerModal._rename(self, entry)
            end }},
            {{ text = _("Edit description…"), callback = function()
                UIManager:close(dlg)
                PresetManagerModal._editDescription(self, entry)
            end }},
            {{ text = _("Duplicate"), callback = function()
                UIManager:close(dlg)
                PresetManagerModal._duplicate(self, entry)
            end }},
            {{ text = _("Delete"), callback = function()
                UIManager:close(dlg)
                PresetManagerModal._delete(self, entry)
            end }},
        },
    }
    UIManager:show(dlg)
end

function PresetManagerModal._rename(self, entry)
    local dlg
    dlg = InputDialog:new{
        title = _("Rename preset"),
        input = entry.name,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
            { text = _("Rename"), is_enter_default = true, callback = function()
                local new_name = dlg:getInputText()
                if new_name and new_name ~= "" and new_name ~= entry.name then
                    local new_filename = self.bookends:renamePresetFile(entry.filename, new_name)
                    if new_filename then
                        -- Update cycle list + active-preset pointer
                        local cycle = self.bookends.settings:readSetting("preset_cycle") or {}
                        for i, f in ipairs(cycle) do
                            if f == entry.filename then cycle[i] = new_filename; break end
                        end
                        self.bookends.settings:saveSetting("preset_cycle", cycle)
                        if self.bookends:getActivePresetFilename() == entry.filename then
                            self.bookends:setActivePresetFilename(new_filename)
                        end
                        -- Re-apply to refresh the preview cache
                        self.previewing = nil
                        self.bookends._previewing = false
                    end
                end
                UIManager:close(dlg)
                self.rebuild()
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function PresetManagerModal._editDescription(self, entry)
    local current = (entry.preset and entry.preset.description) or ""
    local dlg
    dlg = InputDialog:new{
        title = _("Edit description"),
        input = current,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local new_desc = dlg:getInputText() or ""
                local path = self.bookends:presetDir() .. "/" .. entry.filename
                local data = self.bookends.loadPresetFile(path)
                if data then
                    data.description = new_desc ~= "" and new_desc or nil
                    self.bookends:writePresetFile(data.name or entry.name, data)
                end
                UIManager:close(dlg)
                self.rebuild()
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function PresetManagerModal._duplicate(self, entry)
    local dlg
    local suggested = entry.name .. " (" .. _("copy") .. ")"
    dlg = InputDialog:new{
        title = _("Duplicate preset"),
        input = suggested,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local new_name = dlg:getInputText()
                if new_name and new_name ~= "" then
                    local path = self.bookends:presetDir() .. "/" .. entry.filename
                    local data = self.bookends.loadPresetFile(path)
                    if data then
                        data.name = new_name
                        self.bookends:writePresetFile(new_name, data)
                    end
                end
                UIManager:close(dlg)
                self.rebuild()
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function PresetManagerModal._delete(self, entry)
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete preset '%1'?"), entry.name),
        ok_text = _("Delete"),
        ok_callback = function()
            self.bookends:deletePresetFile(entry.filename)
            -- Remove from cycle
            local cycle = self.bookends.settings:readSetting("preset_cycle") or {}
            for i = #cycle, 1, -1 do
                if cycle[i] == entry.filename then table.remove(cycle, i) end
            end
            self.bookends.settings:saveSetting("preset_cycle", cycle)
            -- If the active preset was deleted, switch to next local preset (or detach)
            if self.bookends:getActivePresetFilename() == entry.filename then
                local remaining = self.bookends:readPresetFiles()
                if remaining[1] then
                    self.bookends:applyPresetFile(remaining[1].filename)
                else
                    self.bookends:setActivePresetFilename(nil)
                end
            end
            self.previewing = nil
            self.bookends._previewing = false
            self.bookends:markDirty()
            self.rebuild()
        end,
    })
end
```

- [ ] **Step 3: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/menu/preset_manager_modal.lua
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add menu/preset_manager_modal.lua
git commit -m "$(cat <<'EOF'
feat(preset-manager): overflow menu actions for Personal presets

Adds Rename, Edit description, Duplicate, and Delete via a header
⋯ button shown only when previewing a Personal preset. Delete
falls back to the next Local preset (or detaches if none remain).
Rename updates cycle membership + active pointer atomically.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 1 complete — optional checkpoint

At this point the plugin has:
- New Preset Manager modal (Local tab fully working)
- Autosave for active preset
- Star-based cycle model
- Virtual "(No overlay)" row
- Basic bookends starter + migration

Gallery tab shows "coming soon". The plugin is fully usable with just Phase 1; Phase 2 adds gallery browsing.

**Optional:** Push branch to test Phase 1 on-device before continuing. Revert to this commit if Phase 2 needs rework.

---

## Phase 2 — Gallery tab

Tasks 14–18.

## Task 14: Seed the `bookends-presets` GitHub repo (automated)

**Files:** None in the plugin repo. Extracts bundled presets from the plugin's master branch, creates a fresh gallery repo, and pushes. Requires `gh` CLI authenticated with `repo` scope (verified before starting).

- [ ] **Step 1: Prepare seed directory with README, presets, and index.json via a Lua helper**

Run this as one command block:

```bash
set -e
SEED_DIR=/tmp/bookends-presets-seed
rm -rf "$SEED_DIR"
mkdir -p "$SEED_DIR/presets"

# Write README first
cat > "$SEED_DIR/README.md" <<'MDEOF'
# bookends-presets

Community preset gallery for the [bookends KOReader plugin](https://github.com/AndyHazz/bookends.koplugin).

## Submitting a preset

1. Fork this repo.
2. Add your preset `.lua` file under `presets/`. Use a lowercase-with-dashes slug for the filename.
3. Add a matching entry to `index.json` (`slug`, `name`, `author`, `description`, `added`, `preset_url`).
4. Open a pull request.

Required fields on every preset:
- `name` (string): display name shown in the bookends picker
- `author` (string): your handle or name
- `description` (string): one-line summary

See the [preset schema](https://github.com/AndyHazz/bookends.koplugin/blob/master/preset_manager.lua) for the full format.
MDEOF

# Extract and serialize the four bundled presets via a self-contained Lua script.
# Uses a gettext shim (_) so the preset table evaluates outside KOReader.
lua5.1 <<'LUAEOF'
_ = function(s) return s end

local f = assert(io.open("/home/andyhazz/projects/bookends.koplugin/main.lua", "r"))
local src = f:read("*a"); f:close()
local block = assert(src:match("Bookends%.BUILT_IN_PRESETS%s*=%s*(%b{})"),
    "BUILT_IN_PRESETS block not found in main.lua")
local fn = assert(load("return " .. block))
local presets = fn()

local function slugify(s)
    return (s:lower():gsub("[^%w]", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", ""))
end

local function serialize(v, indent)
    indent = indent or ""
    local next_indent = indent .. "    "
    if type(v) == "table" then
        local parts = {"{\n"}
        local int_keys, str_keys = {}, {}
        for k in pairs(v) do
            if type(k) == "number" then table.insert(int_keys, k) else table.insert(str_keys, k) end
        end
        table.sort(int_keys)
        table.sort(str_keys)
        local is_contig = #int_keys > 0 and int_keys[#int_keys] == #int_keys
        for _, k in ipairs(int_keys) do
            if is_contig then
                table.insert(parts, next_indent .. serialize(v[k], next_indent) .. ",\n")
            else
                table.insert(parts, next_indent .. "[" .. k .. "] = " .. serialize(v[k], next_indent) .. ",\n")
            end
        end
        for _, k in ipairs(str_keys) do
            local key_str = k:match("^[%a_][%w_]*$") and k or ("[" .. string.format("%q", k) .. "]")
            table.insert(parts, next_indent .. key_str .. " = " .. serialize(v[k], next_indent) .. ",\n")
        end
        table.insert(parts, indent .. "}")
        return table.concat(parts)
    elseif type(v) == "string" then
        return string.format("%q", v)
    else
        return tostring(v)
    end
end

local DESCRIPTIONS = {
    ["Classic alternating"] = "Book title on even pages, chapter on odd, page number at bottom",
    ["Rich detail"] = "Clock, battery, Wi-Fi, brightness, highlights — the full kitchen sink",
    ["Speed reader"] = "Session timer, reading speed, time remaining, progress percentages",
    ["SimpleUI status bar"] = "Compact top-right status bar in the simpleui style",
}

local function jsonstr(s)
    return '"' .. (s:gsub('\\', '\\\\'):gsub('"', '\\"')) .. '"'
end

local index_parts = {
    "{\n",
    '  "schema_version": 1,\n',
    '  "updated": ' .. jsonstr(os.date("!%Y-%m-%dT%H:%M:%SZ")) .. ',\n',
    '  "presets": [\n',
}

for i, p in ipairs(presets) do
    local slug = slugify(p.name)
    local preset_data = {
        name = p.name,
        author = "andyhazz",
        description = DESCRIPTIONS[p.name] or "",
        enabled = p.preset.enabled,
        defaults = p.preset.defaults,
        positions = p.preset.positions,
    }
    local out = assert(io.open("/tmp/bookends-presets-seed/presets/" .. slug .. ".lua", "w"))
    out:write("-- Bookends preset: " .. p.name .. "\n")
    out:write("return " .. serialize(preset_data) .. "\n")
    out:close()

    table.insert(index_parts, "    {\n")
    table.insert(index_parts, '      "slug": ' .. jsonstr(slug) .. ",\n")
    table.insert(index_parts, '      "name": ' .. jsonstr(p.name) .. ",\n")
    table.insert(index_parts, '      "author": "andyhazz",\n')
    table.insert(index_parts, '      "description": ' .. jsonstr(DESCRIPTIONS[p.name] or "") .. ",\n")
    table.insert(index_parts, '      "added": ' .. jsonstr(os.date("!%Y-%m-%d")) .. ",\n")
    table.insert(index_parts, '      "preset_url": ' .. jsonstr("presets/" .. slug .. ".lua") .. "\n")
    table.insert(index_parts, "    }" .. (i < #presets and "," or "") .. "\n")
end
table.insert(index_parts, "  ]\n}\n")

local jf = assert(io.open("/tmp/bookends-presets-seed/index.json", "w"))
jf:write(table.concat(index_parts))
jf:close()
print("wrote " .. #presets .. " presets and index.json")
LUAEOF

# Verify
ls -la "$SEED_DIR" "$SEED_DIR/presets"
```

Expected: Lua prints `wrote 4 presets and index.json`. The listing shows `README.md`, `index.json`, and four `.lua` files under `presets/`.

- [ ] **Step 2: Create the GitHub repo**

Run:
```bash
cd /tmp/bookends-presets-seed
git init
git add README.md index.json presets
git commit -m "Initial gallery seed — four presets migrated from the bookends plugin"
gh repo create AndyHazz/bookends-presets --public --source=. --remote=origin --push \
  --description "Community preset gallery for the bookends KOReader plugin"
```

Expected: the repo exists at `https://github.com/AndyHazz/bookends-presets` with the seed commit.

- [ ] **Step 3: Verify the raw URL resolves**

Run:
```bash
curl -s https://raw.githubusercontent.com/AndyHazz/bookends-presets/main/index.json | head -20
```

Expected: the JSON content prints. If `main` doesn't work, try `master` (gh's default branch setting) and update `preset_gallery.lua`'s URL constants if needed.

- [ ] **Step 4: Clean up the seed directory**

```bash
rm -rf /tmp/bookends-presets-seed
```

---

## Task 15: Create `preset_gallery.lua` — HTTP + cache layer

**Files:** Create `preset_gallery.lua`

- [ ] **Step 1: Write the file**

Create `/home/andyhazz/projects/bookends.koplugin/preset_gallery.lua`:

```lua
--- Preset Gallery: fetch remote index + preset files, cache to disk.
-- Mirrors updater.lua's HTTP pattern (LuaSocket + curl fallback).

local DataStorage = require("datastorage")
local logger = require("logger")

local Gallery = {}

local INDEX_URL = "https://raw.githubusercontent.com/AndyHazz/bookends-presets/main/index.json"
local BASE_URL  = "https://raw.githubusercontent.com/AndyHazz/bookends-presets/main/"
local CACHE_TTL = 24 * 3600  -- 24h

-- Session in-memory cache of downloaded preset data
local _preset_cache = {}

local function cacheDir()
    local dir = DataStorage:getSettingsDir() .. "/bookends_gallery_cache"
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(dir, "mode") ~= "directory" then
        lfs.mkdir(dir)
    end
    return dir
end

local function httpGet(url, user_agent)
    local ok_require, http, ltn12, socket, socketutil = pcall(function()
        return require("socket/http"), require("ltn12"), require("socket"), require("socketutil")
    end)
    if ok_require then
        local body = {}
        local ok_req, code = pcall(function()
            socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
            local c = socket.skip(1, http.request({
                url = url,
                method = "GET",
                headers = { ["User-Agent"] = user_agent },
                sink = ltn12.sink.table(body),
                redirect = true,
            }))
            socketutil:reset_timeout()
            return c
        end)
        if ok_req and code == 200 then return table.concat(body) end
        pcall(function() socketutil:reset_timeout() end)
    end
    -- curl fallback
    local handle = io.popen(string.format("curl -s -L -H 'User-Agent: %s' %q", user_agent, url))
    if handle then
        local body = handle:read("*a")
        handle:close()
        if body and body ~= "" then return body end
    end
    return nil
end

function Gallery.isOnline()
    local NetworkMgr = require("ui/network/manager")
    return NetworkMgr:isWifiOn() and NetworkMgr:isConnected()
end

function Gallery.getCacheTimestamp()
    local lfs = require("libs/libkoreader-lfs")
    local ts_path = cacheDir() .. "/index.timestamp"
    local f = io.open(ts_path, "r")
    if not f then return nil end
    local ts = tonumber(f:read("*l"))
    f:close()
    return ts
end

function Gallery.getCachedIndex()
    local path = cacheDir() .. "/index.json"
    local f = io.open(path, "r")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    local ok, json = pcall(require, "json")
    if not ok then return nil end
    local ok2, data = pcall(json.decode, body)
    if ok2 then return data end
    return nil
end

function Gallery.fetchIndex(user_agent, callback)
    if not Gallery.isOnline() then
        callback(nil, "offline")
        return
    end
    local body = httpGet(INDEX_URL, user_agent or "KOReader-Bookends")
    if not body then
        callback(nil, "fetch failed")
        return
    end
    local ok_req, json = pcall(require, "json")
    if not ok_req then callback(nil, "json module missing"); return end
    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= "table" or type(data.presets) ~= "table" then
        callback(nil, "invalid index")
        return
    end
    -- Cache
    local path = cacheDir() .. "/index.json"
    local f = io.open(path, "w")
    if f then f:write(body); f:close() end
    local ts_file = io.open(cacheDir() .. "/index.timestamp", "w")
    if ts_file then ts_file:write(tostring(os.time())); ts_file:close() end
    callback(data, nil)
end

function Gallery.downloadPreset(slug, preset_url, user_agent, callback)
    if _preset_cache[slug] then
        callback(_preset_cache[slug], nil)
        return
    end
    if not Gallery.isOnline() then
        callback(nil, "offline")
        return
    end
    local body = httpGet(BASE_URL .. preset_url, user_agent or "KOReader-Bookends")
    if not body then callback(nil, "fetch failed"); return end
    -- Sandboxed load to evaluate the Lua preset
    local fn, err = loadstring(body)
    if not fn then callback(nil, "parse error: " .. tostring(err)); return end
    setfenv(fn, {})
    local ok, preset = pcall(fn)
    if not ok or type(preset) ~= "table" then
        callback(nil, "runtime error")
        return
    end
    _preset_cache[slug] = preset
    callback(preset, nil)
end

function Gallery.clearCache()
    _preset_cache = {}
end

return Gallery
```

- [ ] **Step 2: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/preset_gallery.lua
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add preset_gallery.lua
git commit -m "$(cat <<'EOF'
feat(gallery): HTTP + cache module for remote preset catalog

fetchIndex retrieves and caches the gallery index.json; downloadPreset
fetches and sandboxes-parses individual preset files. Mirrors
updater.lua's LuaSocket + curl fallback pattern. Cache lives at
<settings_dir>/bookends_gallery_cache/ with a timestamp sidecar.

Session in-memory cache prevents re-downloading the same preset on
repeat preview taps.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: Wire Gallery tab into the modal

**Files:** Modify `menu/preset_manager_modal.lua`

- [ ] **Step 1: Add state + fetch logic**

Edit `menu/preset_manager_modal.lua`. In the `show` function, extend the state table:

Find:

```lua
    local self = {
        bookends = bookends,
        tab = "local",        -- "local" or "gallery"
        page = 1,
        previewing = nil,
        original_settings = nil,
        modal_widget = nil,
    }
```

Replace with:

```lua
    local self = {
        bookends = bookends,
        tab = "local",        -- "local" or "gallery"
        page = 1,
        previewing = nil,
        original_settings = nil,
        modal_widget = nil,
        gallery_index = nil,  -- {presets = {...}} or nil
        gallery_loading = false,
        gallery_error = nil,  -- "offline", "fetch failed", nil
    }
```

Add a `fetchGallery` closure:

```lua
    self.fetchGallery = function(force)
        if self.gallery_loading then return end
        if self.gallery_index and not force then return end
        local Gallery = require("preset_gallery")
        local cached = Gallery.getCachedIndex()
        if cached and not force then
            self.gallery_index = cached
        end
        self.gallery_loading = true
        self.rebuild()
        Gallery.fetchIndex("KOReader-Bookends/" .. (bookends.version or "dev"), function(idx, err)
            self.gallery_loading = false
            if idx then
                self.gallery_index = idx
                self.gallery_error = nil
            else
                self.gallery_error = err
            end
            self.rebuild()
        end)
    end
```

Modify `setTab` to trigger fetch on first entry to Gallery:

Find:

```lua
    self.setTab = function(tab)
        if self.tab ~= tab then self.tab = tab; self.page = 1; self.rebuild() end
    end
```

Replace with:

```lua
    self.setTab = function(tab)
        if self.tab ~= tab then
            self.tab = tab
            self.page = 1
            if tab == "gallery" then self.fetchGallery(false) end
            self.rebuild()
        end
    end
```

- [ ] **Step 2: Replace the Gallery stub with real rendering**

In `_rebuild`, replace this block:

```lua
    else
        -- Gallery stub (Phase 2 will replace this)
        table.insert(vg, LeftContainer:new{
            dimen = Geom:new{ w = width, h = row_height * 3 },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = left_pad },
                TextWidget:new{
                    text = _("Gallery — coming soon"),
                    face = Font:getFace("infofont", 16),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            },
        })
    end
```

With:

```lua
    else
        PresetManagerModal._renderGalleryRows(self, vg, width, row_height, font_size, baseline, left_pad)
    end
```

- [ ] **Step 3: Implement `_renderGalleryRows` and preview/install for Gallery entries**

Add before `return PresetManagerModal`:

```lua
function PresetManagerModal._renderGalleryRows(self, vg, width, row_height, font_size, baseline, left_pad)
    if self.gallery_loading and not self.gallery_index then
        table.insert(vg, LeftContainer:new{
            dimen = Geom:new{ w = width, h = row_height },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = left_pad },
                TextWidget:new{
                    text = _("Loading gallery…"),
                    face = Font:getFace("cfont", 16),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            },
        })
        return
    end
    if self.gallery_error and not self.gallery_index then
        local msg = self.gallery_error == "offline"
            and _("Gallery requires an internet connection")
            or _("Gallery data is temporarily unavailable")
        table.insert(vg, LeftContainer:new{
            dimen = Geom:new{ w = width, h = row_height * 2 },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = left_pad },
                TextWidget:new{
                    text = msg,
                    face = Font:getFace("cfont", 16),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            },
        })
        return
    end
    if not self.gallery_index or not self.gallery_index.presets then return end

    -- Build local-preset-name set for ✓ indicator
    local local_names = {}
    for _, p in ipairs(self.bookends:readPresetFiles()) do local_names[p.name] = true end

    for _, entry in ipairs(self.gallery_index.presets) do
        local check = local_names[entry.name] and "\xE2\x9C\x93 " or "  "
        local by = entry.author and (" — " .. entry.author) or ""
        PresetManagerModal._addGalleryRow(self, vg, width, row_height, font_size, baseline, left_pad,
            entry, check .. entry.name .. by)
    end
end

function PresetManagerModal._addGalleryRow(self, vg, width, row_height, font_size, baseline, left_pad, entry, display)
    -- Gallery rows have no star (cycle only contains local presets)
    local name_widget = TextWidget:new{
        text = display,
        face = Font:getFace("cfont", font_size),
        forced_height = row_height,
        forced_baseline = baseline,
        max_width = width - 2 * left_pad,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local name_ic = InputContainer:new{
        dimen = Geom:new{ w = width - 2 * left_pad, h = row_height },
        name_widget,
    }
    name_ic.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = name_ic.dimen } } }
    name_ic.onTapSelect = function()
        PresetManagerModal._previewGallery(self, entry)
        return true
    end
    table.insert(vg, HorizontalGroup:new{
        HorizontalSpan:new{ width = left_pad },
        name_ic,
    })
end

function PresetManagerModal._previewGallery(self, entry)
    local Gallery = require("preset_gallery")
    Gallery.downloadPreset(entry.slug, entry.preset_url,
        "KOReader-Bookends/" .. (self.bookends.version or "dev"),
        function(data, err)
            if not data then
                Notification:notify(T(_("Couldn't download '%1'."), entry.name))
                return
            end
            -- Validate
            local clean, verr = self.bookends.validatePreset(data)
            if not clean then
                Notification:notify(_("This preset appears invalid; skipping."))
                require("logger").warn("bookends gallery: invalid preset", entry.slug, verr)
                return
            end
            self.bookends._previewing = true
            local ok = pcall(self.bookends.loadPreset, self.bookends, clean)
            if not ok then
                self.bookends._previewing = false
                Notification:notify(_("Could not preview preset"))
                return
            end
            self.previewing = { kind = "gallery", name = entry.name, entry = entry, data = clean }
            self.bookends:markDirty()
            self.rebuild()
        end)
end
```

- [ ] **Step 4: Extend `_applyCurrent` to handle gallery installs**

Find `_applyCurrent` and replace with:

```lua
function PresetManagerModal._applyCurrent(self)
    if not self.previewing then return end
    if self.previewing.kind == "local" then
        self.bookends:setActivePresetFilename(self.previewing.filename)
    elseif self.previewing.kind == "blank" then
        self.bookends:setActivePresetFilename(nil)
    elseif self.previewing.kind == "gallery" then
        -- Install: write to bookends_presets/ and make active.
        -- Collision handling: prompt if name already exists.
        local entry = self.previewing.entry
        local data = self.previewing.data
        local existing
        for _, p in ipairs(self.bookends:readPresetFiles()) do
            if p.name == entry.name then existing = p; break end
        end
        if existing then
            PresetManagerModal._promptInstallCollision(self, existing, data, entry)
            return  -- flow continues after user choice
        end
        local filename = self.bookends:writePresetFile(entry.name, data)
        self.bookends:setActivePresetFilename(filename)
    end
    self.bookends._previewing = false
    self.previewing = nil
    if self.modal_widget then
        UIManager:close(self.modal_widget)
        self.modal_widget = nil
    end
    self.bookends:markDirty()
end

function PresetManagerModal._promptInstallCollision(self, existing, data, entry)
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    local dlg
    dlg = ButtonDialogTitle:new{
        title = T(_("A preset called '%1' already exists."), entry.name),
        title_align = "center",
        buttons = {
            {{ text = _("Overwrite"), callback = function()
                UIManager:close(dlg)
                self.bookends:deletePresetFile(existing.filename)
                local filename = self.bookends:writePresetFile(entry.name, data)
                self.bookends:setActivePresetFilename(filename)
                self.bookends._previewing = false
                self.previewing = nil
                UIManager:close(self.modal_widget)
                self.modal_widget = nil
                self.bookends:markDirty()
            end }},
            {{ text = _("Rename…"), callback = function()
                UIManager:close(dlg)
                local input
                input = InputDialog:new{
                    title = _("Install as"),
                    input = entry.name .. " (2)",
                    buttons = {{
                        { text = _("Cancel"), id = "close",
                          callback = function() UIManager:close(input); self.rebuild() end },
                        { text = _("Install"), is_enter_default = true, callback = function()
                            local new_name = input:getInputText()
                            if new_name and new_name ~= "" then
                                data.name = new_name
                                local filename = self.bookends:writePresetFile(new_name, data)
                                self.bookends:setActivePresetFilename(filename)
                            end
                            self.bookends._previewing = false
                            self.previewing = nil
                            UIManager:close(input)
                            UIManager:close(self.modal_widget)
                            self.modal_widget = nil
                            self.bookends:markDirty()
                        end },
                    }},
                }
                UIManager:show(input)
                input:onShowKeyboard()
            end }},
            {{ text = _("Cancel"), callback = function()
                UIManager:close(dlg)
                self.rebuild()
            end }},
        },
    }
    UIManager:show(dlg)
end
```

- [ ] **Step 5: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/menu/preset_manager_modal.lua
```
Expected: no output.

- [ ] **Step 6: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add menu/preset_manager_modal.lua
git commit -m "$(cat <<'EOF'
feat(gallery): wire Gallery tab into Preset Manager modal

Lazy-fetch on first Gallery tab activation. Offline / loading /
error states rendered inline. ✓ indicator on rows matching a local
preset name. Preview downloads the preset file and applies live;
Install writes to bookends_presets/ + makes active. Name-collision
flow prompts Overwrite / Rename / Cancel.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 17: README update

**Files:** Modify `README.md`

- [ ] **Step 1: Rewrite the Presets section**

Edit `README.md`. Find the "Built-in presets" section (around line 45-52). The section currently reads:

```markdown
### Built-in presets

Three presets are included to get you started — load one and customise from there:

- **Speed Reader** — Session timer, reading speed, time remaining, progress percentages
- **Classic Alternating** — Book title on even pages, chapter on odd, page number at bottom
- **Rich Detail** — All six positions with clock, battery, Wi-Fi, brightness, highlights, and more

Save your own presets via **Presets > Custom presets > Create new preset from current settings**.
```

Replace with:

```markdown
### Preset Manager

Open **Bookends → Presets → Preset Manager…** (or bind the "Open preset manager" gesture) for a single modal that handles everything: creating, editing, starring for the cycle gesture, and browsing community presets from an online Gallery.

**Local tab** — your presets. Tap any row to preview it live on your overlay. Apply to commit; Close to revert. Tap the star on the left to add/remove from the cycle gesture. Use "+ Save current as preset" to snapshot your current overlay. When a preset is "active", your subsequent overlay edits autosave back to the file — no separate save step.

**Gallery tab** — community presets from [AndyHazz/bookends-presets](https://github.com/AndyHazz/bookends-presets). Tap to preview, tap Install to save locally. Presets already installed on your device show a ✓ indicator.

**Cycle gesture** — bind "Cycle preset" to any gesture, then star the presets you want in the rotation. An optional "(No overlay)" slot lets you cycle through a blank state if you want.
```

- [ ] **Step 2: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add README.md
git commit -m "$(cat <<'EOF'
docs(readme): replace Built-in presets section with Preset Manager

Describes the new unified modal (Local + Gallery tabs), autosave
editing model, and star-based cycle.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 18: Final verification

**Files:** None — read-only checks.

- [ ] **Step 1: Syntax-check all modified Lua files together**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
luac -p main.lua preset_manager.lua preset_gallery.lua basic_bookends.lua menu/preset_manager_modal.lua menu/presets_menu.lua config.lua
```
Expected: no output for any file.

- [ ] **Step 2: Review commit history**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin log --oneline master..feature/preset-manager
```
Expected: ~15 commits spanning tasks 2-17. Task 1 created the branch; Task 14 is external (gallery repo); Task 18 does no commits.

- [ ] **Step 3: Review the diff against master**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin diff master..feature/preset-manager --stat
```
Expected: ~7 files changed — `main.lua` (net reduction), `preset_manager.lua`, `menu/presets_menu.lua` (net reduction), `config.lua`, `README.md`, plus new `preset_gallery.lua`, `menu/preset_manager_modal.lua`, `basic_bookends.lua`.

- [ ] **Step 4: Grep for stale BUILT_IN_PRESETS references**

Run:
```bash
grep -rn --include="*.lua" 'BUILT_IN_PRESETS' /home/andyhazz/projects/bookends.koplugin --exclude-dir=.claude
```
Expected: no output.

- [ ] **Step 5: Grep for stale last_cycled_preset references**

Run:
```bash
grep -rn --include="*.lua" 'last_cycled_preset' /home/andyhazz/projects/bookends.koplugin --exclude-dir=.claude
```
Expected: references only in the migration code (`config.lua` legacy list, `preset_manager.lua` migration function).

---

## Manual verification checklist (post-implementation, on-device)

Not part of the TDD task loop. After pushing files to Kindle and restarting KOReader:

**Phase 1:**

1. Open menu → Presets → Preset Manager... — modal opens, Local tab default.
2. "+ Save current as preset" works — prompts for name, new row appears.
3. Star toggles on/off — persist across modal close/reopen.
4. Tap a Personal preset row — overlay updates live, "Previewing: X" appears.
5. Tap Close — overlay reverts to pre-preview state.
6. Tap Apply — overlay commits, "Currently editing: X" updates, modal closes.
7. Edit font size in the regular menu → close menu → overlay reflects change → peek at the preset file (`/mnt/us/koreader/settings/bookends_presets/<filename>.lua`) and confirm font_size updated.
8. Long-press the old way fails gracefully — there's no menu to long-press; the action is gone.
9. Star "(No overlay)" + cycle gesture → cycle lands on blank overlay.
10. Overflow ⋯ menu: rename, edit description, duplicate, delete — each works and cycle/active pointers stay in sync.
11. Delete the active preset → next Local becomes active.
12. Fresh install (delete `bookends_presets/`): on plugin reload, Basic bookends appears + is active.

**Phase 2:**

13. Switch to Gallery tab — index fetches, list populates.
14. Tap a Gallery row — preset downloads + overlay previews live.
15. Tap Install — saves to `bookends_presets/`, ✓ indicator appears on that row next visit.
16. Switch to airplane mode → Gallery tab still shows cached list with banner.
17. Try installing a preset with a name that matches an existing one — collision dialog appears with Overwrite / Rename / Cancel.
