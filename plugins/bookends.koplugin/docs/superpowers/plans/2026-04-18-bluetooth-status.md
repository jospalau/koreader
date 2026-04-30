# Bluetooth Status Token Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `%X` token and a `bluetooth` condition that passthrough kobo.koplugin's `isBluetoothEnabled()` state, so Bookends overlays can show a Bluetooth indicator on Kobo devices running kobo.koplugin.

**Architecture:** Thin passthrough. When `ui.kobo_plugin.kobo_bluetooth` exists, read `isBluetoothEnabled()` and expose as `%X` (→ glyph U+F00AF when on, empty when off) and `state.bluetooth` (`"on"`/`"off"`, nil when plugin not loaded). Mirrors the existing `%W` / `state.wifi` pattern exactly.

**Tech Stack:** Lua 5.1, KOReader plugin framework. No new dependencies. No automated tests (project convention) — verification via `luac -p` syntax check, then manual test on device.

**Spec:** `docs/superpowers/specs/2026-04-18-bluetooth-status-design.md`

**File structure:**

- `tokens.lua` — token resolution and condition state (single file, both additions live here)
- `menu/token_picker.lua` — picker entries for `%X` and the `bluetooth` conditional
- `icon_picker.lua` — static BT glyphs (on/off) for use inside `[if:]` branches
- `README.md` — one row in Device tokens, one row in Conditional tokens, one requirements note
- `_meta.lua` — version bump for the prerelease

Testing for this feature cannot be verified locally (author has no Bluetooth-capable device). Final verification happens via prerelease + Reddit feedback loop per Task 5.

---

### Task 1: Add `%X` token and `bluetooth` condition to `tokens.lua`

**Files:**
- Modify: `tokens.lua:125-130` (add bluetooth to `buildConditionState`)
- Modify: `tokens.lua:298` (add preview mapping)
- Modify: `tokens.lua:670` (add `bt_symbol` block after `%W` block)
- Modify: `tokens.lua:781` (add `%X` to replace table)

All four edits are in a single file and together form one coherent addition. Commit as one unit.

- [ ] **Step 1: Add `state.bluetooth` to `buildConditionState`**

In `tokens.lua`, immediately after the Wi-Fi condition block (current lines 125-130), add a new block. The file currently reads:

```lua
    -- WiFi
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if ok and NetworkMgr then
        state.wifi = NetworkMgr:isWifiOn() and "on" or "off"
        state.connected = (NetworkMgr:isWifiOn() and NetworkMgr:isConnected()) and "yes" or "no"
    end

    -- Battery & charging
```

Insert between the two blocks, so it becomes:

```lua
    -- WiFi
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if ok and NetworkMgr then
        state.wifi = NetworkMgr:isWifiOn() and "on" or "off"
        state.connected = (NetworkMgr:isWifiOn() and NetworkMgr:isConnected()) and "yes" or "no"
    end

    -- Bluetooth (via kobo.koplugin if present; intentionally nil otherwise)
    local kp = ui.kobo_plugin
    if kp and kp.kobo_bluetooth then
        state.bluetooth = kp.kobo_bluetooth:isBluetoothEnabled() and "on" or "off"
    end

    -- Battery & charging
```

`state.bluetooth` is left nil (not set to `"off"`) when kobo.koplugin isn't loaded. This means `[if:bluetooth=off]` does not spuriously match on devices without the plugin — see spec rationale.

- [ ] **Step 2: Add preview mapping for `%X`**

In the preview table in `Tokens.expand`, current line 298 reads:

```lua
            ["%b"] = "[batt]", ["%B"] = "[batt]", ["%W"] = "[wifi]",
```

Change to:

```lua
            ["%b"] = "[batt]", ["%B"] = "[batt]", ["%W"] = "[wifi]", ["%X"] = "[bt]",
```

- [ ] **Step 3: Add `bt_symbol` resolution block after the Wi-Fi block**

Current lines 658-670 contain the Wi-Fi block:

```lua
    -- Wi-Fi
    local wifi_symbol = ""
    if needs("W") then
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr:isWifiOn() then
            if NetworkMgr:isConnected() then
                wifi_symbol = "\xEE\xB2\xA8" -- U+ECA8 wifi connected
            else
                wifi_symbol = "\xEE\xB2\xA9" -- U+ECA9 wifi enabled, not connected
            end
        -- else: wifi disabled, leave as "" (hidden)
        end
    end

    -- Frontlight
```

Insert a parallel block between Wi-Fi and Frontlight:

```lua
    -- Wi-Fi
    local wifi_symbol = ""
    if needs("W") then
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr:isWifiOn() then
            if NetworkMgr:isConnected() then
                wifi_symbol = "\xEE\xB2\xA8" -- U+ECA8 wifi connected
            else
                wifi_symbol = "\xEE\xB2\xA9" -- U+ECA9 wifi enabled, not connected
            end
        -- else: wifi disabled, leave as "" (hidden)
        end
    end

    -- Bluetooth (via kobo.koplugin passthrough — hidden if plugin not loaded)
    local bt_symbol = ""
    if needs("X") then
        local kp = ui.kobo_plugin
        if kp and kp.kobo_bluetooth and kp.kobo_bluetooth:isBluetoothEnabled() then
            bt_symbol = "\xF3\xB0\x82\xAF" -- U+F00AF mdi-bluetooth
        end
    end

    -- Frontlight
```

The byte sequence `\xF3\xB0\x82\xAF` is the UTF-8 encoding of codepoint U+F00AF (SPUA-A, 4 bytes). `needs("X")` is the existing helper at `tokens.lua:331-338` that checks whether the format string contains `%X`; it already works for arbitrary letters with no modification.

- [ ] **Step 4: Add `%X` to the `replace` table**

Current lines 778-786 contain the Device section of the `replace` table:

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

Change the `%W` line to include `%X` right after:

```lua
        -- Device
        ["%b"] = tostring(batt_lvl),
        ["%B"] = tostring(batt_symbol),
        ["%W"] = wifi_symbol,
        ["%X"] = bt_symbol,
        ["%f"] = fl_intensity,
        ["%F"] = fl_warmth,
        ["%m"] = tostring(mem_usage),
        ["%M"] = ram_mb,
        ["%v"] = disk_avail,
    }
```

Do **not** add `%X` to the `always_content` table at line 793 — an empty Bluetooth state should auto-hide a line just like `%W` does.

- [ ] **Step 5: Verify syntax with luac**

Run: `luac -p tokens.lua`
Expected: no output (clean parse). Any error means a typo — inspect the reported line before proceeding.

- [ ] **Step 6: Deploy to test device (if available)**

For local syntax-smoke on the author's Kindle (no BT, but will confirm no regressions to existing tokens):

```bash
scp tokens.lua kindle:/mnt/us/koreader/plugins/bookends.koplugin/
```

On device: restart KOReader, open a book with an existing Bookends overlay, confirm existing `%W` / `%b` / `%B` etc. still render. `%X` will render empty (no kobo.koplugin, no BT hardware). That is the expected local behaviour.

- [ ] **Step 7: Commit**

```bash
git add tokens.lua
git commit -m "feat: %X bluetooth token and bluetooth condition (kobo.koplugin passthrough)"
```

---

### Task 2: Add picker entries

**Files:**
- Modify: `menu/token_picker.lua:54-61` (Device section — add `%X`)
- Modify: `menu/token_picker.lua:73` (Examples — add a bluetooth example)
- Modify: `menu/token_picker.lua:86-100` (Reference — add bluetooth row)
- Modify: `icon_picker.lua:11-14` (Dynamic section — add BT icon; currently holds only battery + wifi)
- Modify: `icon_picker.lua:15-29` (Device section — add static BT-off glyph)

Two separate pickers are involved: the token picker (inserts `%X`) and the icon picker (inserts literal glyphs for use inside `[if:]` branches).

- [ ] **Step 1: Add `%X` to the Device section of the token picker**

In `menu/token_picker.lua`, the Device section currently reads (lines 54-61):

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

Change to:

```lua
    { _("Device"), {
        { "%b", _("Battery level") },
        { "%B", _("Battery icon (dynamic)") },
        { "%W", _("Wi-Fi icon (dynamic)") },
        { "%X", _("Bluetooth icon (needs kobo.koplugin)") },
        { "%f", _("Frontlight brightness") },
        { "%F", _("Frontlight warmth") },
        { "%m", _("RAM used %") },
    }},
```

- [ ] **Step 2: Add a bluetooth example to the conditional Examples block**

Same file, current lines 72-84 in `CONDITIONAL_CATALOG` Examples contain `[if:wifi=on]%W[/if]` at line 73. Add a bluetooth example right after:

```lua
    { _("Examples"), {
        { "[if:wifi=on]%W[/if]", _("Show wifi icon when connected") },
        { "[if:bluetooth=on]%X[/if]", _("Show bluetooth icon when adapter on") },
        { "[if:batt<20]LOW %b[/if]", _("Warning when battery below 20%") },
        ...
```

(Leave the rest of the Examples block unchanged.)

- [ ] **Step 3: Add a bluetooth row to the conditional Reference block**

Same file, current lines 86-100 contain the Reference block. Add a row after the `wifi` entry at line 86:

```lua
    { _("Reference"), {
        { "[if:wifi=on]...[/if]", _("wifi — on / off") },
        { "[if:bluetooth=on]...[/if]", _("bluetooth — on / off (needs kobo.koplugin)") },
        { "[if:connected=yes]...[/if]", _("connected — yes / no") },
        ...
```

(Leave the rest of the Reference block unchanged.)

- [ ] **Step 4: Add BT icon to the Dynamic section of the icon picker**

In `icon_picker.lua`, the Dynamic section currently reads (lines 11-14):

```lua
    { _("Dynamic"), {
        { "\xEE\x9E\x90", _("Battery (changes with level)"), "%B" },     -- U+E790
        { "\xEE\xB2\xA8", _("Wi-Fi (changes with status)"), "%W" },      -- U+ECA8
    }},
```

Change to:

```lua
    { _("Dynamic"), {
        { "\xEE\x9E\x90", _("Battery (changes with level)"), "%B" },     -- U+E790
        { "\xEE\xB2\xA8", _("Wi-Fi (changes with status)"), "%W" },      -- U+ECA8
        { "\xF3\xB0\x82\xAF", _("Bluetooth (needs kobo.koplugin)"), "%X" }, -- U+F00AF mdi-bluetooth
    }},
```

The third tuple element (`"%X"`) causes the picker to insert the dynamic token rather than the literal glyph — same pattern as Wi-Fi.

- [ ] **Step 5: Add static BT-off glyph to the Device section of the icon picker**

Same file, current line 25 is the static Wi-Fi glyph. Add a BT-off glyph right after (inserts the literal glyph, no `%X` passthrough — for use inside `[else]` branches):

```lua
        { "\xEF\x87\xAB", _("Wi-Fi") },                 -- U+F1EB fa-wifi
        { "\xF3\xB0\x82\xB2", _("Bluetooth (off/static)") },  -- U+F00B2 mdi-bluetooth-off
        { "\xEF\x83\x82", _("Cloud") },                 -- U+F0C2 fa-cloud
```

UTF-8 encoding of U+F00B2: same pattern as U+F00AF but last byte changes. Bytes: `F3 B0 82 B2`. (Codepoint differs by `0xB2 - 0xAF = 3` in the last 6 bits; `0xAF & 0x3F = 0x2F` → byte `0xAF`; `0xB2 & 0x3F = 0x32` → byte `0xB2`.)

- [ ] **Step 6: Verify syntax with luac**

Run both:
```bash
luac -p menu/token_picker.lua
luac -p icon_picker.lua
```
Expected: no output for both.

- [ ] **Step 7: Deploy to test device**

```bash
scp menu/token_picker.lua kindle:/mnt/us/koreader/plugins/bookends.koplugin/menu/
scp icon_picker.lua kindle:/mnt/us/koreader/plugins/bookends.koplugin/
```

On device: restart KOReader, open a Bookends line editor, tap **Tokens** — verify `%X` appears in the Device section. Tap **If/Else conditional tokens** → Examples — verify the `[if:bluetooth=on]%X[/if]` row renders. Tap **Icons** → Dynamic — verify the Bluetooth row appears.

Inserting `%X` into a line and saving should cause it to render as empty (no kobo.koplugin locally).

- [ ] **Step 8: Commit**

```bash
git add menu/token_picker.lua icon_picker.lua
git commit -m "feat: token and icon picker entries for bluetooth"
```

---

### Task 3: Update README

**Files:**
- Modify: `README.md` — Device tokens table (~line 133), Conditional tokens table (~line 175), plus one requirements note

- [ ] **Step 1: Add `%X` to the Device tokens table**

Current Device tokens table in `README.md` ends around line 140:

```markdown
| Token | Description | Example |
|-------|-------------|---------|
| `%b` | Battery level | *73%* |
| `%B` | Battery icon (dynamic) | Changes with charge level |
| `%W` | Wi-Fi icon (dynamic) | Hidden when off, changes when connected/disconnected |
| `%f` | Frontlight brightness | *18* or *OFF* |
| `%F` | Frontlight warmth | *12* |
| `%m` | RAM usage | *33%* |
```

Insert a `%X` row right after `%W`:

```markdown
| Token | Description | Example |
|-------|-------------|---------|
| `%b` | Battery level | *73%* |
| `%B` | Battery icon (dynamic) | Changes with charge level |
| `%W` | Wi-Fi icon (dynamic) | Hidden when off, changes when connected/disconnected |
| `%X` | Bluetooth icon (dynamic) | Hidden when off or kobo.koplugin not installed |
| `%f` | Frontlight brightness | *18* or *OFF* |
| `%F` | Frontlight warmth | *12* |
| `%m` | RAM usage | *33%* |
```

- [ ] **Step 2: Add a `bluetooth` row to the Conditional tokens table**

Current Conditional tokens table contains a wifi row around line 179:

```markdown
| Condition | Values | Description |
|-----------|--------|-------------|
| `wifi` | on / off | Wi-Fi radio state |
| `connected` | yes / no | Network connection state |
```

Insert a `bluetooth` row right after `wifi`:

```markdown
| Condition | Values | Description |
|-----------|--------|-------------|
| `wifi` | on / off | Wi-Fi radio state |
| `bluetooth` | on / off | Bluetooth adapter state (requires [kobo.koplugin](https://github.com/OGKevin/kobo.koplugin)) |
| `connected` | yes / no | Network connection state |
```

- [ ] **Step 3: Add a requirements note below the Device tokens table**

Below the Device tokens table (the existing paragraph reads "Page tokens respect **stable page numbers**..."), add a one-line note. The existing paragraph is at ~line 141:

```markdown
Page tokens respect **stable page numbers** and **hidden flows** (non-linear EPUB content). Time-left and reading speed tokens use the **statistics plugin**. Session timer and pages reset each time you wake the device.
```

Keep that paragraph unchanged. Add a new paragraph immediately after:

```markdown
`%X` and the `bluetooth` condition require [kobo.koplugin](https://github.com/OGKevin/kobo.koplugin) installed on a supported Kobo device. They render empty / never match otherwise.
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: bluetooth token and condition in README"
```

---

### Task 4: Bump version

**Files:**
- Modify: `_meta.lua`

- [ ] **Step 1: Read current version**

```bash
cat _meta.lua
```

Expected format (current version from git log is `3.5.0`):

```lua
return {
    name = "bookends",
    version = "3.5.0",
    ...
}
```

- [ ] **Step 2: Bump version to `3.5.1`**

Edit `_meta.lua`, change `version = "3.5.0"` to `version = "3.5.1"`. This is the version the prerelease will carry — if there are multiple rcs you don't need to bump it between rcs (prereleases use the git tag, not `_meta.lua`, as their identity on GitHub).

- [ ] **Step 3: Verify syntax with luac**

Run: `luac -p _meta.lua`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add _meta.lua
git commit -m "chore: bump version to 3.5.1"
```

---

### Task 5: Cut prerelease and reply on Reddit

This is a delivery task, not an implementation one — perform it once Tasks 1-4 are merged to master. No code changes here.

- [ ] **Step 1: Build the plugin zip**

The zip must contain a top-level folder `bookends.koplugin/` so users extract directly into their `plugins/` folder. From the project root:

```bash
# Stage a clean copy excluding dev-only files
rm -rf /tmp/bookends-release && mkdir -p /tmp/bookends-release/bookends.koplugin
rsync -a --exclude='.git' --exclude='.claude' --exclude='docs/superpowers' --exclude='screenshots' \
    ./ /tmp/bookends-release/bookends.koplugin/
cd /tmp/bookends-release && zip -r /tmp/bookends.koplugin.zip bookends.koplugin && cd -
```

Sanity check:
```bash
unzip -l /tmp/bookends.koplugin.zip | head -20
```
Expected: entries begin with `bookends.koplugin/`, include `main.lua`, `tokens.lua`, `_meta.lua`, `menu/`, etc. — and **exclude** `docs/superpowers/`.

- [ ] **Step 2: Open a GitHub issue tracking the feature**

```bash
gh issue create \
    --title "Bluetooth status indicator via kobo.koplugin passthrough" \
    --body "Reddit feature request. Adds \`%X\` token and \`bluetooth\` condition that passthrough \`ui.kobo_plugin.kobo_bluetooth:isBluetoothEnabled()\`. Requires kobo.koplugin on a Kobo device to be useful. Prerelease build attached to v3.5.1-rc1 release. Looking for confirmation that the icon reflects BT state correctly as users toggle it via kobo.koplugin."
```

Note the issue number returned; reference it in the release notes.

- [ ] **Step 3: Cut the prerelease**

```bash
gh release create v3.5.1-rc1 \
    --prerelease \
    --title "v3.5.1-rc1 — Bluetooth status preview" \
    --notes "Preview build adding \`%X\` Bluetooth token and \`bluetooth\` condition.

Requires [kobo.koplugin](https://github.com/OGKevin/kobo.koplugin) installed on a supported Kobo device — the token and condition are passthroughs of kobo.koplugin's Bluetooth state.

Tracking feedback in #<ISSUE_NUMBER>.

This is a prerelease — the in-app updater will not auto-notify existing users." \
    /tmp/bookends.koplugin.zip
```

Replace `<ISSUE_NUMBER>` with the number from Step 2.

Verify the updater correctly skips it: from any book, tap **Settings → Check for updates**. With `v3.5.1-rc1` being a prerelease and `v3.5.0` being the stable, the check should report "up to date" (see `updater.lua:138` — `release.draft or release.prerelease` is filtered).

- [ ] **Step 4: Reply on the Reddit thread**

Template (fill in URLs):

> Preview build is up at <release URL>. It requires kobo.koplugin installed on a Kobo device.
>
> To try it: download the `.zip` from that page, unzip into `/mnt/onboard/.adds/koreader/plugins/` (so you end up with `/mnt/onboard/.adds/koreader/plugins/bookends.koplugin/`), restart KOReader.
>
> Then in the line editor tap **Tokens → Device → Bluetooth icon** to insert `%X`, or write `[if:bluetooth=on]...[/if]` for a conditional branch. `%X` renders the `󰂯` glyph when the adapter is on, empty otherwise.
>
> Please let me know if the icon appears/disappears correctly when you toggle BT via kobo.koplugin — tracking feedback at <issue URL>. Screenshots of anything weird welcome.

- [ ] **Step 5: Await feedback; iterate as `-rc2` / `-rc3` if needed**

When you need to publish a fix:

1. Make the fix on a branch, merge.
2. Rebuild the zip (Step 1).
3. `gh release create v3.5.1-rc2 --prerelease ... /tmp/bookends.koplugin.zip`
4. Reply in the GitHub issue thread and the Reddit thread linking the new preview.

When the feature is validated:

1. Delete the rc releases (`gh release delete v3.5.1-rc1`, etc.).
2. Cut `v3.5.1` as a non-prerelease (without `--prerelease` flag) with the same zip.
3. Close the issue.
