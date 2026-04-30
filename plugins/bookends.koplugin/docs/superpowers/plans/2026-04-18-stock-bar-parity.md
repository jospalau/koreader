# Stock KOReader Status-Bar Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every meaningful gap between KOReader's stock status bar and the bookends plugin — add a page-turn direction indicator, total-annotations token, surface an already-implemented MiB memory token, add three missing glyphs to the icon picker, and document the full mapping in the README.

**Architecture:** Purely additive. Extend `tokens.lua`'s `state` and `replace` tables with new keys (`invert`, `%V`, `%X`) under existing `needs()` gating. Surface three new and one previously-hidden picker entries in `menu/token_picker.lua` and `icon_picker.lua`. Append a new collapsible "Coverage of KOReader's stock status bar" section to `README.md`.

**Tech Stack:** Lua 5.1 (KOReader runtime). No test framework — validation via `luac -p` for syntax and manual SCP-to-Kindle for behaviour. Standard KOReader APIs: `G_reader_settings:isTrue()`, `ui.view.inverse_reading_order`, `ui.annotation:getNumberOfAnnotations()`.

---

## File Structure

| File | Responsibility | Change |
|------|---------------|--------|
| `tokens.lua` | Token expansion and conditional state | Add `state.invert`, `%V`, `%X` |
| `menu/token_picker.lua` | Token catalog shown to user | Expose `%V`, `%X`, `%M`; add `invert` conditional example/reference |
| `icon_picker.lua` | Glyph catalog shown to user | Add `⥖`, `⤻`, `💡` |
| `README.md` | User docs | New stock-parity mapping section |

No other files touched.

---

## Task 1: Branch setup

**Files:** None (git state only).

- [ ] **Step 1: Verify clean tree on master**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin status --short --branch
```
Expected: `## master...origin/master` with only `.claude/` untracked. Fail otherwise (user may have uncommitted work).

- [ ] **Step 2: Create feature branch**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin checkout -b feature/stock-bar-parity
```
Expected: `Switched to a new branch 'feature/stock-bar-parity'`.

---

## Task 2: Add `invert` to condition state

**Files:**
- Modify: `tokens.lua:132-138` (the `-- Battery & charging` block inside `buildConditionState`)

- [ ] **Step 1: Extend `buildConditionState` with page-turn direction**

Edit `tokens.lua`. Find:

```lua
    -- Battery & charging
    local powerd = Device:getPowerDevice()
    if powerd then
        state.batt = powerd:getCapacity() or 0
        state.charging = (powerd:isCharging() or powerd:isCharged()) and "yes" or "no"
        state.light = powerd:frontlightIntensity() > 0 and "on" or "off"
    end
```

Immediately after that block, add:

```lua
    -- Page-turn direction (any of: global key inversion flags, per-book reading order)
    local G = G_reader_settings
    local page_turn_inverted =
           G:isTrue("input_invert_page_turn_keys")
        or G:isTrue("input_invert_left_page_turn_keys")
        or G:isTrue("input_invert_right_page_turn_keys")
        or (ui.view and ui.view.inverse_reading_order)
    state.invert = page_turn_inverted and "yes" or "no"
```

- [ ] **Step 2: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/tokens.lua
```
Expected: no output (success). Any error means fix the edit.

- [ ] **Step 3: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add tokens.lua
git commit -m "$(cat <<'EOF'
feat(tokens): add invert condition state for page-turn direction

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add `%V` token

**Files:**
- Modify: `tokens.lua` — the `replace` table (currently lines 742-787) and add a new computation block before the replace table.

- [ ] **Step 1: Add `%V` computation block**

Edit `tokens.lua`. Find the "Disk available" block (around line 723-734):

```lua
    -- Disk available
    local disk_avail = ""
    if needs("v") then
        local util = require("util")
        if util.diskUsage then
            local drive = Device.home_dir or "/"
            local ok, usage = pcall(util.diskUsage, drive)
            if ok and usage and type(usage.available) == "number" and usage.available > 0 then
                disk_avail = string.format("%.1fG", usage.available / 1024 / 1024 / 1024)
            end
        end
    end
```

Immediately after that block, add:

```lua
    -- Page-turn direction indicator
    -- Shows ⇄ when any page-turn direction is inverted; empty otherwise.
    -- Matches stock readerfooter page_turning_inverted logic (OR of four flags).
    local page_turn_symbol = ""
    if needs("V") then
        local G = G_reader_settings
        local inverted =
               G:isTrue("input_invert_page_turn_keys")
            or G:isTrue("input_invert_left_page_turn_keys")
            or G:isTrue("input_invert_right_page_turn_keys")
            or (ui.view and ui.view.inverse_reading_order)
        if inverted then
            page_turn_symbol = "\xE2\x87\x84" -- U+21C4
        end
    end
```

- [ ] **Step 2: Add `%V` to the replace table**

Edit `tokens.lua`. Find the device section of the replace table:

```lua
        -- Device
        ["%b"] = tostring(batt_lvl),
        ["%B"] = tostring(batt_symbol),
        ["%W"] = wifi_symbol,
        ["%f"] = fl_intensity,
        ["%F"] = fl_warmth,
        ["%m"] = tostring(mem_usage),
        ["%M"] = ram_mb,
        ["%v"] = disk_avail,
    }
```

Replace with:

```lua
        -- Device
        ["%b"] = tostring(batt_lvl),
        ["%B"] = tostring(batt_symbol),
        ["%W"] = wifi_symbol,
        ["%f"] = fl_intensity,
        ["%F"] = fl_warmth,
        ["%m"] = tostring(mem_usage),
        ["%M"] = ram_mb,
        ["%v"] = disk_avail,
        ["%V"] = page_turn_symbol,
    }
```

- [ ] **Step 3: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/tokens.lua
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add tokens.lua
git commit -m "$(cat <<'EOF'
feat(tokens): add %V page-turn direction token

Empty when direction is default, U+21C4 when any of the four
page-turn inversion flags is set. Matches the OR logic used by
stock readerfooter's page_turning_inverted generator.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add `%X` total-annotations token

**Files:**
- Modify: `tokens.lua` — add computation block and extend the replace table.

- [ ] **Step 1: Add `%X` computation block**

Edit `tokens.lua`. Find the page-turn symbol block added in Task 3:

```lua
    -- Page-turn direction indicator
    -- ...
    local page_turn_symbol = ""
    if needs("V") then
        -- ...
    end
```

Immediately after it, add:

```lua
    -- Total annotations (bookmarks + highlights + notes, matching stock bookmark_count)
    local total_annotations = ""
    if needs("X") then
        if ui.annotation and ui.annotation.getNumberOfAnnotations then
            total_annotations = tostring(ui.annotation:getNumberOfAnnotations() or 0)
        end
    end
```

- [ ] **Step 2: Add `%X` to the replace table**

Edit `tokens.lua`. Find the metadata section of the replace table:

```lua
        -- Metadata
        ["%T"] = tostring(title),
        ["%A"] = tostring(authors),
        ["%S"] = tostring(series),
        ["%C"] = tostring(chapter_title),
        ["%N"] = file_name,
        ["%i"] = book_language,
        ["%o"] = doc_format,
        ["%q"] = highlights_count,
        ["%Q"] = notes_count,
        ["%x"] = bookmarks_count,
```

Replace with:

```lua
        -- Metadata
        ["%T"] = tostring(title),
        ["%A"] = tostring(authors),
        ["%S"] = tostring(series),
        ["%C"] = tostring(chapter_title),
        ["%N"] = file_name,
        ["%i"] = book_language,
        ["%o"] = doc_format,
        ["%q"] = highlights_count,
        ["%Q"] = notes_count,
        ["%x"] = bookmarks_count,
        ["%X"] = total_annotations,
```

- [ ] **Step 3: Add `%X` to the always_content table**

Find (currently around lines 793-798):

```lua
    local always_content = {
        ["%c"] = true, ["%t"] = true, ["%p"] = true, ["%L"] = true,
        ["%P"] = true, ["%g"] = true, ["%G"] = true, ["%l"] = true,
        ["%h"] = true, ["%H"] = true, ["%k"] = true, ["%K"] = true,
        ["%R"] = true, ["%s"] = true, ["%r"] = true,
    }
```

Replace with:

```lua
    local always_content = {
        ["%c"] = true, ["%t"] = true, ["%p"] = true, ["%L"] = true,
        ["%P"] = true, ["%g"] = true, ["%G"] = true, ["%l"] = true,
        ["%h"] = true, ["%H"] = true, ["%k"] = true, ["%K"] = true,
        ["%R"] = true, ["%s"] = true, ["%r"] = true,
        ["%X"] = true, ["%x"] = true, ["%q"] = true, ["%Q"] = true,
    }
```

(Rationale: annotation counts are meaningful at zero — "%x Bookmarks" should render as "0 Bookmarks" when there are none, matching other numeric-state tokens. `%x`, `%q`, `%Q` are added here too for consistency; they were omitted previously but follow the same principle.)

- [ ] **Step 4: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/tokens.lua
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add tokens.lua
git commit -m "$(cat <<'EOF'
feat(tokens): add %X total-annotations token

Sum of bookmarks + highlights + notes, matching stock readerfooter's
bookmark_count generator. %x, %q, %Q retain their individual meanings.
Annotation tokens marked always_content so a zero count still renders.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Surface `%V`, `%X`, `%M` in the token picker

**Files:**
- Modify: `menu/token_picker.lua` — extend `TOKEN_CATALOG`.

- [ ] **Step 1: Add `%X` to the Metadata category**

Edit `menu/token_picker.lua`. Find:

```lua
    { _("Metadata"), {
        { "%T", _("Document title") },
        { "%A", _("Author(s)") },
        { "%S", _("Series with index") },
        { "%C", _("Chapter title (deepest)") },
        { "%C1", _("Chapter title at depth 1") },
        { "%C2", _("Chapter title at depth 2") },
        { "%C3", _("Chapter title at depth 3") },
        { "%N", _("File name") },
        { "%i", _("Book language") },
        { "%o", _("Document format (EPUB, PDF, etc.)") },
        { "%q", _("Number of highlights") },
        { "%Q", _("Number of notes") },
        { "%x", _("Number of bookmarks") },
    }},
```

Replace with:

```lua
    { _("Metadata"), {
        { "%T", _("Document title") },
        { "%A", _("Author(s)") },
        { "%S", _("Series with index") },
        { "%C", _("Chapter title (deepest)") },
        { "%C1", _("Chapter title at depth 1") },
        { "%C2", _("Chapter title at depth 2") },
        { "%C3", _("Chapter title at depth 3") },
        { "%N", _("File name") },
        { "%i", _("Book language") },
        { "%o", _("Document format (EPUB, PDF, etc.)") },
        { "%q", _("Number of highlights") },
        { "%Q", _("Number of notes") },
        { "%x", _("Number of bookmarks") },
        { "%X", _("Total annotations (bookmarks + highlights + notes)") },
    }},
```

- [ ] **Step 2: Add `%V` and `%M` to the Device category**

Find:

```lua
    { _("Device"), {
        { "%b", _("Battery level") },
        { "%B", _("Battery icon (dynamic)") },
        { "%W", _("Wi-Fi icon (dynamic)") },
        { "%f", _("Frontlight brightness") },
        { "%F", _("Frontlight warmth") },
        { "%m", _("RAM used %") },
    }},
```

Replace with:

```lua
    { _("Device"), {
        { "%b", _("Battery level") },
        { "%B", _("Battery icon (dynamic)") },
        { "%W", _("Wi-Fi icon (dynamic)") },
        { "%V", _("Page-turn direction (shows when inverted)") },
        { "%f", _("Frontlight brightness") },
        { "%F", _("Frontlight warmth") },
        { "%m", _("RAM used %") },
        { "%M", _("RAM used (MiB)") },
    }},
```

- [ ] **Step 3: Add invert example and reference to CONDITIONAL_CATALOG**

Find:

```lua
Bookends.CONDITIONAL_CATALOG = {
    { _("Examples"), {
        { "[if:wifi=on]%W[/if]", _("Show wifi icon when connected") },
        { "[if:batt<20]LOW %b[/if]", _("Warning when battery below 20%") },
        { "[if:charging=yes]\xE2\x9A\xA1[/if] %b", _("Bolt icon when charging") },
        { "[if:speed>0]%r pg/hr[/if]", _("Speed, hidden until calculated") },
        { "[if:session>0]%R[/if]", _("Session time, hidden at start") },
        { "[if:page=odd]%c[else]%c[/if]", _("Different content on odd/even pages") },
        { "[if:percent>90]Almost done![/if]", _("Message near end of book") },
        { "[if:light=off]Light off[else]Light on[/if]", _("Frontlight status") },
        { "[if:format=PDF]%c / %t[/if]", _("Only show for PDF documents") },
        { "[if:time>22:00]Late night reading![/if]", _("After 10pm") },
        { "[if:day=Sat]Weekend![else]%a[/if]", _("Different text on Saturdays") },
    }},
    { _("Reference"), {
        { "[if:wifi=on]...[/if]", _("wifi — on / off") },
        { "[if:connected=yes]...[/if]", _("connected — yes / no") },
        { "[if:batt<50]...[/if]", _("batt — 0 to 100") },
        { "[if:charging=yes]...[/if]", _("charging — yes / no") },
        { "[if:percent>50]...[/if]", _("percent — 0 to 100 (book)") },
        { "[if:chapter>50]...[/if]", _("chapter — 0 to 100 (chapter)") },
        { "[if:speed>0]...[/if]", _("speed — pages per hour") },
        { "[if:session>30]...[/if]", _("session — minutes reading") },
        { "[if:pages>0]...[/if]", _("pages — session pages read") },
        { "[if:page=odd]...[/if]", _("page — odd / even") },
        { "[if:light=on]...[/if]", _("light — on / off") },
        { "[if:format=EPUB]...[/if]", _("format — EPUB / PDF / CBZ etc.") },
        { "[if:time>18:00]...[/if]", _("time — use HH:MM (24h)") },
        { "[if:day=Mon]...[/if]", _("day — Mon Tue Wed Thu Fri Sat Sun") },
    }},
}
```

Replace with:

```lua
Bookends.CONDITIONAL_CATALOG = {
    { _("Examples"), {
        { "[if:wifi=on]%W[/if]", _("Show wifi icon when connected") },
        { "[if:batt<20]LOW %b[/if]", _("Warning when battery below 20%") },
        { "[if:charging=yes]\xE2\x9A\xA1[/if] %b", _("Bolt icon when charging") },
        { "[if:invert=yes]\xE2\x87\x84[/if]", _("Arrows when page-turn direction is flipped") },
        { "[if:speed>0]%r pg/hr[/if]", _("Speed, hidden until calculated") },
        { "[if:session>0]%R[/if]", _("Session time, hidden at start") },
        { "[if:page=odd]%c[else]%c[/if]", _("Different content on odd/even pages") },
        { "[if:percent>90]Almost done![/if]", _("Message near end of book") },
        { "[if:light=off]Light off[else]Light on[/if]", _("Frontlight status") },
        { "[if:format=PDF]%c / %t[/if]", _("Only show for PDF documents") },
        { "[if:time>22:00]Late night reading![/if]", _("After 10pm") },
        { "[if:day=Sat]Weekend![else]%a[/if]", _("Different text on Saturdays") },
    }},
    { _("Reference"), {
        { "[if:wifi=on]...[/if]", _("wifi — on / off") },
        { "[if:connected=yes]...[/if]", _("connected — yes / no") },
        { "[if:batt<50]...[/if]", _("batt — 0 to 100") },
        { "[if:charging=yes]...[/if]", _("charging — yes / no") },
        { "[if:invert=yes]...[/if]", _("invert — yes / no (page-turn direction)") },
        { "[if:percent>50]...[/if]", _("percent — 0 to 100 (book)") },
        { "[if:chapter>50]...[/if]", _("chapter — 0 to 100 (chapter)") },
        { "[if:speed>0]...[/if]", _("speed — pages per hour") },
        { "[if:session>30]...[/if]", _("session — minutes reading") },
        { "[if:pages>0]...[/if]", _("pages — session pages read") },
        { "[if:page=odd]...[/if]", _("page — odd / even") },
        { "[if:light=on]...[/if]", _("light — on / off") },
        { "[if:format=EPUB]...[/if]", _("format — EPUB / PDF / CBZ etc.") },
        { "[if:time>18:00]...[/if]", _("time — use HH:MM (24h)") },
        { "[if:day=Mon]...[/if]", _("day — Mon Tue Wed Thu Fri Sat Sun") },
    }},
}
```

- [ ] **Step 4: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/menu/token_picker.lua
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add menu/token_picker.lua
git commit -m "$(cat <<'EOF'
feat(picker): surface %V, %X, %M tokens and invert conditional

%M already existed in tokens.lua but wasn't in the picker catalog.
%V and %X are new. invert conditional key gets example + reference.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add missing glyphs to icon picker

**Files:**
- Modify: `icon_picker.lua` — extend the Arrows and Device categories.

- [ ] **Step 1: Add two glyphs to the Arrows category**

Edit `icon_picker.lua`. Find:

```lua
        { "\xE2\x87\x84", _("Arrows left-right") },     -- U+21C4
        { "\xE2\x87\x89", _("Double arrows right") },   -- U+21C9
```

Replace with:

```lua
        { "\xE2\x87\x84", _("Arrows left-right") },     -- U+21C4
        { "\xE2\x87\x89", _("Double arrows right") },   -- U+21C9
        { "\xE2\xA5\x96", _("Left harpoon with right arrow") }, -- U+2956
        { "\xE2\xA4\xBB", _("Curved back arrow") },     -- U+293B
```

- [ ] **Step 2: Add lightbulb emoji to the Device category**

Find:

```lua
    { _("Device"), {
        { "\xEF\x83\xAB", _("Lightbulb") },             -- U+F0EB fa-lightbulb-o
```

Replace with:

```lua
    { _("Device"), {
        { "\xEF\x83\xAB", _("Lightbulb") },             -- U+F0EB fa-lightbulb-o
        { "\xF0\x9F\x92\xA1", _("Lightbulb emoji") },   -- U+1F4A1
```

- [ ] **Step 3: Syntax check**

Run:
```bash
luac -p /home/andyhazz/projects/bookends.koplugin/icon_picker.lua
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add icon_picker.lua
git commit -m "$(cat <<'EOF'
feat(picker): add three glyphs used by stock status bar

U+2956 and U+293B are stock's chapter-time-to-read icons.
U+1F4A1 is stock's frontlight-warmth icon. Adding these gives
picker parity for any user recreating the stock bar layout.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: README parity section

**Files:**
- Modify: `README.md` — insert new `<details>` block after the Settings section (around line 320, before the `---` separator).

- [ ] **Step 1: Insert the new section**

Edit `README.md`. Find (around line 319-322):

```markdown
Assign **Toggle bookends** to any gesture via **Settings > Gesture manager > Reader**. Quickly show/hide all overlays with a tap, swipe, or multi-finger gesture.

</details>

---

## Installation
```

Replace with:

```markdown
Assign **Toggle bookends** to any gesture via **Settings > Gesture manager > Reader**. Quickly show/hide all overlays with a tap, swipe, or multi-finger gesture.

</details>

<details>
<summary><strong>Coverage of KOReader's stock status bar</strong> — every stock item mapped to a bookends token</summary>

Bookends covers the same information as KOReader's built-in status bar, often with finer granularity. This table maps each stock footer item to the bookends token(s) that produce the same information.

| Stock footer item | Bookends token(s) |
|-------------------|-------------------|
| Page number (current / total) | `%c` / `%t` |
| Pages left in book | `%L` |
| Pages left in chapter | `%l` |
| Chapter progress (page in chapter) | `%g` / `%G` |
| Book percentage | `%p` |
| Chapter percentage | `%P` |
| Time to finish book | `%H` |
| Time to finish chapter | `%h` |
| Clock (12h / 24h) | `%k` / `%K` |
| Battery level | `%b` (%) / `%B` (dynamic icon) |
| Charging indicator | `[if:charging=yes]⚡[/if]` |
| Wi-Fi status | `%W` (dynamic) |
| Frontlight brightness | `%f` |
| Frontlight warmth | `%F` |
| Memory usage | `%m` (%) / `%M` (MiB) |
| Book title / author | `%T` / `%A` |
| Current chapter title | `%C` (also `%C1`…`%C9` by depth) |
| Bookmark count | `%x` |
| Highlight count | `%q` |
| Note count | `%Q` |
| **Total annotations** | `%X` |
| **Page-turning inverted** | `%V` (also `[if:invert=yes]`) |

Bookends' six-zone positioning model replaces stock's `dynamic_filler` layout and `additional_content` plugin hook — those aren't separate tokens because the overlay itself fills that role.

</details>

---

## Installation
```

- [ ] **Step 2: Commit**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add README.md
git commit -m "$(cat <<'EOF'
docs(readme): add stock KOReader status bar coverage table

Maps every item in the stock footer to the bookends token that
produces equivalent information. Helps users migrating from the
built-in bar find the right replacement quickly.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Final verification

**Files:** None — read-only checks.

- [ ] **Step 1: Syntax-check all modified files together**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
luac -p tokens.lua menu/token_picker.lua icon_picker.lua
```
Expected: no output for any file.

- [ ] **Step 2: Review commit history**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin log --oneline master..feature/stock-bar-parity
```
Expected: six commits, one per code task (2–7). Task 1 created the branch; Task 8 does no commits.

- [ ] **Step 3: Review the diff against master**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin diff master..feature/stock-bar-parity --stat
```
Expected: roughly four files changed — `tokens.lua`, `menu/token_picker.lua`, `icon_picker.lua`, `README.md`.

- [ ] **Step 4: Grep for `%V` and `%X` references (sanity)**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
grep -rn --include="*.lua" '%V\|%X' .
```
Expected occurrences: `tokens.lua` (2 × `%V`: computation + replace-table key; 2 × `%X`: computation + replace-table key + always_content entry) and `menu/token_picker.lua` (1 × `%V` catalog row, 1 × `%X` catalog row). README matches happen via `grep --include="*.md"` separately — not needed here.

- [ ] **Step 5: Report**

Summarise:
- Branch: `feature/stock-bar-parity`
- Files changed: 4
- Commits: 6
- Pending manual verification: push to Kindle (outside scope of this plan — the SCP/luac workflow is owner-driven).

---

## Manual verification checklist (post-implementation, on-device)

This is the standard dev workflow — not part of the TDD-style task loop above. After the branch lands on `master` or the user is ready to test:

1. `scp` plugin directory to Kindle via the established `kindle` SSH alias.
2. Restart KOReader on device (or force reload plugin).
3. Create an overlay line with `%V` in it. Toggle **Settings > Taps & gestures > Invert page turn direction**. `⇄` should appear after the next page turn.
4. Add 2 bookmarks + 1 highlight; add `%X` to an overlay line. Value should read `3`.
5. Open the token picker: confirm `%V`, `%X`, `%M` visible in their categories.
6. Open the icon picker: confirm `⥖`, `⤻`, `💡` visible.
7. Open the README (rendered on GitHub or locally): confirm the new section renders correctly.
