# Font-family Font Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add six font-family entries (UI font + five CSS generic families) to bookends' font picker. Selected families resolve at render time via KOReader's `cre_font_family_fonts` map, falling back to UI font when a slot is unmapped.

**Architecture:** Additive only. Two helper functions in `utils.lua` handle resolution and labelling. The picker gains a "Font-family fonts" section on page 1. The main menu's font-setting label uses the label helper for family values. No schema migration — families are stored in the existing `font_face` field as a sentinel string `@family:<key>`.

**Tech Stack:** Lua 5.1 (KOReader runtime). KOReader APIs: `G_reader_settings:readSetting("cre_font_family_fonts")` for the family map, `Font.fontmap.cfont` for the UI font. No test framework — validation via `luac -p` for syntax and manual SCP-to-Kindle for behaviour.

---

## File Structure

| File | Responsibility | Change |
|------|---------------|--------|
| `utils.lua` | Plugin-scoped helpers | Add `FONT_FAMILIES` constant, `FONT_FAMILY_ORDER` array, `resolveFontFace`, `getFontFamilyLabel` |
| `main.lua` | Render path + picker dialog | One line change in `resolveLineConfig`. Extend `showFontPicker` with a family section on page 1. Picker title row shows family label when current face is a family |
| `menu/main_menu.lua` | Default-font menu item | Use `utils.getFontFamilyLabel` for label when value is a family; fall through to existing FontChooser path otherwise |
| `README.md` | User docs | New collapsible subsection "Using KOReader's font families" inside the Settings area |

`line_editor.lua` is NOT modified — its per-line font button already just shows "Font ✓" vs "Font..." (no font name displayed), which works unchanged for family values. A future enhancement could display the family label, but that's out of scope.

---

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
git -C /home/andyhazz/projects/bookends.koplugin checkout -b feature/font-family-picker
```
Expected: `Switched to a new branch 'feature/font-family-picker'`.

---

## Task 2: Add family helpers to `utils.lua`

**Files:**
- Modify: `utils.lua` (currently 45 lines, one `Utils` table exported; returns `Utils`)

- [ ] **Step 1: Update file header and add i18n import**

Edit `utils.lua`. Replace the first two lines:

```lua
--- Pure utility helpers shared across the plugin. No KOReader or UI imports.
local Utils = {}
```

With:

```lua
--- Utility helpers shared across the plugin. KOReader modules loaded lazily where needed.
local _ = require("i18n").gettext
local Utils = {}
```

- [ ] **Step 2: Add constants**

Edit `utils.lua`. Immediately after `local Utils = {}`, insert:

```lua

--- Supported font-family keys with human-readable labels.
-- "ui" resolves to KOReader's UI font; others resolve via cre_font_family_fonts.
Utils.FONT_FAMILIES = {
    ui             = _("UI font"),
    serif          = _("Serif"),
    ["sans-serif"] = _("Sans-serif"),
    monospace      = _("Monospace"),
    cursive        = _("Cursive"),
    fantasy        = _("Fantasy"),
}
Utils.FONT_FAMILY_ORDER = { "ui", "serif", "sans-serif", "monospace", "cursive", "fantasy" }

```

- [ ] **Step 3: Add `resolveFontFace`**

Edit `utils.lua`. Immediately before the final `return Utils` line, insert:

```lua
--- Resolve a font-face string to a concrete file path.
-- Returns `face` unchanged if it isn't a family sentinel.
-- Family sentinels resolve via KOReader's font-family map; unmapped slots fall
-- back to the UI font (matching KOReader's own family fallback semantics).
-- @param face string: a TTF path, or "@family:<key>"
-- @param fallback any: returned only in pathological cases (no UI font registered)
function Utils.resolveFontFace(face, fallback)
    if type(face) ~= "string" then return fallback end
    local family = face:match("^@family:(.+)$")
    if not family then return face end
    local Font = require("ui/font")
    if family == "ui" then
        return (Font.fontmap and Font.fontmap.cfont) or fallback
    end
    local map = G_reader_settings:readSetting("cre_font_family_fonts") or {}
    local mapped = map[family]
    if mapped and mapped ~= "" then return mapped end
    -- Unmapped family → fall back to UI font
    return (Font.fontmap and Font.fontmap.cfont) or fallback
end
```

- [ ] **Step 4: Add `getFontFamilyLabel`**

Edit `utils.lua`. Immediately after `Utils.resolveFontFace` (before `return Utils`), insert:

```lua
--- Build a display label for a font-face value.
-- Returns nil for non-family faces (caller uses its existing display logic).
-- For family faces, returns a table with fields:
--   label       string  e.g. "Serif (EB Garamond)" or "Cursive (UI font)"
--   is_family   bool    always true
--   is_mapped   bool    false when the family has no mapping in KOReader
--   resolved    string  the resolved TTF path (may be UI font for unmapped)
function Utils.getFontFamilyLabel(face)
    if type(face) ~= "string" then return nil end
    local family = face:match("^@family:(.+)$")
    if not family then return nil end
    local human = Utils.FONT_FAMILIES[family] or family
    local resolved = Utils.resolveFontFace(face, nil)
    local FontList = require("fontlist")
    local display
    if resolved then
        display = FontList:getLocalizedFontName(resolved, 0)
               or resolved:match("([^/]+)%.[tT][tT][fF]$")
               or resolved
    end
    local is_mapped
    if family == "ui" then
        is_mapped = true
    else
        local map = G_reader_settings:readSetting("cre_font_family_fonts") or {}
        is_mapped = (map[family] ~= nil and map[family] ~= "")
    end
    local inner
    if is_mapped then
        inner = display or "?"
    else
        inner = _("UI font")
    end
    return {
        label     = human .. " (" .. inner .. ")",
        is_family = true,
        is_mapped = is_mapped,
        resolved  = resolved,
    }
end
```

- [ ] **Step 5: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/utils.lua
```
Expected: no output.

- [ ] **Step 6: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add utils.lua
git commit -m "$(cat <<'EOF'
feat(utils): add resolveFontFace and getFontFamilyLabel helpers

New sentinel format @family:<key> stores font-family selections in
the existing font_face field. resolveFontFace translates the
sentinel to a concrete TTF path via KOReader's cre_font_family_fonts
map or Font.fontmap.cfont for @family:ui. Unmapped slots fall back
to the UI font, matching KOReader's own family-fallback semantics.

getFontFamilyLabel builds a display string like "Serif (EB Garamond)"
or "Cursive (UI font)" for pickers and menu labels.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Resolve family sentinels at render time

**Files:**
- Modify: `main.lua:474-508` — `resolveLineConfig` function

- [ ] **Step 1: Import Utils if not already imported at top of file**

Check `main.lua` near the top (first 20 lines) for an existing `local Utils = require("utils")` line. If not present, add it near the other local requires (alphabetical order preferred). Run:

```bash
grep -n 'require("utils")' /home/andyhazz/projects/bookends.koplugin/main.lua | head -3
```

If already required, skip this step. If not, edit `main.lua` and add:

```lua
local Utils = require("utils")
```

…in the require-block near the top of the file.

- [ ] **Step 2: Wire `resolveFontFace` into `resolveLineConfig`**

Edit `main.lua`. Find the current function (starts at line 474):

```lua
function Bookends:resolveLineConfig(face_name, font_size, style)
    style = style or "regular"
    local resolved_face = face_name
    local synthetic_bold = false

    if style ~= "regular" then
        -- Try to find the exact real font file for this style
        local variant = OverlayWidget.findFontVariant(face_name, style)
```

Replace the first four lines of the function body with:

```lua
function Bookends:resolveLineConfig(face_name, font_size, style)
    style = style or "regular"
    -- Resolve @family:<key> sentinels before any variant lookup.
    face_name = Utils.resolveFontFace(face_name, self.defaults.font_face)
    local resolved_face = face_name
    local synthetic_bold = false

    if style ~= "regular" then
        -- Try to find the exact real font file for this style
        local variant = OverlayWidget.findFontVariant(face_name, style)
```

(The resolution happens before `findFontVariant` so italic/bold lookups use the real TTF path, not the sentinel.)

- [ ] **Step 3: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/main.lua
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add main.lua
git commit -m "$(cat <<'EOF'
feat(render): resolve font-family sentinels in resolveLineConfig

A face value of @family:<key> now gets translated to a real TTF path
before the existing findFontVariant logic runs. This keeps the variant
search working unchanged (serif + italic still finds EB Garamond Italic
via the resolved path).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add "Font-family fonts" section to the picker

**Files:**
- Modify: `main.lua` — function `Bookends:showFontPicker` (starts at line 1362)

- [ ] **Step 1: Locate the font-list-build loop**

Open `main.lua`. The font-list build loop runs roughly from line 1387 to 1418 and culminates in `table.sort(fonts, ...)`. The `fonts` array holds entries `{ file, name, display }`.

- [ ] **Step 2: Add family entries at the start of the font list**

Edit `main.lua`. Find this block (around line 1412-1418):

```lua
    for _, entry in pairs(families) do
        table.insert(fonts, { file = entry.file, name = entry.name, display = entry.name })
        font_display_names[entry.file] = entry.name
    end
    table.sort(fonts, function(a, b)
        return ffiUtil.strcoll(a.name, b.name)
    end)
```

Replace with:

```lua
    for _, entry in pairs(families) do
        table.insert(fonts, { file = entry.file, name = entry.name, display = entry.name })
        font_display_names[entry.file] = entry.name
    end
    table.sort(fonts, function(a, b)
        return ffiUtil.strcoll(a.name, b.name)
    end)

    -- Prepend family entries (page 1 only, before the specific-font list)
    local family_entries = {}
    for _, fkey in ipairs(Utils.FONT_FAMILY_ORDER) do
        local sentinel = "@family:" .. fkey
        local fam_label = Utils.getFontFamilyLabel(sentinel)
        if fam_label then
            -- .file holds the sentinel so selection round-trips through the existing logic.
            -- .display is the composed label ("Serif (EB Garamond)").
            -- .resolved_file is what we render the row text with.
            table.insert(family_entries, {
                file = sentinel,
                name = Utils.FONT_FAMILIES[fkey],
                display = fam_label.label,
                resolved_file = fam_label.resolved,
                is_family = true,
            })
            font_display_names[sentinel] = fam_label.label
        end
    end
```

- [ ] **Step 3: Update `resolveToVisible` to accept family sentinels**

Edit `main.lua`. Find (around line 1420-1431):

```lua
    -- If current/default face is a variant not in the list, resolve to the family representative
    local shown_files = {}
    for _, f in ipairs(fonts) do shown_files[f.file] = true end
    local function resolveToVisible(face)
        if not face or shown_files[face] then return face end
        local info = FontList.fontinfo[face]
        if info and info[1] then
            local name = FontList:getLocalizedFontName(face, 0) or info[1].name
            if families[name] then return families[name].file end
        end
        return face
    end
```

Replace with:

```lua
    -- If current/default face is a variant not in the list, resolve to the family representative
    local shown_files = {}
    for _, f in ipairs(fonts) do shown_files[f.file] = true end
    for _, f in ipairs(family_entries) do shown_files[f.file] = true end
    local function resolveToVisible(face)
        if not face or shown_files[face] then return face end
        -- Family sentinels pass through as themselves (they're always "visible" on page 1)
        if type(face) == "string" and face:match("^@family:") then return face end
        local info = FontList.fontinfo[face]
        if info and info[1] then
            local name = FontList:getLocalizedFontName(face, 0) or info[1].name
            if families[name] then return families[name].file end
        end
        return face
    end
```

- [ ] **Step 4: Prepend family header + rows on page 1**

Find the page-1 list builder inside `buildPage()`. Look for (around line 1497):

```lua
        local list_group = VerticalGroup:new{ align = "left" }
        local start_idx = (page - 1) * per_page + 1
        local end_idx = math.min(start_idx + per_page - 1, #fonts)

        for i = start_idx, end_idx do
            local f = fonts[i]
```

Replace with (adds family header + family rows + "Fonts" header, only on page 1):

```lua
        local list_group = VerticalGroup:new{ align = "left" }

        -- Page 1: prepend "Font-family fonts" header + family rows + "Fonts" header
        if page == 1 and #family_entries > 0 then
            local baseline = math.floor(row_height * 0.65)
            -- Family section header
            local family_header = TextWidget:new{
                text = "\xE2\x94\x80\xE2\x94\x80 " .. _("Font-family fonts") .. " \xE2\x94\x80\xE2\x94\x80",
                face = Font:getFace("cfont", font_size),
                forced_height = row_height,
                forced_baseline = baseline,
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
            table.insert(list_group, LeftContainer:new{
                dimen = Geom:new{ w = width, h = row_height },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = left_pad },
                    family_header,
                },
            })

            -- Family rows
            for _, f in ipairs(family_entries) do
                local is_selected = (f.file == selected)
                local row_face = f.resolved_file and Font:getFace(f.resolved_file, font_size)
                                 or Font:getFace("cfont", font_size)
                local check_w = TextWidget:new{
                    text = is_selected and "\xE2\x9C\x93 " or "",
                    face = Font:getFace("cfont", font_size),
                    forced_height = row_height,
                    forced_baseline = baseline,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    bold = true,
                }
                local check_width = Screen:scaleBySize(30)
                local text_w = TextWidget:new{
                    text = f.display,
                    face = row_face,
                    forced_height = row_height,
                    forced_baseline = baseline,
                    max_width = width - 2 * left_pad - check_width,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    bold = is_selected,
                }
                local row_group = HorizontalGroup:new{
                    HorizontalSpan:new{ width = left_pad },
                    CenterContainer:new{
                        dimen = Geom:new{ w = check_width, h = row_height },
                        check_w,
                    },
                    text_w,
                }
                local item_container = InputContainer:new{
                    dimen = Geom:new{ w = width, h = row_height },
                    row_group,
                }
                item_container.ges_events = {
                    TapSelect = { GestureRange:new{ ges = "tap", range = item_container.dimen } },
                }
                local sentinel = f.file
                item_container.onTapSelect = safe("fontPicker:selectFamily", function()
                    selected = sentinel
                    on_select(sentinel)
                    picker:rebuild()
                    return true
                end)
                table.insert(list_group, item_container)
            end

            -- "Fonts" section header (separates family block from specific fonts)
            local fonts_header = TextWidget:new{
                text = "\xE2\x94\x80\xE2\x94\x80 " .. _("Fonts") .. " \xE2\x94\x80\xE2\x94\x80",
                face = Font:getFace("cfont", font_size),
                forced_height = row_height,
                forced_baseline = baseline,
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
            table.insert(list_group, LeftContainer:new{
                dimen = Geom:new{ w = width, h = row_height },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = left_pad },
                    fonts_header,
                },
            })
        end

        local start_idx = (page - 1) * per_page + 1
        -- Page 1 gets fewer specific-font rows to make room for the family section
        local rows_on_page = per_page
        if page == 1 and #family_entries > 0 then
            -- 6 family rows + 2 section headers = 8 extra rows displaced
            rows_on_page = math.max(2, per_page - #family_entries - 2)
        end
        local end_idx = math.min(start_idx + rows_on_page - 1, #fonts)

        for i = start_idx, end_idx do
            local f = fonts[i]
```

- [ ] **Step 5: Update the title row to handle family sentinels**

Find the title row builder inside `buildPage()` (around line 1458-1465):

```lua
        -- Custom title row: "Select font — FontName" with font name in its typeface
        local selected_name = selected and font_display_names[selected] or _("Default")
        local selected_face = selected and Font:getFace(selected, title_font_size)
                              or Font:getFace("cfont", title_font_size)
```

Replace with:

```lua
        -- Custom title row: "Select font — FontName" with font name in its typeface
        local selected_name = selected and font_display_names[selected] or _("Default")
        local selected_face
        if selected then
            local sel_resolved = Utils.resolveFontFace(selected, nil)
            if sel_resolved then
                selected_face = Font:getFace(sel_resolved, title_font_size)
            else
                selected_face = Font:getFace("cfont", title_font_size)
            end
        else
            selected_face = Font:getFace("cfont", title_font_size)
        end
```

- [ ] **Step 6: Fix the total-pages calculation to account for fewer-rows-on-page-1**

Find (around line 1447):

```lua
    local total_pages = math.max(1, math.ceil(#fonts / per_page))
```

Replace with:

```lua
    -- Page 1 shows fewer specific fonts (family rows + headers take space)
    local page1_fonts = (#family_entries > 0) and math.max(2, per_page - #family_entries - 2) or per_page
    local remaining_fonts = math.max(0, #fonts - page1_fonts)
    local total_pages = 1 + math.ceil(remaining_fonts / per_page)
```

- [ ] **Step 7: Fix the page-for-current-selection lookup**

Find (around line 1440-1446):

```lua
    -- Find initial page for current font
    for i, f in ipairs(fonts) do
        if f.file == selected then
            page = math.ceil(i / per_page)
            break
        end
    end
```

Replace with:

```lua
    -- Find initial page for current font (family sentinels always live on page 1)
    if type(selected) == "string" and selected:match("^@family:") then
        page = 1
    else
        for i, f in ipairs(fonts) do
            if f.file == selected then
                -- page 1 holds page1_fonts; subsequent pages hold per_page each
                if i <= page1_fonts then
                    page = 1
                else
                    page = 1 + math.ceil((i - page1_fonts) / per_page)
                end
                break
            end
        end
    end
```

- [ ] **Step 8: Fix the start_idx calculation on pages 2+ to skip page1_fonts**

Find (inside `buildPage()` after the family-section code from Step 4):

```lua
        local start_idx = (page - 1) * per_page + 1
        -- Page 1 gets fewer specific-font rows to make room for the family section
        local rows_on_page = per_page
        if page == 1 and #family_entries > 0 then
            -- 6 family rows + 2 section headers = 8 extra rows displaced
            rows_on_page = math.max(2, per_page - #family_entries - 2)
        end
        local end_idx = math.min(start_idx + rows_on_page - 1, #fonts)
```

Replace with:

```lua
        local start_idx
        local rows_on_page = per_page
        if page == 1 then
            start_idx = 1
            if #family_entries > 0 then
                -- 6 family rows + 2 section headers = 8 extra rows displaced
                rows_on_page = math.max(2, per_page - #family_entries - 2)
            end
        else
            -- Page 1 held `page1_fonts` specific fonts; subsequent pages each hold per_page.
            local page1_fonts = (#family_entries > 0) and math.max(2, per_page - #family_entries - 2) or per_page
            start_idx = page1_fonts + (page - 2) * per_page + 1
        end
        local end_idx = math.min(start_idx + rows_on_page - 1, #fonts)
```

- [ ] **Step 9: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/main.lua
```
Expected: no output.

- [ ] **Step 10: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add main.lua
git commit -m "$(cat <<'EOF'
feat(picker): add Font-family fonts section to font picker

Page 1 now shows a "Font-family fonts" header followed by six rows
(UI font, Serif, Sans-serif, Monospace, Cursive, Fantasy) above the
existing "Fonts" list. Each row renders the family name in the font
it will actually resolve to, giving a live preview.

Selecting a family saves the @family:<key> sentinel through the
existing on_select callback, so per-line and global-default
callers need no changes.

Pagination accounts for page 1 displacing 6 family rows + 2 headers;
page 2+ continues the specific-font list from where page 1 left off.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Update default-font menu label

**Files:**
- Modify: `menu/main_menu.lua` — `text_func` inside the "Default font" menu item (around lines 98-107)

- [ ] **Step 1: Add Utils import if missing**

Check the top of `menu/main_menu.lua` for an existing `local Utils = require("utils")`. If absent, add it near the other requires.

Run to check:
```bash
grep -n 'require("utils")' /home/andyhazz/projects/bookends.koplugin/menu/main_menu.lua
```

If no match, add `local Utils = require("utils")` near the file's other local requires.

- [ ] **Step 2: Use the family label in the text_func**

Edit `menu/main_menu.lua`. Find (around lines 97-107):

```lua
                    text_func = function()
                        local ok, FontChooser = pcall(require, "ui/widget/fontchooser")
                        local name
                        if ok and FontChooser and FontChooser.getFontNameText then
                            name = FontChooser.getFontNameText(self.defaults.font_face)
                        end
                        if not name then
                            name = self.defaults.font_face:match("([^/]+)$"):gsub("%.%w+$", "")
                        end
                        return _("Default font") .. " (" .. name .. ")"
                    end,
```

Replace with:

```lua
                    text_func = function()
                        local fam = Utils.getFontFamilyLabel(self.defaults.font_face)
                        if fam then
                            return _("Default font") .. " (" .. fam.label .. ")"
                        end
                        local ok, FontChooser = pcall(require, "ui/widget/fontchooser")
                        local name
                        if ok and FontChooser and FontChooser.getFontNameText then
                            name = FontChooser.getFontNameText(self.defaults.font_face)
                        end
                        if not name then
                            name = self.defaults.font_face:match("([^/]+)$"):gsub("%.%w+$", "")
                        end
                        return _("Default font") .. " (" .. name .. ")"
                    end,
```

- [ ] **Step 3: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/menu/main_menu.lua
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add menu/main_menu.lua
git commit -m "$(cat <<'EOF'
feat(menu): show family label for Default font setting

When the default font is a family sentinel, the menu label now reads
"Default font (Serif (EB Garamond))" or "Default font (Cursive (UI font))"
so users see what will actually render. Falls through to the existing
FontChooser-based name lookup for specific fonts.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: README subsection

**Files:**
- Modify: `README.md` — insert new `<details>` block under the Settings area.

- [ ] **Step 1: Insert new subsection**

Edit `README.md`. Find the end of the Settings section (around line 320, the one ending with the gesture-support paragraph and closing `</details>`):

```markdown
Assign **Toggle bookends** to any gesture via **Settings > Gesture manager > Reader**. Quickly show/hide all overlays with a tap, swipe, or multi-finger gesture.

</details>

<details>
<summary><strong>Coverage of KOReader's stock status bar</strong>
```

Replace with:

```markdown
Assign **Toggle bookends** to any gesture via **Settings > Gesture manager > Reader**. Quickly show/hide all overlays with a tap, swipe, or multi-finger gesture.

</details>

<details>
<summary><strong>Using KOReader's font families</strong> — pick Serif, Sans-serif, etc. instead of specific fonts</summary>

Bookends' font picker includes KOReader's font-family slots: **UI font**, **Serif**, **Sans-serif**, **Monospace**, **Cursive**, and **Fantasy**. Pick a family instead of a specific font, and overlays will use whichever font you have mapped to that slot in **KOReader Settings › Font › Font-family fonts**. This keeps overlay appearance consistent with your document font and makes presets portable across devices — someone sharing a preset that picks "Serif" will have it rendered in *your* serif, not theirs.

If a family slot isn't mapped in KOReader, the overlay falls back to your KOReader UI font. That's the same behaviour KOReader itself uses. If you see overlay text rendering in the UI font when you expected something else, check your KOReader **Font-family fonts** menu and set a mapping for that family.

</details>

<details>
<summary><strong>Coverage of KOReader's stock status bar</strong>
```

- [ ] **Step 2: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add README.md
git commit -m "$(cat <<'EOF'
docs(readme): document font-family picker entries

New "Using KOReader's font families" section explains the six new
picker entries, the portability benefit for presets, and the UI-font
fallback for unmapped families.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Final verification

**Files:** None — read-only checks.

- [ ] **Step 1: Syntax-check all modified Lua files together**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
luac -p utils.lua main.lua menu/main_menu.lua
```
Expected: no output for any file.

- [ ] **Step 2: Review commit history**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin log --oneline master..feature/font-family-picker
```
Expected: five commits (tasks 2-6).

- [ ] **Step 3: Review the diff stat against master**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin diff master..feature/font-family-picker --stat
```
Expected: four files changed — `utils.lua`, `main.lua`, `menu/main_menu.lua`, `README.md`.

- [ ] **Step 4: Grep for residual references**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
grep -rn --include="*.lua" '@family:' .
```
Expected occurrences:
- `utils.lua` (pattern match + comment)
- `main.lua` (sentinel handling in picker + `resolveToVisible`)
- Nothing in `line_editor.lua`, `menu/main_menu.lua` (they rely on Utils, don't string-match directly)

- [ ] **Step 5: Push branch to Kindle and restart (manual)**

Developer pushes each modified file to the Kindle per the standard workflow (see `feedback_dev_workflow.md` / README), then restarts KOReader.

---

## Manual verification checklist (post-implementation, on-device)

This is the standard dev workflow — not part of the TDD-style task loop above. After the branch is pushed and KOReader restarted:

1. **Picker shows the family section.** Open **Bookends → Settings → Default font** → picker's page 1 should have a `── Font-family fonts ──` header, six rows (UI font, Serif, Sans-serif, Monospace, Cursive, Fantasy), then a `── Fonts ──` header and the usual list.
2. **Row preview uses the resolved font.** Each family row's name is rendered in the font it resolves to. Serif-mapped to EB Garamond? "Serif (EB Garamond)" renders in EB Garamond.
3. **UI font entry works.** Pick "UI font" → menu label becomes "Default font (UI font (FS Me))" if you have the FS Me patch, else the default "UI font (NotoSans-Regular)".
4. **Serif selection updates render.** Pick "Serif" → return to the reader → overlay renders in whatever you have mapped to Serif in KOReader.
5. **Unmapped family falls back to UI font.** Ensure Fantasy has no mapping in KOReader; pick "Fantasy"; overlay renders in UI font. Label in menu reads "Default font (Fantasy (UI font))".
6. **Changing KOReader mapping mid-session propagates.** With "Serif" selected in bookends, change KOReader's Serif mapping to a different font. Next page turn → overlay updates.
7. **Per-line family works.** Tap any line → Font... → pick "Cursive" → live preview updates. Menu shows a ✓ on the Font button (current behaviour unchanged).
8. **Specific-font selection still works.** Pick any specific TTF → behaves exactly as before; no regression.
9. **Pagination.** Scroll to page 2, 3 of the picker — specific-font list is correct and complete, no gaps or overlaps with page 1.
