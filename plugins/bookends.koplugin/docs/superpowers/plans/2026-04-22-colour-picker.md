# v4.3.0 Colour Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an HSV colour-wheel picker for every Bookends colour setting on colour-capable e-ink devices, with greyscale-device luminance fallback at paint time and no data migration for existing presets. Ships as v4.3.0 behind a v4.3.0-rc1 pre-release for Kaleido tester feedback.

**Architecture:** `{hex="#RRGGBB"}` is added as a new storage shape discriminated from the existing `{grey=N}` (text/symbol) and raw-byte (bar_colors) shapes by field presence. A central `Colour` helper module holds `parseColorValue(v)` with a memoised hex → `Blitbuffer.ColorRGB32` / `Color8(luminance)` cache, flushed whenever the user toggles KOReader's colour-rendering mode. Menu-side, a single `Screen:isColorEnabled()` branch in `colorNudge`/`textColorPickerOrNudge` swaps the existing `% black` nudge for the new picker — all 10 colour-setting call-sites get the feature automatically via 3 helper functions. The colour-wheel widget itself is ported (unchanged in behaviour, wrapped to plugin dialog conventions) from `appearance.koplugin` under GPL-3.0 with attribution in README, release notes, and file header.

**Tech Stack:** Lua 5.1 (LuaJIT), KOReader widget framework (`Blitbuffer`, `Device:screen()`, `UIManager`, `ButtonDialog`, `InputContainer`), `ffi/blitbuffer` (`ColorRGB32`, `Color8`, `paintRect`, `paintCircle`), `bookends_i18n` for translatable strings, existing `_test_conditionals.lua`-style in-plugin test runner.

**Assumptions / prerequisites (locked in at plan time):**

- Phase 1 (metro fill) has already landed on `master`: `bookends_overlay_widget.lua:922` already reads `colors.metro_fill`, the widget's `resolveColor` helper handles its absence, and `menu/colours_menu.lua:62-74` already has the "Metro read color" item. The plan treats `metro_fill` as just one more field in `bar_colors` — no special-casing during the port.
- Work happens on a **plain feature branch `feat/colour-picker`** on the main checkout. **Do not create a git worktree** (per `feedback_skip_worktrees.md` — the Kindle SCP dev loop is simpler from the main checkout).
- The **widget port is done without colour-device hardware** (`user_no_colour_device.md`). Primary correctness verification is **KOReader desktop** (`user_koreader_desktop_testing.md`), which exercises the full colour stack; final aesthetic validation is deferred to community testers via an explicit v4.3.0-rc1 pre-release.
- Deploy loop: **tar-pipe with excludes**, not plain `scp -r` (per `feedback_scp_exclude_tools.md`), and the user restarts KOReader manually after each push (per `feedback_killall_doesnt_reload.md`).
- In any file that imports gettext as `local _`, **never use `_` as a throwaway loop variable** — use `_i`, `_idx`, `_k` (per `feedback_gettext_shadowing.md`). The widget port will come from a different codebase where this convention may not hold; audit every loop header.
- Any new dialog widget that wraps a `CenterContainer` must **not reassign `self.dimen`** post-paint. If the widget exposes a visible-rect dimen for external observers (halo suppression, dogear userpatch), hang that on an **outer WidgetContainer shell**, not on the CenterContainer itself (per `feedback_centercontainer_dimen.md`). Verify as part of the port.

---

## File Structure

**New files:**

- `bookends_colour.lua` — module with `parseColorValue(v)`, `flushCache()`, `Colour.defaultHexFor(field)`. Required by both the overlay widget (paint side) and the colours menu (picker side). Small (~80 LoC), no UI dependencies.
- `bookends_colour_wheel.lua` — the HSV wheel widget itself, ported from appearance.koplugin. ~500 LoC. Holds the widget class, input handling, and the `showColourPicker` API function.
- `_test_colour.lua` — pure-Lua test runner in the same style as `_test_conditionals.lua`, covering `parseColorValue`.

**Modified files:**

- `_meta.lua` — version bump to `4.3.0` (and intermediate `4.3.0-rc1`).
- `main.lua` — attach the new helper, subscribe to the colour-rendering event, route `resolveBarColors` through `parseColorValue`, wire `showColourPicker` onto the `Bookends` class.
- `bookends_overlay_widget.lua` — route the 4 `cfg.text_color` / `cfg.symbol_color` call-sites through `parseColorValue` so hex works for text too.
- `menu/colours_menu.lua` — add `Screen:isColorEnabled()` branch in `colorNudge`; refactor the two inline `showNudgeDialog` calls in `buildTextColourMenu` to a shared `textColorPickerOrNudge` helper with the same branch.
- `preset_manager.lua` — detect hex values in `buildPreset()` output and set `metadata.has_colour = true` on the saved preset table. Hydrate `metadata.has_colour` from loaded presets so the gallery/local lists can show the 🎨 flag.
- `menu/preset_manager_modal.lua` — append a small " 🎨" glyph to the title-line `HorizontalGroup` in `_addRow` when `opts.has_colour` is true; pass `has_colour` through from both the local (line 490) and gallery (line 1295) render paths.
- `README.md` — new "Acknowledgements" section before "License" (line ~399) crediting appearance.koplugin + note on missing hardware.
- `docs/release-notes-4.3.0.md` — new file with feature summary, attribution block, tester call.
- `locale/bookends.pot` — regenerate with new translatable strings.
- `locale/*.po` (bg_BG, de, en_GB, es, fr, it, pt_BR) — add placeholder `msgstr ""` entries for the new strings.
- `.claude/skills/review-preset-submission/SKILL.md` — add a new "Colour-value usage" check section that scans for `hex = ` fields and logs the `metadata.has_colour` flag in the mechanical report.

---

## Task 1 — Groundwork: branch + version-bump rc1 scaffold

**Files:**
- Modify: `_meta.lua`

- [ ] **Step 1: Create feature branch**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git checkout -b feat/colour-picker
git status
```

Expected: `On branch feat/colour-picker` and a clean tree.

- [ ] **Step 2: Bump version to rc1 scaffold (non-functional commit, locks the identifier used by release-notes later)**

Change `_meta.lua` line 6 from:

```lua
    version = "4.2.0",
```

to:

```lua
    version = "4.3.0-rc1",
```

- [ ] **Step 3: Commit**

```bash
git add _meta.lua
git commit -m "chore: bump version to 4.3.0-rc1 scaffold for colour-picker work"
```

---

## Task 2 — Skeleton `bookends_colour.lua` with `parseColorValue` + cache

**Files:**
- Create: `bookends_colour.lua`

- [ ] **Step 1: Create `bookends_colour.lua` with the module skeleton, hex cache, and documented `parseColorValue` function**

```lua
--[[
Central colour-value helpers.

Every colour setting in Bookends (text_color, symbol_color, bar_colors.{fill,
bg, track, tick, border, invert, metro_fill}) can be stored in one of three
shapes:

  - table with .hex = "#RRGGBB"    -- v4.3+ colour-picker authoring
  - table with .grey = 0xNN        -- v2+ greyscale nudge (text/symbol)
  - raw byte 0..0xFF               -- legacy bar_colors shape (pre-v4)

parseColorValue folds all three into a Blitbuffer colour object:
  * Colour-enabled screens: hex → ColorRGB32, grey/byte → Color8.
  * Greyscale screens: hex → Color8 of the Rec.601 luminance (so presets
    authored on colour devices still render sensibly on Kindle/older Kobo).

The hex → colour conversion is memoised in a module-local table; toggling
KOReader's colour-rendering mode at runtime must call flushCache() to drop
stale ColorRGB32 values cached from the previous mode (ColorRGB32 on a now-
greyscale screen would go through Blitbuffer's default 32→8 converter rather
than our Rec.601 luminance helper, which looks subtly different on photos).
]]

local Blitbuffer = require("ffi/blitbuffer")

local Colour = {}

local _hex_cache = {}

-- Default hex for each field when the user taps "Default" in the picker.
-- nil means "clear the setting entirely" (fall back to the field's own
-- default-colour logic in the render path).
local DEFAULT_HEX = {
    fill        = "#404040",  -- matches the 75%-black greyscale default
    bg          = "#BFBFBF",  -- matches the 25%-black greyscale default
    track       = "#404040",
    tick        = "#000000",
    border      = "#000000",
    invert      = "#FFFFFF",
    metro_fill  = "#000000",
    text_color  = nil,        -- "book text colour" — clear rather than default
    symbol_color = nil,       -- "match text" — clear rather than default
}

function Colour.defaultHexFor(field) return DEFAULT_HEX[field] end

--- Parse a stored colour value into a Blitbuffer colour object.
--- Returns nil if v is nil, false if v is false (transparent).
function Colour.parseColorValue(v, is_color_enabled)
    if v == nil then return nil end
    if v == false then return false end

    if type(v) == "table" and v.hex then
        local key = v.hex .. (is_color_enabled and ":c" or ":g")
        local cached = _hex_cache[key]
        if cached then return cached end
        local hex = v.hex
        if hex:sub(1, 1) ~= "#" or #hex ~= 7 then return nil end
        local r = tonumber(hex:sub(2, 3), 16)
        local g = tonumber(hex:sub(4, 5), 16)
        local b = tonumber(hex:sub(6, 7), 16)
        if not (r and g and b) then return nil end
        local out
        if is_color_enabled then
            out = Blitbuffer.ColorRGB32(r, g, b, 0xFF)
        else
            -- Rec.601 luminance, rounded to 0..255.
            local lum = math.floor(0.299 * r + 0.587 * g + 0.114 * b + 0.5)
            out = Blitbuffer.Color8(lum)
        end
        _hex_cache[key] = out
        return out
    end

    if type(v) == "table" and v.grey then
        if v.grey >= 0xFF then return false end
        return Blitbuffer.Color8(v.grey)
    end

    if type(v) == "number" then
        if v >= 0xFF then return false end
        return Blitbuffer.Color8(v)
    end

    return nil
end

function Colour.flushCache()
    _hex_cache = {}
end

return Colour
```

- [ ] **Step 2: `luac -p` the new file**

```bash
luac -p bookends_colour.lua
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add bookends_colour.lua
git commit -m "feat(colour): add parseColorValue helper with hex→ColorRGB32/Color8 cache"
```

---

## Task 3 — Unit tests for `parseColorValue`

**Files:**
- Create: `_test_colour.lua`

- [ ] **Step 1: Write `_test_colour.lua` in the existing `_test_conditionals.lua`-style runner**

```lua
-- Dev-box test runner for bookends_colour.lua parseColorValue.
-- Runs pure-Lua (no KOReader) by stubbing ffi/blitbuffer with in-memory
-- constructors so we can assert on r/g/b/alpha without FFI.
-- Usage: cd into the plugin dir, then `lua _test_colour.lua`.
-- Exits non-zero on failure; no external dependencies.

package.loaded["ffi/blitbuffer"] = {
    ColorRGB32 = function(r, g, b, a)
        return { kind = "rgb32", r = r, g = g, b = b, a = a }
    end,
    Color8 = function(v)
        return { kind = "color8", v = v }
    end,
}

local Colour = dofile("bookends_colour.lua")

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
            .. " expected=" .. tostring(expected)
            .. " got=" .. tostring(actual), 2)
    end
end

-- --- nil / false passthrough ------------------------------------------------
test("nil → nil", function()
    eq(Colour.parseColorValue(nil, true), nil)
end)
test("false → false (transparent)", function()
    eq(Colour.parseColorValue(false, true), false)
end)

-- --- hex on colour-enabled screen ------------------------------------------
test("hex black on colour → ColorRGB32(0,0,0,255)", function()
    local c = Colour.parseColorValue({ hex = "#000000" }, true)
    eq(c.kind, "rgb32"); eq(c.r, 0); eq(c.g, 0); eq(c.b, 0); eq(c.a, 0xFF)
end)
test("hex purple on colour → ColorRGB32(127,8,255,255)", function()
    local c = Colour.parseColorValue({ hex = "#7F08FF" }, true)
    eq(c.kind, "rgb32"); eq(c.r, 0x7F); eq(c.g, 0x08); eq(c.b, 0xFF)
end)

-- --- hex on greyscale screen: Rec.601 luminance ----------------------------
test("hex white on greyscale → Color8(255)", function()
    local c = Colour.parseColorValue({ hex = "#FFFFFF" }, false)
    eq(c.kind, "color8"); eq(c.v, 255)
end)
test("hex pure red on greyscale → Color8(76)   [0.299 × 255 = 76.245]", function()
    local c = Colour.parseColorValue({ hex = "#FF0000" }, false)
    eq(c.kind, "color8"); eq(c.v, 76)
end)
test("hex pure green on greyscale → Color8(150) [0.587 × 255 = 149.685]", function()
    local c = Colour.parseColorValue({ hex = "#00FF00" }, false)
    eq(c.kind, "color8"); eq(c.v, 150)
end)

-- --- grey and raw-byte passthrough -----------------------------------------
test("{grey=0x40} → Color8(0x40) on colour and greyscale alike", function()
    local c1 = Colour.parseColorValue({ grey = 0x40 }, true)
    local c2 = Colour.parseColorValue({ grey = 0x40 }, false)
    eq(c1.v, 0x40); eq(c2.v, 0x40)
end)
test("{grey=0xFF} → false (transparent)", function()
    eq(Colour.parseColorValue({ grey = 0xFF }, true), false)
end)
test("raw byte 0x80 → Color8(0x80)", function()
    local c = Colour.parseColorValue(0x80, true)
    eq(c.v, 0x80)
end)
test("raw byte 0xFF → false (transparent)", function()
    eq(Colour.parseColorValue(0xFF, true), false)
end)

-- --- invalid input does not crash ------------------------------------------
test("hex with too few chars → nil (no crash)", function()
    eq(Colour.parseColorValue({ hex = "#FFF" }, true), nil)
end)
test("hex missing # → nil", function()
    eq(Colour.parseColorValue({ hex = "FFFFFF" }, true), nil)
end)
test("hex with non-hex chars → nil", function()
    eq(Colour.parseColorValue({ hex = "#ZZZZZZ" }, true), nil)
end)
test("empty table → nil", function()
    eq(Colour.parseColorValue({}, true), nil)
end)

-- --- cache behaviour: flushCache drops entries -----------------------------
test("flushCache drops memoised hex entries", function()
    local c1 = Colour.parseColorValue({ hex = "#123456" }, true)
    local c2 = Colour.parseColorValue({ hex = "#123456" }, true)
    if c1 ~= c2 then error("expected same memoised ref before flush") end
    Colour.flushCache()
    local c3 = Colour.parseColorValue({ hex = "#123456" }, true)
    if c3 == c1 then error("expected different ref after flush (new construction)") end
end)

-- --- cache key includes is_color_enabled (colour and greyscale differ) -----
test("cache is keyed on is_color_enabled — both kinds retained", function()
    local cc = Colour.parseColorValue({ hex = "#FF0000" }, true)
    local gg = Colour.parseColorValue({ hex = "#FF0000" }, false)
    eq(cc.kind, "rgb32"); eq(gg.kind, "color8")
end)

io.write(string.format("%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
```

- [ ] **Step 2: Run the test suite and confirm all pass**

```bash
cd /home/andyhazz/projects/bookends.koplugin
lua _test_colour.lua
```

Expected: `16 passed, 0 failed` (exit code 0).

- [ ] **Step 3: Commit**

```bash
git add _test_colour.lua
git commit -m "test(colour): cover parseColorValue hex, luminance, cache, invalid input"
```

---

## Task 4 — Route `resolveBarColors` through `parseColorValue`

**Files:**
- Modify: `main.lua:973-1001`

- [ ] **Step 1: Replace the local `colorOrTransparent` inside `resolveBarColors` with a delegation to the new helper, threading `Screen:isColorEnabled()` once**

Open `main.lua`. Find the block starting at line 973 (`--- Convert a settings-stored color value…`) and through line 1001 (closing `end` of the `return { … }`). Replace it with:

```lua
--- Convert a settings-stored color value (number, {grey=N}, {hex="#RRGGBB"},
--- false, or nil) to a Blitbuffer colour object (or false for transparent).
--- Delegates per-value parsing + memoisation to bookends_colour so hex → RGB
--- and greyscale-fallback are consistent with text_color / symbol_color.
local function resolveBarColors(bc)
    local Colour = require("bookends_colour")
    local is_color_enabled = Device:screen():isColorEnabled()
    local function cv(v) return Colour.parseColorValue(v, is_color_enabled) end
    return {
        fill = cv(bc.fill),
        bg = cv(bc.bg),
        track = cv(bc.track),
        tick = cv(bc.tick),
        border = cv(bc.border),
        invert = cv(bc.invert),
        metro_fill = cv(bc.metro_fill),
        invert_read_ticks = bc.invert_read_ticks,
        tick_height_pct = bc.tick_height_pct,
        border_thickness = bc.border_thickness,
    }
end
```

- [ ] **Step 2: Confirm `Device` is already required at file top**

```bash
grep -n "^local Device = require" main.lua | head -1
```

Expected: a line like `local Device = require("device")`. If it's not present (sanity check), add `local Device = require("device")` near the other top-of-file requires. (As of Phase 1 master it is already imported.)

- [ ] **Step 3: Byte-compile to catch typos**

```bash
luac -p main.lua
```

Expected: no output.

- [ ] **Step 4: Re-run the colour tests to confirm the helper still behaves after being called from the render path (smoke — they don't load main.lua, so this just confirms nothing was broken in the shared module)**

```bash
lua _test_colour.lua
```

Expected: `16 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add main.lua
git commit -m "refactor(colour): route resolveBarColors through parseColorValue"
```

---

## Task 5 — Route text/symbol colour through `parseColorValue`

**Files:**
- Modify: `bookends_overlay_widget.lua:258`, `:378`, `:412`, `:721`

- [ ] **Step 1: Add the colour module require and a cached `is_color_enabled` local at the top of `bookends_overlay_widget.lua`, just after the existing `local Blitbuffer = …` line**

Find the `local Blitbuffer = require("ffi/blitbuffer")` line near the top of `bookends_overlay_widget.lua` (use `grep -n "^local Blitbuffer" bookends_overlay_widget.lua` to locate it) and add immediately after it:

```lua
local Colour = require("bookends_colour")
local Device = require("device")
-- Helper: resolve a text/symbol colour table ({grey=N} or {hex=H}) to a
-- Blitbuffer colour object on the current screen. Returns nil when v is nil.
local function resolveTextColor(v)
    if v == nil then return nil end
    return Colour.parseColorValue(v, Device:screen():isColorEnabled())
end
```

- [ ] **Step 2: Replace each `cfg.text_color and Blitbuffer.Color8(cfg.text_color.grey) or nil` call with `resolveTextColor(cfg.text_color)`**

There are four exact call-sites (line numbers from pre-change `master`):

- `bookends_overlay_widget.lua:258`: `local text_fgcolor = cfg.text_color and Blitbuffer.Color8(cfg.text_color.grey) or nil` → `local text_fgcolor = resolveTextColor(cfg.text_color)`
- `bookends_overlay_widget.lua:378`: same pattern → same replacement
- `bookends_overlay_widget.lua:412`: same → same
- `bookends_overlay_widget.lua:721`: inside an `elseif cfg.text_color then` branch, `seg_fgcolor = Blitbuffer.Color8(cfg.text_color.grey)` → `seg_fgcolor = resolveTextColor(cfg.text_color)`

After each edit, re-grep to confirm no `cfg.text_color.grey` references remain:

```bash
grep -n "cfg.text_color.grey\|cfg.symbol_color.grey" bookends_overlay_widget.lua
```

Expected: no output.

- [ ] **Step 3: Repeat for `cfg.symbol_color` call-sites (if any)**

```bash
grep -n "cfg.symbol_color" bookends_overlay_widget.lua
```

Expected: shows the `cfg.symbol_color and Blitbuffer.Color8(cfg.symbol_color.grey)` lines if any. Replace each with `resolveTextColor(cfg.symbol_color)`. If grep returns no results (symbol_color is resolved in main.lua), skip this step.

- [ ] **Step 4: Byte-compile**

```bash
luac -p bookends_overlay_widget.lua
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add bookends_overlay_widget.lua
git commit -m "refactor(colour): route text/symbol paint through parseColorValue"
```

---

## Task 6 — Colour-rendering event subscription + cache flush

**Files:**
- Modify: `main.lua` (insert after `onSetDimensions`, around line 867)

KOReader broadcasts an event when the user toggles colour rendering. The event name is **unverified at plan time**. Implementation:

- [ ] **Step 1: Grep KOReader frontend for the broadcast site**

Locate the KOReader source on the dev box. Try these common paths:

```bash
for p in ~/koreader ~/projects/koreader /usr/lib/koreader /opt/koreader; do
  [ -d "$p/frontend" ] && echo "$p/frontend" && break
done
```

Assume the path is `$KOREADER_FRONTEND`. Then:

```bash
grep -rn "Broadcast\|UIManager:broadcastEvent\|isColorEnabled\b" "$KOREADER_FRONTEND" \
    | grep -iE "color|colour" | head -40
```

Expected: one or more events. Record the exact event name(s) — candidates include `ColorRenderingUpdate`, `ColorRenderingModeChanged`, `SetColorRendering`. Pick the one broadcast when the user toggles colour rendering in Settings → Screen. If multiple fire, subscribe to all relevant ones.

- [ ] **Step 2: If no reliable event exists, fall back to the defensive path: re-check `Screen:isColorEnabled()` at the top of `parseColorValue` and flush the cache on mismatch**

In `bookends_colour.lua`, change `parseColorValue` to track the last-seen mode and auto-flush:

```lua
local _last_mode = nil

function Colour.parseColorValue(v, is_color_enabled)
    if _last_mode ~= nil and _last_mode ~= is_color_enabled then
        _hex_cache = {}
    end
    _last_mode = is_color_enabled
    -- … existing body unchanged
end
```

Re-run `lua _test_colour.lua` to confirm tests still pass. (The flushCache test already exercises the same path — no new tests needed.) Skip the event subscription in Step 3 if taking this fallback; commit the defensive change with message `fix(colour): auto-flush cache on is_color_enabled toggle (no reliable event found)`.

- [ ] **Step 3: If an event was found in Step 1, subscribe to it in `main.lua`**

Open `main.lua`. After the existing `function Bookends:onSetDimensions() self:markDirty() end` at line 867, insert (replacing `<ACTUAL_EVENT_NAME>` with the event name discovered in Step 1):

```lua
--- KOReader broadcasts this when the user toggles colour rendering (or when
--- the colour-rendering mode otherwise changes). Flush the hex cache so the
--- next paint reconstructs Blitbuffer values in the new mode, then mark the
--- overlay dirty so it repaints.
function Bookends:on<ACTUAL_EVENT_NAME>()
    require("bookends_colour").flushCache()
    self:markDirty()
end
```

- [ ] **Step 4: Byte-compile**

```bash
luac -p main.lua bookends_colour.lua
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add main.lua bookends_colour.lua
git commit -m "feat(colour): flush hex cache on colour-rendering toggle"
```

---

## Task 7 — Port `bookends_colour_wheel.lua` (widget)

**Files:**
- Create: `bookends_colour_wheel.lua`

The widget is ported from [appearance.koplugin](https://github.com/Euphoriyy/appearance.koplugin) — an HSV colour-wheel with separate brightness nudge, proven on colour e-ink devices. The Bookends port preserves the upstream behaviour and license; plugin-specific adaptations go into the outer dialog shell, not the wheel widget itself.

- [ ] **Step 1: Pin upstream commit SHA**

```bash
git ls-remote https://github.com/Euphoriyy/appearance.koplugin HEAD | awk '{print $1}'
```

Record the SHA (e.g. `a1b2c3d…`) — it goes into the file-head comment in Step 3.

- [ ] **Step 2: Fetch the upstream source**

```bash
TMPDIR=$(mktemp -d)
git clone --depth 1 https://github.com/Euphoriyy/appearance.koplugin "$TMPDIR/appearance"
ls "$TMPDIR/appearance"
```

Expected: see the upstream widget file (likely `colorwheel.lua`, `color_picker.lua`, or similar — scan for it).

- [ ] **Step 3: Create `bookends_colour_wheel.lua` with the required file-head comment**

```lua
--[[
Bookends colour wheel — HSV wheel + brightness picker widget.

Ported from appearance.koplugin (Euphoriyy, GPL-3.0):
  https://github.com/Euphoriyy/appearance.koplugin
  Source commit: <SHA from Step 1>

Adaptations for Bookends:
- Cancel / Default / Apply button row (plugin-wide dialog convention).
- Writes {hex="#RRGGBB"} into settings via the on_apply callback.
- dismissable = false (plugin-wide dialog convention).
- Outer WidgetContainer shell owns the observer-facing dimen (halo-overlay
  suppression relies on this); inner CenterContainer keeps its own dimen
  untouched (see feedback_centercontainer_dimen.md — never reassign a
  CenterContainer's self.dimen post-paint).

Licence: GPL-3.0 (preserved from upstream). See LICENSE.
]]

local _ = require("bookends_i18n").gettext
-- … (body: paste upstream widget class, then adaptations below)
```

- [ ] **Step 4: Copy the upstream widget body verbatim**

Paste the upstream `ColorWheel:new{ … }` widget class (or equivalent — the widget that renders the HSV wheel + swatch + hex label + brightness nudge) into the file below the header comment. Adjust only:
- Local requires to KOReader's module paths (`ui/widget/…`, `ffi/blitbuffer`, `device`).
- Upstream's use of `require("gettext")` → `require("bookends_i18n").gettext`.
- Any `for _, x in ipairs(...) do` loops that live inside scopes referring to gettext-as-`_` → rename to `_idx` / `_i` (per `feedback_gettext_shadowing.md`). Audit every loop header in the ported file.

- [ ] **Step 5: Wrap the widget's `paintTo` in an outer `WidgetContainer` shell so external observers can read `self.dimen` safely**

The outer dialog shell for the picker (the ButtonDialog-like container — see Task 8) should layer as:

```
FocusManager / WidgetContainer   ← outer: owns observer-facing self.dimen
 └─ FrameContainer                 ← visual border + background
     └─ CenterContainer              ← centring math: self.dimen = Screen:getSize() UNCHANGED
         └─ VerticalGroup
             ├─ wheel widget + brightness nudge
             ├─ swatch + hex label row
             └─ button row (Cancel / Default / Apply)
```

The outer shell's `paintTo` assigns `self.dimen = inner_frame.dimen` — CenterContainer's own `self.dimen` is never reassigned. Verify with:

```bash
grep -n "self.dimen = " bookends_colour_wheel.lua
```

Expected: `self.dimen = ` only inside the outer `WidgetContainer` shell's paintTo — never inside a CenterContainer subclass.

- [ ] **Step 6: Add the `Bookends:showColourPicker` public entry point at the foot of the file**

The signature intentionally mirrors `showNudgeDialog`:

```lua
--- Show the HSV colour picker for a single field.
--- @param title string: dialog title
--- @param current_hex string|nil: "#RRGGBB" or nil (fall back to default)
--- @param default_hex string|nil: shown behind the "Default" button; when
---        nil, Default clears the field (on_default callback)
--- @param on_apply function(new_hex) — called on Apply
--- @param on_default function()|nil — called on Default (optional; when nil,
---        the picker seeds itself with default_hex but on_apply still fires)
--- @param touchmenu_instance any — forwarded to self:hideMenu() for touchmenu
---        restore on close (matches showNudgeDialog's contract)
function Bookends:showColourPicker(title, current_hex, default_hex, on_apply, on_default, touchmenu_instance)
    -- Body: instantiate ColorWheel widget, wire Apply / Default / Cancel
    -- buttons, call self:hideMenu(touchmenu_instance) for menu restore,
    -- UIManager:show(dialog).
    -- See showNudgeDialog (main.lua:1562) for the restoreMenu / dismissable /
    -- tap_close_callback pattern to copy.
end
```

- [ ] **Step 7: Attach to the `Bookends` class by adding a require + call in `main.lua`**

After `require("menu.token_picker")(Bookends)` at `main.lua:162`, add:

```lua
require("bookends_colour_wheel")  -- attaches Bookends:showColourPicker
```

(The widget file self-registers via `function Bookends:showColourPicker…` on the global `Bookends` class — the require is enough to run the attach code.)

- [ ] **Step 8: Byte-compile**

```bash
luac -p bookends_colour_wheel.lua main.lua
```

Expected: no output.

- [ ] **Step 9: Interactive smoke-test on KOReader desktop**

```bash
# Push to desktop KOReader's user plugins dir (or run from source if user
# runs KOReader from a git clone):
cd /home/andyhazz/projects/bookends.koplugin
# … (user verifies the plugin loads without errors; no UI surface yet
# exercises showColourPicker, so this is purely a load-time smoke test)
```

Confirm: KOReader starts, plugin loads, `:luacheck` / `luac -p` is clean. No functional verification yet — Task 8 wires the callers.

- [ ] **Step 10: Commit**

```bash
git add bookends_colour_wheel.lua main.lua
git commit -m "feat(colour): port HSV colour-wheel widget from appearance.koplugin"
```

---

## Task 8 — Menu branch: `colorNudge` → picker on colour devices

**Files:**
- Modify: `menu/colours_menu.lua:12-24`

- [ ] **Step 1: Add a `Screen:isColorEnabled()` branch to `colorNudge`**

Open `menu/colours_menu.lua`. At the top of the file, just below `local _ = require("bookends_i18n").gettext`, add:

```lua
local Device = require("device")
local Colour = require("bookends_colour")
```

Then, replace the existing `colorNudge` helper (lines 12-24, the inner function inside `Bookends:_buildColorItems`) with:

```lua
    local function colorNudge(title, field, default_pct, touchmenu_instance)
        if Device:screen():isColorEnabled() then
            -- Colour device: show HSV picker. Hex-shape takes priority; if
            -- the field still holds a legacy raw byte or {grey=N}, render
            -- the equivalent greyscale hex so the picker opens on the
            -- user's currently-stored value.
            local v = bc[field]
            local current_hex
            if type(v) == "table" and v.hex then
                current_hex = v.hex
            elseif type(v) == "table" and v.grey then
                local g = string.format("%02X", v.grey)
                current_hex = "#" .. g .. g .. g
            elseif type(v) == "number" then
                local g = string.format("%02X", v)
                current_hex = "#" .. g .. g .. g
            end
            local default_hex = Colour.defaultHexFor(field)
            self:showColourPicker(title, current_hex, default_hex,
                function(new_hex)
                    bc[field] = { hex = new_hex }
                    saveColors()
                end,
                function()
                    bc[field] = nil
                    saveColors()
                end,
                touchmenu_instance)
            return
        end
        -- Greyscale device: existing nudge path, unchanged.
        local v = bc[field]
        local byte
        if type(v) == "table" and v.grey then byte = v.grey
        elseif type(v) == "number" then byte = v
        end
        local current = byte and math.floor((0xFF - byte) * 100 / 0xFF + 0.5) or default_pct
        self:showNudgeDialog(title, current, 0, 100, default_pct, "%",
            function(val)
                bc[field] = { grey = 0xFF - math.floor(val * 0xFF / 100 + 0.5) }
                saveColors()
            end,
            nil, nil, nil, touchmenu_instance,
            function()
                bc[field] = nil; saveColors()
            end,
            _("Default") .. " (" .. _("per style") .. ")")
    end
```

Note the dual-shape accommodation: legacy `bc[field]` as raw byte is still read, but new writes use `{grey = N}`. This normalises the bar_colors storage shape going forward without migrating existing data.

- [ ] **Step 2: Update `pctLabel` (lines 26-33) to handle all three shapes**

Replace with:

```lua
    local function pctLabel(field)
        local v = bc[field]
        if not v then return _("default") end
        if type(v) == "table" and v.hex then return v.hex end
        local byte
        if type(v) == "table" and v.grey then byte = v.grey
        elseif type(v) == "number" then byte = v
        end
        if byte then
            local pct = math.floor((0xFF - byte) * 100 / 0xFF + 0.5)
            if pct == 0 then return _("transparent") end
            return pct .. "%"
        end
        return _("default")
    end
```

- [ ] **Step 3: Byte-compile**

```bash
luac -p menu/colours_menu.lua
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add menu/colours_menu.lua
git commit -m "feat(colour): branch colorNudge to colour picker on colour devices"
```

---

## Task 9 — Text/Symbol menu helper with shared branch

**Files:**
- Modify: `menu/colours_menu.lua:268-348` (`buildTextColourMenu`)

- [ ] **Step 1: Extract a shared `textColorPickerOrNudge(field, default_label_suffix)` helper**

At the top of `buildTextColourMenu` (after `local symbol_color = self.settings:readSetting("symbol_color")` on line 270), add:

```lua
    local function textColorPickerOrNudge(field, title, default_label_suffix, touchmenu_instance)
        local stored = self.settings:readSetting(field)
        if Device:screen():isColorEnabled() then
            local current_hex
            if stored and stored.hex then
                current_hex = stored.hex
            elseif stored and stored.grey then
                local g = string.format("%02X", stored.grey)
                current_hex = "#" .. g .. g .. g
            end
            self:showColourPicker(title, current_hex, Colour.defaultHexFor(field),
                function(new_hex)
                    self.settings:saveSetting(field, { hex = new_hex })
                    self:markDirty()
                end,
                function()
                    self.settings:delSetting(field)
                    self:markDirty()
                end,
                touchmenu_instance)
            return
        end
        -- Greyscale: existing nudge path.
        local byte = (stored and stored.grey) or nil
        local current = byte and math.floor((0xFF - byte) * 100 / 0xFF + 0.5) or 100
        self:showNudgeDialog(title, current, 0, 100, 100, "%",
            function(val)
                self.settings:saveSetting(field, { grey = 0xFF - math.floor(val * 0xFF / 100 + 0.5) })
                self:markDirty()
            end,
            nil, nil, nil, touchmenu_instance,
            function()
                self.settings:delSetting(field)
                self:markDirty()
            end,
            _("Default") .. " (" .. default_label_suffix .. ")")
    end
```

- [ ] **Step 2: Replace the inline `self:showNudgeDialog(_("Text color…"), …)` call (lines 296-311) with a call to the helper**

```lua
        {
            text_func = function()
                return _("Text color") .. ": " .. textPctLabel()
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                textColorPickerOrNudge("text_color", _("Text color"), _("book"), touchmenu_instance)
            end,
            hold_callback = function(touchmenu_instance)
                self.settings:delSetting("text_color")
                self:markDirty()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
```

Delete the now-unused `text_color = nil` local assignment reset inside the old closure — the closure references have been removed. Re-read `text_color` inside `textPctLabel()` or lift the read to `text_color = self.settings:readSetting("text_color")` at the top of each invocation. (Simpler: replace the module-level `local text_color = …` and `local symbol_color = …` with accessors inside `textPctLabel` / `symbolPctLabel` that re-read from settings, since the helper writes via `self.settings` now.)

- [ ] **Step 3: Repeat for `symbol_color`**

Mirror-image of Step 2, using `textColorPickerOrNudge("symbol_color", _("Symbol color"), _("text"), touchmenu_instance)`.

- [ ] **Step 4: Byte-compile**

```bash
luac -p menu/colours_menu.lua
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add menu/colours_menu.lua
git commit -m "feat(colour): route text/symbol menu items through shared picker helper"
```

---

## Task 10 — Push, restart, manually verify on KOReader desktop

This is the first integration checkpoint. All picker call-sites now exist; verify they actually work before moving on to preset-gallery work.

- [ ] **Step 1: Push plugin to KOReader desktop**

If the user keeps KOReader desktop's plugins dir at a known path, push there. Otherwise the user runs KOReader desktop from a git clone — symlink the plugin:

```bash
# User verifies the actual plugin path for their KOReader desktop install.
# Typical path on Linux: ~/.config/koreader/plugins/
ln -sfn /home/andyhazz/projects/bookends.koplugin ~/.config/koreader/plugins/bookends.koplugin
```

Or tar-pipe a fresh copy if the user prefers a cold install:

```bash
cd /home/andyhazz/projects/bookends.koplugin
tar --exclude='.git' --exclude='.claude' --exclude='docs' --exclude='screenshots' --exclude='tools' --exclude='*.swp' -cf - . \
    | tar -xf - -C ~/.config/koreader/plugins/bookends.koplugin/
```

- [ ] **Step 2: Launch KOReader desktop and open a book**

Confirm the plugin loads without errors. Scan the KOReader log (`~/.config/koreader/crash.log`) for any bookends-related complaints on startup.

- [ ] **Step 3: Picker smoke-test — bar fill colour**

Open Bookends menu → Colors → Progress bar colors and tick marks → Read color. The HSV colour-wheel picker dialog should open (not the `% black` nudge), because KOReader desktop reports `Screen:isColorEnabled() == true` by default.

Drag the wheel; confirm the swatch + hex label update live. Tap Apply. Confirm the menu item now shows the chosen hex (e.g. `#7F08FF`) in place of a percentage. Confirm the book page repaints with the new fill colour in the read portion of any visible bar.

- [ ] **Step 4: Greyscale fallback — toggle KOReader's "Colour rendering" off**

In KOReader's Screen menu, toggle "Colour rendering" off. The bar should immediately repaint with the Rec.601 luminance of the chosen hex (greyscale byte). Re-open the Bookends menu → Read color — now it should open the `% black` nudge (not the picker), because `Screen:isColorEnabled()` now returns false.

Important: this is also the event-subscription verification surface. If Task 6's event subscription worked, the paint should update immediately on toggle. If the fallback was taken, the next paint triggers the auto-flush.

- [ ] **Step 5: Text colour — same drill via Colors → Text color**

- [ ] **Step 6: Hold-to-reset — long-press a menu item set to a hex, confirm the field clears**

- [ ] **Step 7: Document findings**

Write a short note in commit message or working doc about any misbehaviour seen (e.g. picker dialog renders off-centre, Apply button doesn't fire, cache not flushing on colour-toggle). If event name from Task 6 was wrong, loop back to Task 6 Step 2's fallback path.

- [ ] **Step 8: No commit required unless bugs were found and fixed**

If the interactive smoke-test surfaces a bug: fix, re-test, commit with a `fix(colour): …` message. If everything works, move on.

---

## Task 11 — Preset-side 🎨 detection in `preset_manager.lua`

**Files:**
- Modify: `preset_manager.lua:133` (inside `PresetManager.attach`)

- [ ] **Step 1: Add a `hasColour(preset_data)` helper near the top of the file, after `serializeTable`**

```lua
--- Detect whether a preset payload uses any colour (hex) values.
--- Walks the table recursively; returns true on the first `hex` key hit.
local function hasColour(t)
    if type(t) ~= "table" then return false end
    if t.hex and type(t.hex) == "string" and t.hex:match("^#%x%x%x%x%x%x$") then
        return true
    end
    for _k, v in pairs(t) do
        if type(v) == "table" and hasColour(v) then return true end
    end
    return false
end
PresetManager.hasColour = hasColour
```

Note: using `_k` (not `_`) to avoid shadowing gettext in files that ever import `_` as gettext — this module doesn't today, but defensive per `feedback_gettext_shadowing.md`.

- [ ] **Step 2: Update `writePresetContents` (lines 122-131) to stamp `has_colour` into the written payload when applicable**

```lua
local function writePresetContents(path, name, preset_data)
    local fout = io.open(path, "w")
    if fout then
        preset_data.metadata = preset_data.metadata or {}
        if hasColour(preset_data) then
            preset_data.metadata.has_colour = true
        else
            preset_data.metadata.has_colour = nil
        end
        if next(preset_data.metadata) == nil then
            preset_data.metadata = nil
        end
        fout:write("-- Bookends preset: " .. name .. "\n")
        fout:write("return " .. serializeTable(preset_data) .. "\n")
        fout:close()
        return true
    end
    return false
end
```

- [ ] **Step 3: Accept `metadata` as a valid top-level field in `validatePreset` (line 82-93)**

Add to `EXPECTED_TYPES`:

```lua
        metadata = "table",
```

- [ ] **Step 4: Byte-compile**

```bash
luac -p preset_manager.lua
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add preset_manager.lua
git commit -m "feat(colour): stamp metadata.has_colour when presets use hex values"
```

---

## Task 12 — Preset-card 🎨 glyph in `_addRow`

**Files:**
- Modify: `menu/preset_manager_modal.lua:490-499`, `:1295-1302`, `:563-607` (`_addRow` body)

- [ ] **Step 1: Plumb `has_colour` through the local-preset render call (line 490)**

Replace lines 488-499 with:

```lua
    for i = start_idx, end_idx do
        local p = presets[i]
        local has_colour = p.preset.metadata and p.preset.metadata.has_colour or false
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
```

- [ ] **Step 2: Plumb through the gallery render call (line 1295)**

Around line 1295, where `display = entry.name,` begins, add:

```lua
            has_colour = entry.metadata and entry.metadata.has_colour or false,
```

(The server-side `entry.metadata` comes from the refreshed index.json — see Task 14 for the review-skill side that writes it.)

- [ ] **Step 3: Render the 🎨 glyph inside `_addRow`**

Inside `PresetManagerModal._addRow` (line 563), at the end of the `title_line` composition (line 607, right after the `if opts.author …` block), append:

```lua
    if opts.has_colour then
        table.insert(title_line, HorizontalSpan:new{ width = Screen:scaleBySize(6) })
        table.insert(title_line, TextWidget:new{
            -- Colour-palette emoji; some fonts will render monochrome, which
            -- is fine — the semantic (preset uses colour) is still conveyed.
            text = "🎨",
            face = Font:getFace("cfont", 14),
            forced_height = title_h,
            forced_baseline = title_bl,
            fgcolor = Blitbuffer.COLOR_BLACK,
        })
    end
```

- [ ] **Step 4: Byte-compile**

```bash
luac -p menu/preset_manager_modal.lua
```

Expected: no output.

- [ ] **Step 5: Interactive check on KOReader desktop**

- Author a preset on desktop with a hex colour (from Task 10's picker run).
- Save preset → exit Preset Manager → re-open. Confirm 🎨 glyph appears on that preset's card.
- Confirm a greyscale-only preset (no hex) does **not** show the glyph.

- [ ] **Step 6: Commit**

```bash
git add menu/preset_manager_modal.lua
git commit -m "feat(colour): show 🎨 glyph on preset cards that use colour"
```

---

## Task 13 — Gallery review tooling: stamp `metadata.has_colour` in the review skill

**Files:**
- Modify: `.claude/skills/review-preset-submission/SKILL.md`

The bookends-presets repo's review skill already catalogues incoming PRs; add a "Colour usage" section plus a note that the reviewer should ensure `metadata.has_colour = true` is stamped into the preset before merge if the preset uses hex. The plugin-side `hasColour` helper is the authoritative detector; the review skill can shell to it when installed locally.

- [ ] **Step 1: Add a new "Colour usage" section to the skill, between "Disabled regions" and "Margin and layout sanity" (around line 155)**

Insert (in the style of the existing sections):

```markdown
### Colour usage (soft check)

Scan for `hex = "#…"` entries in the preset file:

\`\`\`bash
grep -oE 'hex = "#[0-9A-Fa-f]{6}"' /tmp/<slug>.lua
\`\`\`

If any are found:
- Verify the preset's top-level table includes `metadata = { has_colour = true, … }` so the gallery can show the 🎨 glyph on the card. If missing, modify-and-merge by injecting the metadata block.
- Report which region / line / field the hex colour is used in — colour-only aesthetic choices are hard to spot from the bare .lua.

Format in the report:

> **Colour usage**: ⚠ preset uses 3 hex values (line N "fill", line M "text_color" in `tr[1]`, …). `metadata.has_colour = true` ✓ (or ❌ missing — inject during modify-and-merge).

If no hex values are present, `metadata.has_colour` should be absent or false — report ✓.
```

- [ ] **Step 2: Add the colour-usage check to the checklist summary in the "Catches reliably" section at line 175**

Append:

```markdown
- Colour-value usage (`hex = "#…"`) + verification that `metadata.has_colour` is stamped for the gallery glyph.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/review-preset-submission/SKILL.md
git commit -m "docs(review-skill): add colour-usage check and has_colour stamping"
```

---

## Task 14 — Attribution: README acknowledgements section

**Files:**
- Modify: `README.md` (insert new section before `## License` at line ~399)

- [ ] **Step 1: Insert "Acknowledgements" section**

In `README.md`, find the `## License` heading (around line 399). Immediately before it, insert:

```markdown
## Acknowledgements

The HSV colour-wheel picker used on colour e-ink devices is adapted from [appearance.koplugin](https://github.com/Euphoriyy/appearance.koplugin) by Euphoriyy (GPL-3.0). I don't have a colour e-ink device myself, so I've leaned heavily on their proven design — if the picker feels off on your Kindle Colorsoft / Kobo Libra Colour / Boox Go Color, please open an issue on the Bookends repo. I can fix the bug, but I can't reproduce hardware-specific visual quirks without your help.

A general preset-authoring tip for colour devices: pick colours whose luminances are distinct for fill / background / ticks, so greyscale readers of your preset still see sensible contrast.

```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: credit appearance.koplugin in README acknowledgements"
```

---

## Task 15 — Translation strings: new msgids + placeholder entries

**Files:**
- Modify: `locale/bookends.pot`, `locale/{bg_BG,de,en_GB,es,fr,it,pt_BR}.po`

New translatable strings introduced by this feature:

1. `"Choose colour"` — picker dialog title prefix (or a specific per-field title if the caller already wraps in `_(…)`).
2. `"Hex"` — hex input field label.
3. `"Brightness"` — brightness nudge label in the picker.
4. `"Enter hex colour"` — prompt text for the hex input.
5. `"Invalid hex"` — validation error on hex entry.
6. `"Preset uses colour"` — optional tap-to-expand hint for the 🎨 glyph.
7. `"Colour rendering is disabled"` — shown in picker when called on a device with Screen:isColorEnabled() = false (defensive fallback message; should rarely fire since the picker is gated).

- [ ] **Step 1: Add the 7 msgid blocks to `locale/bookends.pot`**

In alphabetical order within the existing msgid list, add:

```po
msgid "Brightness"
msgstr ""

msgid "Choose colour"
msgstr ""

msgid "Colour rendering is disabled"
msgstr ""

msgid "Enter hex colour"
msgstr ""

msgid "Hex"
msgstr ""

msgid "Invalid hex"
msgstr ""

msgid "Preset uses colour"
msgstr ""
```

Validate the pot with `msgfmt -c -o /dev/null locale/bookends.pot`.

- [ ] **Step 2: Mirror the msgid blocks into each locale file as placeholder `msgstr ""` entries**

For each of `bg_BG`, `de`, `en_GB`, `es`, `fr`, `it`, `pt_BR`: add the same 7 msgid blocks with empty msgstr. (Per `reference_translation.md`, the en_GB file typically only holds colour/centre differences — the 4.3 strings use "Colour" spelling already, so en_GB only needs msgstrs for the 3 strings where en_GB wants a different spelling from the American template, if any. Check each string: all 7 here use "colour" (UK) spelling in the msgid, so en_GB may not need overrides. Confirm by running `msgfmt -c` on each file.)

- [ ] **Step 3: Validate every .po file**

```bash
for f in locale/*.po; do
    echo "== $f =="
    msgfmt -c -o /dev/null "$f" || echo "  FAILED"
done
```

Expected: all files pass, no `FAILED` lines.

- [ ] **Step 4: Dispatch parallel translator agents (per `reference_translation.md`) — one per non-English locale**

In a single turn, launch 5-6 subagents in parallel (bg_BG is out because the Bulgarian translator handles their own PRs; also skip en_GB because its overrides are minimal — verify by hand if needed). Each agent's prompt: "Translate these 7 new msgids into `<language>` in `locale/<code>.po`. See reference_translation.md for convention. Each msgstr should match the plugin's existing tone in that locale."

- [ ] **Step 5: After each translator returns, re-run `msgfmt -c`**

```bash
for f in locale/*.po; do msgfmt -c -o /dev/null "$f"; done
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add locale/
git commit -m "i18n: add 7 colour-picker strings + translations for non-English locales"
```

---

## Task 16 — Release notes draft

**Files:**
- Create: `docs/release-notes-4.3.0.md`

- [ ] **Step 1: Write the release notes in the style of `docs/release-notes-4.2.0.md`**

```markdown
# Bookends 4.3.0 — release notes

## New: colour picker on colour e-ink devices

On Kindle Colorsoft, Kobo Libra Colour, Boox Go Color, and any other colour-capable e-ink device, every colour setting in Bookends (text, symbols, progress-bar fill / background / track / ticks / border / invert / metro read) now opens an HSV colour-wheel picker instead of the `% black` nudge. Pick any colour; the plugin stores it as a hex string and paints it directly through KOReader's 32-bit colour surface.

On greyscale devices, the picker is not shown — the existing `% black` nudge behaves exactly as before. Presets authored on colour devices still render on greyscale hardware via Rec.601 luminance conversion at paint time, so a preset shared on the gallery works everywhere.

**Preset Gallery**: presets that use colour are now flagged with a 🎨 glyph on their card, so you can see at a glance which gallery entries are designed for colour hardware.

## Attribution

The HSV colour-wheel widget is adapted from [appearance.koplugin](https://github.com/Euphoriyy/appearance.koplugin) by Euphoriyy, under GPL-3.0 — the same licence as Bookends. I don't own a colour e-ink device myself, so I've leaned heavily on their proven widget design. If the picker feels off on your Kaleido display, please open an issue; I can fix the bug, but I can't reproduce hardware-specific visual quirks without your help.

## Tester call

This release is tagged **v4.3.0-rc1** first — a pre-release for community testers on colour hardware. If you have a Colorsoft / Libra Colour / Go Color (or any Kaleido e-reader running KOReader), please try the rc1 build and report screenshots of the picker and any applied colours on-book to [GitHub Issues](https://github.com/AndyHazz/bookends.koplugin/issues). The final v4.3.0 tag lands once at least one tester confirms the widget works and colours render sensibly.

## No visual change for existing users

Existing presets don't use hex values — they continue to render pixel-identically.
```

- [ ] **Step 2: Commit**

```bash
git add docs/release-notes-4.3.0.md
git commit -m "docs: add 4.3.0 release notes with attribution and tester call"
```

---

## Task 17 — v4.3.0-rc1 pre-release

**Files:**
- Modify: `_meta.lua` (verify version is `4.3.0-rc1`)

- [ ] **Step 1: Verify working tree is clean and version is `4.3.0-rc1`**

```bash
git status
grep 'version = ' _meta.lua
```

Expected: `nothing to commit, working tree clean` and `version = "4.3.0-rc1"`.

- [ ] **Step 2: Push branch and open a PR for review**

```bash
git push -u origin feat/colour-picker
gh pr create --title "Colour picker for colour e-ink devices (v4.3.0)" --body "$(cat <<'EOF'
## Summary
- Adds HSV colour-wheel picker on colour-enabled screens (Kindle Colorsoft, Kobo Libra Colour, Boox Go Color).
- Hex values stored as `{hex="#RRGGBB"}`; backward-compatible with existing `{grey=N}` and raw-byte storage.
- Greyscale devices continue with the existing `% black` nudge — no behaviour change.
- Preset gallery flags colour-using presets with a 🎨 glyph.
- Ports the HSV wheel from [appearance.koplugin](https://github.com/Euphoriyy/appearance.koplugin) (GPL-3.0), with attribution in README, release notes, and file header.

## Test plan
- [ ] `lua _test_colour.lua` passes (16 assertions).
- [ ] `luac -p` clean on all modified files.
- [ ] On KOReader desktop (SDL2): picker opens on colour settings, Apply writes hex to settings, book repaints in colour.
- [ ] On KOReader desktop with "Colour rendering" disabled: picker does NOT open; existing `% black` nudge opens; bar repaints using Rec.601 luminance of the stored hex.
- [ ] On the Kindle (greyscale): all existing bars paint identically to 4.2.0. `% black` nudge behaves as before.
- [ ] Preset authored on desktop with hex values, scp'd to Kindle: renders as luminance. 🎨 glyph visible in Preset Manager.
- [ ] Pre-release rc1 → community Kaleido tester feedback → final v4.3.0 tag once confirmed.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: After PR review passes, tag and release rc1**

```bash
git checkout master
git merge --ff-only feat/colour-picker  # or merge via GitHub UI
git tag -a v4.3.0-rc1 -m "Bookends v4.3.0-rc1 — colour picker pre-release for Kaleido testers"
git push origin master --tags
```

- [ ] **Step 4: Build the rc1 zip and attach to the GitHub release**

(Per `project_releases.md` — the updates manager relies on the .zip asset being attached to the release.)

```bash
cd /home/andyhazz/projects
zip -r bookends.koplugin-4.3.0-rc1.zip bookends.koplugin \
    -x 'bookends.koplugin/.git/*' \
    -x 'bookends.koplugin/.claude/*' \
    -x 'bookends.koplugin/docs/*' \
    -x 'bookends.koplugin/screenshots/*' \
    -x 'bookends.koplugin/tools/*'
gh release create v4.3.0-rc1 bookends.koplugin-4.3.0-rc1.zip \
    --repo AndyHazz/bookends.koplugin \
    --prerelease \
    --title "Bookends v4.3.0-rc1 — colour-picker pre-release" \
    --notes-file bookends.koplugin/docs/release-notes-4.3.0.md
```

- [ ] **Step 5: Post tester call**

Open a GitHub discussion or issue on `AndyHazz/bookends.koplugin` titled "v4.3.0-rc1 colour-picker — testers wanted for Kaleido hardware" with the tester-call paragraph from the release notes and a link to the rc1 zip. Wait for at least one tester confirmation before proceeding to Task 18.

---

## Task 18 — Tester feedback incorporation + final v4.3.0

Conditional: only run after at least one Kaleido tester confirms the picker works and colours render sensibly.

- [ ] **Step 1: If the tester reports a visual bug, open a short fix branch off rc1 and iterate**

Each fix commit: `fix(colour): <what> — reported by @<tester>`.

- [ ] **Step 2: When tester confirms the next rc build is good, bump version to final**

In `_meta.lua`:

```lua
    version = "4.3.0",
```

Commit:

```bash
git add _meta.lua
git commit -m "chore: bump version to 4.3.0"
```

- [ ] **Step 3: Squash rc-iteration fix commits (if any) into a clean history**

Per `feedback_dev_workflow.md` — squash intermediate fixes before final release:

```bash
git log --oneline master..HEAD
# Identify the fix commits to squash, then:
git rebase -i master   # mark intermediate fixes as `fixup`
```

- [ ] **Step 4: Tag final release and attach zip**

```bash
git tag -a v4.3.0 -m "Bookends v4.3.0 — colour picker"
git push origin master --tags
cd /home/andyhazz/projects
zip -r bookends.koplugin-4.3.0.zip bookends.koplugin \
    -x 'bookends.koplugin/.git/*' \
    -x 'bookends.koplugin/.claude/*' \
    -x 'bookends.koplugin/docs/*' \
    -x 'bookends.koplugin/screenshots/*' \
    -x 'bookends.koplugin/tools/*'
gh release create v4.3.0 bookends.koplugin-4.3.0.zip \
    --repo AndyHazz/bookends.koplugin \
    --title "Bookends v4.3.0 — colour picker" \
    --notes-file bookends.koplugin/docs/release-notes-4.3.0.md
```

- [ ] **Step 5: Update release notes with tester credit line**

In `docs/release-notes-4.3.0.md`, append (at the bottom of the "Attribution" section):

```markdown
Tested on colour e-ink hardware by @<tester-handle> — thank you.
```

Commit:

```bash
git add docs/release-notes-4.3.0.md
git commit -m "docs: credit 4.3.0 colour-picker tester"
git push
gh release edit v4.3.0 --notes-file docs/release-notes-4.3.0.md
```

---

## Appendix A — Verification matrix

| Surface | What it verifies | Hardware needed |
|---|---|---|
| `lua _test_colour.lua` | parseColorValue hex / grey / raw-byte / luminance / cache | none (dev box) |
| `luac -p <file>` | syntax on every modified Lua file | none |
| KOReader desktop (colour on) | picker opens, apply writes hex, paint uses ColorRGB32 | none (laptop) |
| KOReader desktop (colour off) | picker gated out, greyscale paint uses Color8(luminance), cache flushes on toggle | none (laptop) |
| Kindle (greyscale) | pre-change regression: no visual change, nudge unchanged | Kindle |
| Kindle (preset import) | hex preset imported on greyscale renders as luminance | Kindle |
| Kaleido community tester | dithering quality, wheel touch latency, picker legibility | colour e-reader (tester's) |

## Appendix B — File touch summary

| File | Created / Modified | Role |
|---|---|---|
| `bookends_colour.lua` | Created | `parseColorValue`, hex cache, default hex map |
| `bookends_colour_wheel.lua` | Created | HSV wheel widget + `showColourPicker` entry |
| `_test_colour.lua` | Created | Unit tests for `parseColorValue` |
| `_meta.lua` | Modified | Version bump 4.2.0 → 4.3.0-rc1 → 4.3.0 |
| `main.lua` | Modified | `resolveBarColors` delegates to `parseColorValue`; colour-rendering event subscription; widget require |
| `bookends_overlay_widget.lua` | Modified | Text/symbol paint routes through `parseColorValue` |
| `menu/colours_menu.lua` | Modified | `colorNudge` + `textColorPickerOrNudge` branch on `Screen:isColorEnabled()` |
| `preset_manager.lua` | Modified | `hasColour` helper + `metadata.has_colour` stamping |
| `menu/preset_manager_modal.lua` | Modified | 🎨 glyph in preset card title line |
| `README.md` | Modified | Acknowledgements section |
| `docs/release-notes-4.3.0.md` | Created | Release notes + attribution + tester call |
| `locale/bookends.pot` | Modified | 7 new msgids |
| `locale/{bg_BG,de,en_GB,es,fr,it,pt_BR}.po` | Modified | Placeholder + translated msgstrs |
| `.claude/skills/review-preset-submission/SKILL.md` | Modified | Colour-usage check + has_colour stamping guidance |
