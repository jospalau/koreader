# Metro fill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the metro progress bar style a configurable read-portion fill colour (`bar_colors.metro_fill`), distinct from both the generic `bar_colors.fill` (which applies to bordered/wavy/solid bars) and `bar_colors.track` (metro's trunk colour). When set, the read portion and the ticks already passed are painted in `metro_fill`; when unset, metro renders pixel-identically to today.

**Architecture:** Three localised changes: (1) unpack `colors.metro_fill` into a new local in `paintProgressBar`, (2) teach the metro render branch and its tick loop to use it, (3) add one menu item in the shared `_buildColorItems` helper so both the global and per-bar colour menus pick it up. No new files, no new widgets, no preset-schema change (the preset system serialises `bar_colors` as an opaque table).

**Tech Stack:** Lua, KOReader widget primitives, `gettext` via `bookends_i18n`, existing `Blitbuffer` primitives. No new dependencies.

---

## File Structure

Files touched in this plan:

- **Modify** `bookends_overlay_widget.lua` — unpack new field + rendering changes in `paintProgressBar`
- **Modify** `menu/colours_menu.lua` — one new menu item in `_buildColorItems`; update `saveColors()` empty-check
- **Modify** `locale/bookends.pot` — add msgid entries for two new strings
- **Modify** `locale/en_GB.po` — en_GB British-spelling translations
- **Modify** `locale/bg_BG.po`, `locale/de.po`, `locale/es.po`, `locale/fr.po`, `locale/it.po`, `locale/pt_BR.po` — empty msgstr placeholders for translators
- **Modify** `_meta.lua` — version bump `4.1.0` → `4.2.0` (final task)

No files created. No files deleted.

---

### Task 1: Unpack `colors.metro_fill` at the top of `paintProgressBar`

**Files:**
- Modify: `bookends_overlay_widget.lua:906-913`

- [ ] **Step 1: Read the existing unpack block**

```bash
sed -n '900,915p' bookends_overlay_widget.lua
```

Expected output shows the existing `custom_*` locals at lines 906–913.

- [ ] **Step 2: Add the `custom_metro_fill` local**

In `bookends_overlay_widget.lua`, find this block (around line 913):

```lua
    local custom_border = colors and colors.border
    local custom_invert = colors and colors.invert
```

Insert a new line immediately after `custom_invert`:

```lua
    local custom_border = colors and colors.border
    local custom_invert = colors and colors.invert
    local custom_metro_fill = colors and colors.metro_fill
```

- [ ] **Step 3: Syntax check**

```bash
luac -p bookends_overlay_widget.lua
```

Expected: no output (success).

- [ ] **Step 4: Commit**

```bash
git add bookends_overlay_widget.lua
git commit -m "feat(metro): unpack bar_colors.metro_fill in paintProgressBar"
```

---

### Task 2: Replace metro's rendering so the read portion paints in `metro_fill`

**Files:**
- Modify: `bookends_overlay_widget.lua:961-964` (and tick loop at lines 968–990)

The existing metro branch has a local `metro_fill` bound from `custom_fill` but never painted with it; the trunk is painted uniformly in `metro_track`. Replace that local and add a conditional overlay paint.

- [ ] **Step 1: Replace the metro_fill local + track paint**

In `bookends_overlay_widget.lua`, find this section (around line 961–964):

```lua
        local metro_track = resolveColor(custom_track, Blitbuffer.COLOR_DARK_GRAY)
        local metro_fill = resolveColor(custom_fill, Blitbuffer.COLOR_DARK_GRAY)
        -- Track line (uniform colour — progress shown by dot only)
        pr(line_ox, line_y, line_len, line_thick, metro_track)
```

Replace with:

```lua
        local metro_track = resolveColor(custom_track, Blitbuffer.COLOR_DARK_GRAY)
        -- metro_fill: nil when user has not set a distinct fill (or set it to false/transparent)
        local metro_fill = resolveColor(custom_metro_fill, nil)
        -- Track line full length
        pr(line_ox, line_y, line_len, line_thick, metro_track)
        -- Optional fill overlay on the read portion
        if metro_fill then
            pr(line_ox + line_fill_start, line_y, line_fill, line_thick, metro_fill)
        end
```

Notes for the implementer:
- `resolveColor(custom_metro_fill, nil)` returns `nil` both when the user hasn't set a fill (`custom_metro_fill == nil`) and when they've set it to transparent (`custom_metro_fill == false`). Both cases should skip the overlay paint — the existing `if metro_fill then` handles both uniformly.
- `line_fill_start` is already computed two lines earlier (around line 958–959) and correctly handles `reverse = true`.
- Do **not** reach for `metro_fill ~= metro_track` as a distinctness test — Blitbuffer colour types have `__eq` metamethods that make equality unreliable. Checking `custom_metro_fill` presence (as we do via `resolveColor(..., nil)`) avoids the metamethod entirely.

- [ ] **Step 2: Update the tick loop to recolour ticks behind progress**

In the same function, find the tick-painting loop (around lines 968–990):

```lua
        local metro_tick_h = math.max(1, math.floor(thickness * tick_height_pct / 100))
        for _, tick in ipairs(ticks or {}) do
            local tick_frac = type(tick) == "table" and tick[1] or tick
            local tick_w = type(tick) == "table" and tick[2] or 1
            local tick_depth = type(tick) == "table" and tick[3] or 1
            if reverse then tick_frac = 1 - tick_frac end
            local tick_pos = math.floor(line_len * tick_frac)
            if tick_pos > 0 and tick_pos < line_len then
                local tick_above
                if reverse then
                    tick_above = tick_depth > 1
                else
                    tick_above = tick_depth <= 1
                end
                -- Vertical (side-anchored) bars: flip tick sides
                if vertical then tick_above = not tick_above end
                if tick_above then
                    pr(line_ox + tick_pos, line_y - metro_tick_h, line_thick, metro_tick_h, metro_track)
                else
                    pr(line_ox + tick_pos, line_y + line_thick, line_thick, metro_tick_h, metro_track)
                end
            end
        end
```

Replace with:

```lua
        local metro_tick_h = math.max(1, math.floor(thickness * tick_height_pct / 100))
        for _i, tick in ipairs(ticks or {}) do
            local tick_frac = type(tick) == "table" and tick[1] or tick
            local tick_w = type(tick) == "table" and tick[2] or 1
            local tick_depth = type(tick) == "table" and tick[3] or 1
            if reverse then tick_frac = 1 - tick_frac end
            local tick_pos = math.floor(line_len * tick_frac)
            if tick_pos > 0 and tick_pos < line_len then
                local tick_above
                if reverse then
                    tick_above = tick_depth > 1
                else
                    tick_above = tick_depth <= 1
                end
                -- Vertical (side-anchored) bars: flip tick sides
                if vertical then tick_above = not tick_above end
                -- Tick recolouring: ticks within the read portion paint in metro_fill
                local is_read
                if reverse then
                    is_read = tick_pos >= line_len - line_fill
                else
                    is_read = tick_pos <= line_fill
                end
                local tick_color = (metro_fill and is_read) and metro_fill or metro_track
                if tick_above then
                    pr(line_ox + tick_pos, line_y - metro_tick_h, line_thick, metro_tick_h, tick_color)
                else
                    pr(line_ox + tick_pos, line_y + line_thick, line_thick, metro_tick_h, tick_color)
                end
            end
        end
```

Notes for the implementer:
- Loop variable renamed `_` → `_i` per the saved feedback about not shadowing `gettext`'s `_` alias (see the "Don't shadow gettext" memory).
- Ticks at exactly `tick_pos == line_fill` count as read (using `<=`). Documented choice; low stakes visually.
- Unused-local `tick_w` is preserved from the original — it's tracked for future per-tick width support; leaving it keeps the diff tight.

- [ ] **Step 3: Syntax check**

```bash
luac -p bookends_overlay_widget.lua
```

Expected: no output (success).

- [ ] **Step 4: Commit**

```bash
git add bookends_overlay_widget.lua
git commit -m "feat(metro): paint read portion + passed ticks in metro_fill when set"
```

---

### Task 3: Add the "Metro read color" menu item

**Files:**
- Modify: `menu/colours_menu.lua:63-74` (existing "Metro track color" item is the insertion anchor)

The item is added to the shared `_buildColorItems` helper so both the global bar-colours menu (`buildBarColorsMenu`) and the per-bar colours menu (called from `menu/progress_bar_menu.lua:268`) pick it up with a single edit.

- [ ] **Step 1: Insert the new menu item**

In `menu/colours_menu.lua`, find the existing "Metro track color" item (lines 62–74):

```lua
        {
            text_func = function()
                return _("Metro track color") .. ": " .. pctLabel("track")
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                colorNudge(_("Metro track color (% black)"), "track", 75, touchmenu_instance)
            end,
            hold_callback = function(touchmenu_instance)
                bc.track = nil; saveColors()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
```

Immediately after that closing `},`, insert the new item:

```lua
        {
            text_func = function()
                return _("Metro read color") .. ": " .. pctLabel("metro_fill")
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                colorNudge(_("Metro read color (% black)"), "metro_fill", 100, touchmenu_instance)
            end,
            hold_callback = function(touchmenu_instance)
                bc.metro_fill = nil; saveColors()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
```

Notes for the implementer:
- `pctLabel("metro_fill")` works without changes — it's a closure over `bc` and reads `bc.metro_fill` directly, falling back to `_("default")` when unset.
- `colorNudge` signature: `(title, field, default_pct, touchmenu_instance)`. Default of `100` (black) is chosen so that if a user invokes the nudge and taps Apply at the starting position, they see a visible progress fill.
- Hold-to-reset clears `bc.metro_fill` and calls `saveColors()` to persist.

- [ ] **Step 2: Syntax check**

```bash
luac -p menu/colours_menu.lua
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add menu/colours_menu.lua
git commit -m "feat(menu): add 'Metro read color' item alongside 'Metro track color'"
```

---

### Task 4: Extend the `saveColors()` empty-check

**Files:**
- Modify: `menu/colours_menu.lua:165-166` (the `if not bc.fill and not bc.bg and ...` condition in `buildBarColorsMenu`)

When every colour field is nil, `saveColors()` deletes the whole `bar_colors` setting rather than persisting an empty table. The new `metro_fill` field must be part of this check or a lone `metro_fill` clear won't drop the blob.

- [ ] **Step 1: Extend the empty-check**

In `menu/colours_menu.lua`, find (line 165):

```lua
        if not bc.fill and not bc.bg and not bc.track and not bc.tick and bc.invert_read_ticks == nil and not bc.tick_height_pct and not bc.border and not bc.invert and not bc.border_thickness then
```

Replace with:

```lua
        if not bc.fill and not bc.bg and not bc.track and not bc.tick and bc.invert_read_ticks == nil and not bc.tick_height_pct and not bc.border and not bc.invert and not bc.border_thickness and not bc.metro_fill then
```

- [ ] **Step 2: Syntax check**

```bash
luac -p menu/colours_menu.lua
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add menu/colours_menu.lua
git commit -m "fix(colours): include metro_fill in saveColors() empty-check"
```

---

### Task 5: Add translation strings

**Files:**
- Modify: `locale/bookends.pot` — two new msgid entries
- Modify: `locale/en_GB.po` — British-spelling translations
- Modify: `locale/bg_BG.po`, `locale/de.po`, `locale/es.po`, `locale/fr.po`, `locale/it.po`, `locale/pt_BR.po` — placeholder entries

Two new translatable strings are introduced by Task 3:
1. `"Metro read color"`
2. `"Metro read color (% black)"`

- [ ] **Step 1: Add entries to `locale/bookends.pot`**

Open `locale/bookends.pot` and locate the existing "Metro track color" entries (search for `msgid "Metro track color"`). Immediately after the existing two Metro-track blocks, append:

```
msgid "Metro read color"
msgstr ""

msgid "Metro read color (% black)"
msgstr ""
```

Keep the alphabetical / functional grouping if the .pot is organised that way — otherwise appending next to "Metro track color" is correct.

- [ ] **Step 2: Add British-English translations to `locale/en_GB.po`**

Locate the "Metro track color" entries in `locale/en_GB.po` and add immediately after:

```
msgid "Metro read color"
msgstr "Metro read colour"

msgid "Metro read color (% black)"
msgstr "Metro read colour (% black)"
```

- [ ] **Step 3: Add placeholder entries to each other locale**

For each of `locale/bg_BG.po`, `locale/de.po`, `locale/es.po`, `locale/fr.po`, `locale/it.po`, `locale/pt_BR.po`, locate the "Metro track color" entries and append:

```
msgid "Metro read color"
msgstr ""

msgid "Metro read color (% black)"
msgstr ""
```

An empty `msgstr` causes gettext to fall back to the English msgid at runtime, which is the intended behaviour until translators fill these in.

- [ ] **Step 4: Verify every `.po` has valid syntax**

```bash
for f in locale/*.po; do
    msgfmt --check --output-file=/dev/null "$f" && echo "OK: $f" || echo "FAIL: $f"
done
```

Expected: every file reports OK.

- [ ] **Step 5: Commit**

```bash
git add locale/bookends.pot locale/*.po
git commit -m "i18n: add 'Metro read color' strings to pot and all locales"
```

---

### Task 6: Bump version to 4.2.0

**Files:**
- Modify: `_meta.lua:6`

- [ ] **Step 1: Update version string**

In `_meta.lua`, replace:

```lua
    version = "4.1.0",
```

with:

```lua
    version = "4.2.0",
```

- [ ] **Step 2: Syntax check**

```bash
luac -p _meta.lua
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add _meta.lua
git commit -m "chore: bump version to 4.2.0"
```

---

### Task 7: On-device verification (greyscale regression)

Verify on the author's Kindle that (a) existing users see no visual change by default, (b) setting the new field produces the intended progress fill + tick recolouring, and (c) reverse-direction bars behave correctly.

Follow the saved "Dev workflow" memory for SCP push; alias `kindle` is already configured.

- [ ] **Step 1: Push the plugin to the Kindle**

```bash
scp -r ./bookends.koplugin kindle:/mnt/us/koreader/plugins/
```

(Adjust path if the saved "Kindle SSH access" reference memory has a different target.)

- [ ] **Step 2: Restart KOReader on the Kindle and open a book with chapter ticks**

Force a restart if changes don't appear (KOReader caches plugin state):

```bash
ssh kindle 'killall -HUP koreader 2>/dev/null; true'
```

- [ ] **Step 3: Regression check — no visible change before setting `metro_fill`**

In a book with at least one metro-style progress bar configured (and no `bar_colors.metro_fill` set), observe the bar. Expected: **pixel-identical** to pre-change — uniform trunk, position dot, chapter ticks all painted in the track colour.

If the bar looks different, the `if metro_fill then` guard from Task 2 is wrong or the resolver is returning a non-nil value for the unset case — debug before proceeding.

- [ ] **Step 4: Positive check — set a metro_fill and confirm paint**

In `Bookends → Settings → Colors → Progress bar colors and tick marks → Metro read color`, nudge to a low % black (e.g. 20% black = light grey) and apply. Reopen the book. Expected:
- Read portion of the metro trunk paints in that colour.
- Track portion (unread) remains in the original track colour.
- Chapter ticks behind the current position paint in the fill colour; ticks ahead paint in track colour.

- [ ] **Step 5: Reverse-direction check**

Configure a reverse-direction metro bar (Bar → direction: reverse) and repeat step 4. Expected: the read portion is on the right side, and ticks on the right of the position dot paint in fill colour; ticks on the left paint in track colour.

- [ ] **Step 6: Hold-to-reset check**

Long-press "Metro read color" in the menu. Expected: setting reverts to "default"; bar returns to uniform-trunk appearance.

- [ ] **Step 7: Full-reset check**

`Progress bar colors and tick marks → Reset all to defaults`. Expected: no `bar_colors` key in settings; metro bar uniform; no regressions elsewhere.

---

### Task 8: KOReader desktop verification (secondary surface)

Run the same checks on the laptop's KOReader desktop build. This is cheap and catches anything that depends on SDL2-vs-FBInk differences.

- [ ] **Step 1: Point KOReader desktop at the plugin**

If the desktop install has a custom plugin search path, copy the plugin there; otherwise symlink:

```bash
ln -sfn "$(pwd)" ~/.config/koreader/plugins/bookends.koplugin
```

(Exact path depends on the desktop install — the user knows their setup.)

- [ ] **Step 2: Repeat Task 7 steps 3–6 on the desktop build**

Same expectations.

- [ ] **Step 3: Sanity-check vertical / side-anchored bars**

Configure a left- or right-anchored metro bar. Expected: reads vertically, fill paint direction matches the progress direction, tick recolouring respects the vertical flip that already exists in the code (`if vertical then tick_above = not tick_above end`).

---

### Task 9: Write release notes and prepare release

**Files:**
- Create: `docs/release-notes-4.2.0.md`
- Modify: (none)

- [ ] **Step 1: Draft release notes**

Create `docs/release-notes-4.2.0.md` with:

```markdown
# Bookends v4.2.0

## New

- **Metro progress bar has a visible read portion.** A new "Metro read color" setting (under Colors → Progress bar colors and tick marks) paints the part of the metro trunk the reader has passed in a distinct colour, and recolours the chapter ticks already reached. Metro's track colour is preserved as before. When unset (default), metro renders identically to 4.1.0.

## Notes

- The new setting is also available per-bar: configure individual bars to use different metro read colours under Progress bars → Bar N → Colors → Metro read color.
- Existing presets continue to work unchanged; they simply lack the new field and fall back to the uniform-trunk rendering.
```

Match the tone of `docs/release-notes-4.1.0.md` (which should exist for reference). Per the saved "Release notes" feedback memory, list only net-new changes — not intermediate fixes that happened during implementation.

- [ ] **Step 2: Commit release notes**

```bash
git add docs/release-notes-4.2.0.md
git commit -m "docs: release notes for 4.2.0"
```

---

### Task 10: Squash feature branch and prepare for merge

Per the saved "Dev workflow" memory (iterative SCP push, luac check, squash before release).

- [ ] **Step 1: Confirm the feature branch commits**

```bash
git log master..HEAD --oneline
```

Expected: 6 commits — unpack, render, menu item, empty-check, i18n, version bump, release notes.

- [ ] **Step 2: Squash into a single commit**

If this plan ran on a dedicated feature branch (e.g. `feature/metro-fill`), interactive-rebase-squash into one commit. If running directly on master (not recommended), skip this step.

```bash
git rebase -i master
# Keep first commit as 'pick', change the rest to 's' (squash).
# Edit the combined message to something like:
#
#   feat(metro): configurable fill colour for read portion + passed ticks
#
#   Adds bar_colors.metro_fill. When set, the read portion of the metro
#   progress bar paints in this colour and chapter ticks behind the
#   current position recolour to match. Default (unset) preserves the
#   uniform-trunk appearance of 4.1.0 pixel-for-pixel.
#
#   New menu item: Colors → Progress bar colors and tick marks →
#   Metro read color (also available per-bar).
```

- [ ] **Step 3: Final luac pass across all touched files**

```bash
for f in bookends_overlay_widget.lua menu/colours_menu.lua _meta.lua; do
    luac -p "$f" && echo "OK: $f" || echo "FAIL: $f"
done
```

Expected: every file OK.

- [ ] **Step 4: Open PR (or merge to master, per your usual flow)**

If using PRs:

```bash
gh pr create --title "feat: metro progress bar read fill (v4.2.0)" --body "$(cat <<'EOF'
## Summary
- New `bar_colors.metro_fill` field with corresponding menu item under Colors → Progress bar colors and tick marks.
- Metro read portion and passed ticks paint in this colour when set; default renders identically to 4.1.0.
- Works per-bar via the existing per-bar colour menu (single `_buildColorItems` edit covers both entry points).

## Test plan
- [x] Regression: no visible change on greyscale Kindle with metro_fill unset
- [x] Positive: setting metro_fill shows fill + recoloured ticks
- [x] Reverse direction: fill and tick recolouring mirror correctly
- [x] Vertical (side-anchored): fill and tick sides handled by existing vertical flip
- [x] Hold-to-reset: clears setting, bar returns to uniform
- [x] Full reset: Reset all to defaults drops bar_colors entirely
- [x] KOReader desktop: same behaviour

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: After merge, tag and release**

Per the saved "Release process" memory: a `.zip` asset must be attached to the GitHub release for the updates manager to pick it up.

```bash
git checkout master && git pull
git tag v4.2.0
git push origin v4.2.0

# Build the plugin zip at the repo root (structure expected by KOReader)
zip -r bookends.koplugin-4.2.0.zip \
    bookends_*.lua main.lua _meta.lua \
    menu/ icons/ locale/ \
    README.md LICENSE OWNER \
    preset_gallery.lua preset_manager.lua \
    -x '.git/*' -x '.claude/*' -x 'docs/*' -x 'screenshots/*'

gh release create v4.2.0 \
    --title "v4.2.0" \
    --notes-file docs/release-notes-4.2.0.md \
    bookends.koplugin-4.2.0.zip
```

(Double-check the zip contents against a known-working release zip structure — the saved "Release process" memory is authoritative if this command differs from prior practice.)

---

## Self-review

**Spec coverage:** every in-scope item from section "Phase 1" of the spec maps to a task:
- ✅ New field `bar_colors.metro_fill` — Task 1 + Task 3
- ✅ Render change, read portion paint — Task 2
- ✅ Tick recolouring for passed ticks — Task 2
- ✅ New menu item — Task 3
- ✅ `saveColors()` empty-check — Task 4
- ✅ Preset serialisation unchanged (no task needed — opaque table handles the new key)
- ✅ One new translatable string — Task 5 (two strings: the menu-item label and the nudge-title variant)
- ✅ Pot regeneration + placeholders — Task 5

**Placeholder scan:** No "TBD", "TODO", "implement later", "add appropriate error handling", "similar to Task N", or reference-without-code patterns. The zip-build command in Task 10 defers to the user's saved release process as the authoritative pattern, which is honest rather than guessing.

**Type consistency:** `custom_metro_fill` in Task 1 matches Task 2's usage; `bc.metro_fill` / `"metro_fill"` consistent across Tasks 3 and 4; string keys `"Metro read color"` and `"Metro read color (% black)"` identical across Tasks 3 and 5.

**Ambiguity:** one explicit decision logged — ticks at exactly `tick_pos == line_fill` count as read (Task 2 notes). All other rendering decisions are concrete code.
