# Branch Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user (and trusted testers) install a non-default GitHub branch via a "Settings → Advanced → Development branch" entry, with a one-tap "Reset to latest stable release" escape hatch and a status line showing what's installed.

**Architecture:** Three files touched. New helpers in `bookends_updater.lua` (URL composition, branch installer, latest-stable installer, plus an `on_success` callback parameter on the existing `install`). One-line dispatch in `Bookends:checkForUpdates`. New "Advanced" submenu appended to `buildBookendsSettingsMenu`'s returned table with three rows. Two new persisted settings: `dev_branch` (string, default `""`) and `last_install_source` (string, default `"release"`).

**Tech Stack:** Lua 5.1 (KOReader-bundled). LuaSocket + curl-fallback HTTP (existing). KOReader UI widgets: `InputDialog`, `ConfirmBox`. `Device:unpackArchive` for zip extraction. The plugin's existing `self.settings` handle for persistence. Spec at `docs/superpowers/specs/2026-04-25-branch-switcher-design.md`.

**Working branch:** `feature/branch-switcher` (already created off `master`).

---

### Task 1: Test scaffolding for `bookends_updater.lua`

The updater module currently has no test file. We're adding pure-function helpers (URL composition) that are easy to unit-test once the module loads under pure Lua. This task only sets up the harness.

**Files:**
- Create: `_test_updater.lua`

- [ ] **Step 1: Create the test file with KOReader stubs**

Create `/home/andyhazz/projects/bookends.koplugin/_test_updater.lua`:

```lua
-- Dev-box test runner for bookends_updater.lua.
-- Runs pure-Lua (no KOReader) by stubbing every module the updater requires.
-- Usage: cd into the plugin dir, then `lua _test_updater.lua`.

package.loaded["ui/widget/confirmbox"] = setmetatable({}, { __index = function() return function() end end })
package.loaded["device"] = {
    canOpenLink = function() return false end,
    openLink = function() end,
    unpackArchive = function() return true end,
}
package.loaded["ui/widget/infomessage"] = setmetatable({}, { __index = function() return function() end end })
package.loaded["ui/uimanager"] = {
    show = function() end,
    close = function() end,
    scheduleIn = function() end,
    restartKOReader = function() end,
}
package.loaded["bookends_i18n"] = { gettext = function(s) return s end }

local Updater = dofile("bookends_updater.lua")

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end

local function eq(actual, expected)
    if actual ~= expected then
        error(("expected=%q got=%q"):format(tostring(expected), tostring(actual)), 2)
    end
end

-- Smoke: module loads
test("module loads", function()
    assert(Updater, "Updater module did not load")
    assert(type(Updater.getInstalledVersion) == "function")
end)

print(pass .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
```

- [ ] **Step 2: Run the harness, confirm it loads**

Run: `cd /home/andyhazz/projects/bookends.koplugin && lua _test_updater.lua`
Expected: `1 passed, 0 failed`

- [ ] **Step 3: Commit**

```bash
git add _test_updater.lua
git commit -m "test(updater): add pure-Lua test harness for bookends_updater"
```

---

### Task 2: `composeBranchUrl` helper + tests (TDD)

URL composition is the only pure function in the new code. Write tests first, then the helper.

**Files:**
- Modify: `_test_updater.lua` (add tests)
- Modify: `bookends_updater.lua` (add `Updater.composeBranchUrl`)

- [ ] **Step 1: Add failing tests**

Insert these tests after the `module loads` test in `_test_updater.lua` (before the `print(pass ...)` line):

```lua
test("composeBranchUrl: simple branch", function()
    eq(Updater.composeBranchUrl("master"),
       "https://github.com/AndyHazz/bookends.koplugin/archive/refs/heads/master.zip")
end)

test("composeBranchUrl: branch with slash kept literal", function()
    eq(Updater.composeBranchUrl("feature/v5.2-test"),
       "https://github.com/AndyHazz/bookends.koplugin/archive/refs/heads/feature/v5.2-test.zip")
end)

test("composeBranchUrl: special chars are URL-encoded", function()
    -- Spaces, semicolons, etc. encoded; alnum/-/_/./~// preserved
    eq(Updater.composeBranchUrl("a b;c"),
       "https://github.com/AndyHazz/bookends.koplugin/archive/refs/heads/a%20b%3Bc.zip")
end)
```

- [ ] **Step 2: Run, confirm fails**

Run: `lua _test_updater.lua`
Expected: 3 FAILs (`attempt to call a nil value (field 'composeBranchUrl')`)

- [ ] **Step 3: Add the helper to `bookends_updater.lua`**

Open `/home/andyhazz/projects/bookends.koplugin/bookends_updater.lua` and insert the helper just after `local function isNewer(...)` ends (around line 39, before `--- Try LuaSocket first...`):

```lua
--- Compose the GitHub branch-archive URL for a given branch name.
-- Branch path is URL-encoded except for alnum, dash, underscore, dot, tilde
-- and forward slash (so feature/foo keeps its slash).
function Updater.composeBranchUrl(branch)
    local encoded = branch:gsub("[^%w%-_/.~]", function(c)
        return string.format("%%%02X", c:byte())
    end)
    return string.format(
        "https://github.com/AndyHazz/bookends.koplugin/archive/refs/heads/%s.zip",
        encoded)
end
```

- [ ] **Step 4: Run tests, confirm pass**

Run: `lua _test_updater.lua`
Expected: `4 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add bookends_updater.lua _test_updater.lua
git commit -m "feat(updater): add composeBranchUrl helper"
```

---

### Task 3: Add `on_success` callback parameter to `Updater.install`

Backwards-compatible signature extension. The callback fires after `Device:unpackArchive` returns true but before the restart `ConfirmBox` is shown — so the caller can stamp `last_install_source` while the new code is on disk but the running session is still using the old code.

**Files:**
- Modify: `bookends_updater.lua:287` (function `Updater.install`)

- [ ] **Step 1: Edit `Updater.install` signature and body**

Change the function signature and add the callback hook just before the restart `ConfirmBox`. In `bookends_updater.lua`:

Replace:
```lua
function Updater.install(zip_url, old_version, new_version)
```
with:
```lua
function Updater.install(zip_url, old_version, new_version, on_success)
```

Then find the block right after `pcall(os.remove, zip_path)` that says `if not ok then ... return end`. Just *after* that error-return block, and *before* `UIManager:show(ConfirmBox:new{` for the restart prompt, insert:

```lua
        -- Stamp install context (e.g. last_install_source) before the restart
        -- prompt fires; runs only when unpack succeeded.
        if on_success then
            local ok_cb = pcall(on_success)
            if not ok_cb then
                -- Don't let a misbehaving callback abort the restart prompt.
            end
        end
```

The `pcall` guard is defensive: a buggy callback shouldn't stop the user from being offered the restart prompt.

- [ ] **Step 2: Syntax check**

Run: `luac -p bookends_updater.lua && echo ok`
Expected: `ok`

- [ ] **Step 3: Verify existing test harness still loads the module**

Run: `lua _test_updater.lua`
Expected: `4 passed, 0 failed`

- [ ] **Step 4: Commit**

```bash
git add bookends_updater.lua
git commit -m "feat(updater): add optional on_success callback to install()"
```

---

### Task 4: `Updater.installBranch` wrapper

Composes the branch URL and hands off to `Updater.install`. Includes the same Wi-Fi guard as `Updater.check`.

**Files:**
- Modify: `bookends_updater.lua` (append after `Updater.install` function ends, around line 374)

- [ ] **Step 1: Add the function**

Insert into `bookends_updater.lua` immediately after the closing `end` of `Updater.install`:

```lua
--- Install from a GitHub branch's archive zip.
-- Same install pipeline as the release path; just composes a different URL.
-- @param branch string: branch name (e.g. "feature/v5.2-test")
-- @param on_success function or nil: fired after successful unpack
function Updater.installBranch(branch, on_success)
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isWifiOn() then
        UIManager:show(InfoMessage:new{
            text = _("Wi-Fi is not enabled."),
            timeout = 3,
        })
        return
    end

    local installed_version = Updater.getInstalledVersion()
    local zip_url = Updater.composeBranchUrl(branch)
    Updater.install(zip_url, installed_version, "branch:" .. branch, on_success)
end
```

- [ ] **Step 2: Syntax check**

Run: `luac -p bookends_updater.lua && lua _test_updater.lua`
Expected: `ok` then `4 passed, 0 failed`

- [ ] **Step 3: Commit**

```bash
git add bookends_updater.lua
git commit -m "feat(updater): add installBranch wrapper"
```

---

### Task 5: `Updater.installLatestStable` wrapper

Fetches `/releases/latest` and installs unconditionally — no version-comparison guard, so it works correctly even when a branch's `_meta.lua` reports a higher version than the current release.

**Files:**
- Modify: `bookends_updater.lua` (append after `Updater.installBranch`)

- [ ] **Step 1: Add the function**

Insert into `bookends_updater.lua` immediately after `Updater.installBranch`:

```lua
--- Install the latest stable (non-prerelease) release, regardless of installed version.
-- Used by the "Reset to latest stable release" entry: even when on a branch whose
-- _meta.lua reports a higher version than the current release, we still want to
-- pull the release zip and re-stamp last_install_source = "release".
-- @param on_success function or nil: fired after successful unpack
function Updater.installLatestStable(on_success)
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isWifiOn() then
        UIManager:show(InfoMessage:new{
            text = _("Wi-Fi is not enabled."),
            timeout = 3,
        })
        return
    end

    UIManager:show(InfoMessage:new{
        text = _("Downloading latest release..."),
        timeout = 1,
    })

    UIManager:scheduleIn(0.1, function()
        local installed_version = Updater.getInstalledVersion()
        local user_agent = "KOReader-Bookends/" .. installed_version
        local release = httpGetJSON(
            "https://api.github.com/repos/AndyHazz/bookends.koplugin/releases/latest",
            user_agent)
        if not release or not release.tag_name or release.draft or release.prerelease then
            Updater.offerReleasesPage(_("Could not fetch latest release."))
            return
        end
        local zip_url
        if release.assets then
            for _, asset in ipairs(release.assets) do
                if asset.name:match("%.zip$") then
                    zip_url = asset.browser_download_url
                    break
                end
            end
        end
        if not zip_url then
            Updater.offerReleasesPage(_("Latest release has no downloadable zip."))
            return
        end
        local new_version = release.tag_name:gsub("^v", "")
        Updater.install(zip_url, installed_version, new_version, on_success)
    end)
end
```

Note: `httpGetJSON` is a `local` function defined earlier in the same file (line 42), so it's reachable from this function as long as we keep it in `bookends_updater.lua`.

- [ ] **Step 2: Syntax check**

Run: `luac -p bookends_updater.lua && lua _test_updater.lua`
Expected: `ok` then `4 passed, 0 failed`

- [ ] **Step 3: Commit**

```bash
git add bookends_updater.lua
git commit -m "feat(updater): add installLatestStable wrapper"
```

---

### Task 6: Wire `on_success` through `Updater.check` for the release path

The existing release flow goes via `Updater.check` → `Updater.install`. Forward an optional `on_success` so callers of `check` can also stamp `last_install_source = "release"`.

**Files:**
- Modify: `bookends_updater.lua:162` (function `Updater.check`)

- [ ] **Step 1: Add parameter to signature**

In `bookends_updater.lua`, change:
```lua
function Updater.check()
```
to:
```lua
function Updater.check(on_success)
```

- [ ] **Step 2: Forward the callback into the inner `Updater.install` call**

Find the line `Updater.install(latest_zip_url, installed_version, latest_version)` (around line 270 inside the "Update and restart" button callback) and change it to:

```lua
Updater.install(latest_zip_url, installed_version, latest_version, on_success)
```

- [ ] **Step 3: Syntax check**

Run: `luac -p bookends_updater.lua && lua _test_updater.lua`
Expected: `ok` then `4 passed, 0 failed`

- [ ] **Step 4: Commit**

```bash
git add bookends_updater.lua
git commit -m "feat(updater): forward on_success through Updater.check"
```

---

### Task 7: Initialise the two new settings in `main.lua`

Read `dev_branch` and `last_install_source` near the other settings reads. No defaults are written to disk; reads supply the defaults at runtime so a fresh install needs no migration.

**Files:**
- Modify: `main.lua:609` (insertion after `self.check_updates = ...`)

- [ ] **Step 1: Add reads**

In `/home/andyhazz/projects/bookends.koplugin/main.lua`, find:
```lua
    self.check_updates = self.settings:readSetting("check_updates", false)
    self.stock_bar_disabled = self.settings:readSetting("stock_bar_disabled", false)
```

Insert between these two lines:
```lua
    self.dev_branch = self.settings:readSetting("dev_branch", "")
    self.last_install_source = self.settings:readSetting("last_install_source", "release")
```

So the block becomes:
```lua
    self.check_updates = self.settings:readSetting("check_updates", false)
    self.dev_branch = self.settings:readSetting("dev_branch", "")
    self.last_install_source = self.settings:readSetting("last_install_source", "release")
    self.stock_bar_disabled = self.settings:readSetting("stock_bar_disabled", false)
```

- [ ] **Step 2: Syntax check**

Run: `luac -p main.lua && echo ok`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add main.lua
git commit -m "feat(settings): persist dev_branch and last_install_source"
```

---

### Task 8: Dispatch in `Bookends:checkForUpdates`

The version row's callback in the menu calls `self:checkForUpdates()`. Branch on `self.dev_branch`: empty → existing release flow; non-empty → branch flow. Pass an `on_success` closure that stamps `self.last_install_source` and persists it.

**Files:**
- Modify: `main.lua:2324-2326` (function `Bookends:checkForUpdates`)

- [ ] **Step 1: Replace the function body**

Find:
```lua
function Bookends:checkForUpdates()
    Updater.check()
end
```

Replace with:
```lua
function Bookends:checkForUpdates()
    local settings = self.settings
    local dev_branch = self.dev_branch or ""
    if dev_branch ~= "" then
        Updater.installBranch(dev_branch, function()
            settings:saveSetting("last_install_source", "branch:" .. dev_branch)
        end)
    else
        Updater.check(function()
            settings:saveSetting("last_install_source", "release")
        end)
    end
end
```

- [ ] **Step 2: Syntax check**

Run: `luac -p main.lua && echo ok`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add main.lua
git commit -m "feat(main): dispatch checkForUpdates between release and branch"
```

---

### Task 9: `Bookends:editDevBranch` method

Opens an `InputDialog` pre-filled with the current `dev_branch`. Save trims and persists; Cancel discards. Empty submission clears the field.

**Files:**
- Modify: `main.lua` (insert immediately after `Bookends:checkForUpdates` ends, around line 2326)

- [ ] **Step 1: Add the method**

Insert into `main.lua` immediately after the closing `end` of `Bookends:checkForUpdates`:

```lua
function Bookends:editDevBranch(touchmenu_instance)
    local InputDialogMod = require("ui/widget/inputdialog")
    local UIManagerMod = require("ui/uimanager")
    local dlg
    dlg = InputDialogMod:new{
        title = _("Development branch"),
        input = self.dev_branch or "",
        input_hint = _("Branch name (leave empty for stable)"),
        buttons = {{
            { text = _("Cancel"), id = "close",
              callback = function() UIManagerMod:close(dlg) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local raw = dlg:getInputText() or ""
                local trimmed = raw:gsub("^%s+", ""):gsub("%s+$", "")
                self.dev_branch = trimmed
                self.settings:saveSetting("dev_branch", trimmed)
                UIManagerMod:close(dlg)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end },
        }},
    }
    UIManagerMod:show(dlg)
    dlg:onShowKeyboard()
end
```

- [ ] **Step 2: Syntax check**

Run: `luac -p main.lua && echo ok`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add main.lua
git commit -m "feat(main): add editDevBranch input dialog"
```

---

### Task 10: `Bookends:resetToStableRelease` method

`ConfirmBox` → on confirm, clear `dev_branch` and call `Updater.installLatestStable(on_success)`. The `on_success` stamps `last_install_source = "release"`.

**Files:**
- Modify: `main.lua` (insert immediately after `Bookends:editDevBranch`)

- [ ] **Step 1: Add the method**

Insert into `main.lua` immediately after the closing `end` of `Bookends:editDevBranch`:

```lua
function Bookends:resetToStableRelease()
    local ConfirmBoxMod = require("ui/widget/confirmbox")
    local UIManagerMod = require("ui/uimanager")
    UIManagerMod:show(ConfirmBoxMod:new{
        text = _("This will clear the development branch setting and install the latest stable release of Bookends, then restart KOReader. Continue?"),
        ok_text = _("Reset"),
        ok_callback = function()
            self.dev_branch = ""
            self.settings:saveSetting("dev_branch", "")
            local settings = self.settings
            Updater.installLatestStable(function()
                settings:saveSetting("last_install_source", "release")
            end)
        end,
    })
end
```

Note: `Updater` is already required at the top of `main.lua` (verified at line 31 area; same file already imports it for the existing update flow).

- [ ] **Step 2: Verify Updater import exists in main.lua**

Run: `grep -n 'local Updater = require' /home/andyhazz/projects/bookends.koplugin/main.lua`
Expected: at least one matching line. If no match, add `local Updater = require("bookends_updater")` near the other top-of-file requires.

- [ ] **Step 3: Syntax check**

Run: `luac -p main.lua && echo ok`
Expected: `ok`

- [ ] **Step 4: Commit**

```bash
git add main.lua
git commit -m "feat(main): add resetToStableRelease confirm flow"
```

---

### Task 11: Append "Advanced" submenu to `buildBookendsSettingsMenu`

Three rows: editable Development branch, Reset to latest stable release, status line.

**Files:**
- Modify: `menu/main_menu.lua:394` (last item of returned table)

- [ ] **Step 1: Add the new menu item**

Open `/home/andyhazz/projects/bookends.koplugin/menu/main_menu.lua`. Find the closing `},` of the version-row item at line 394 (the row with `text_func` showing `"Installed version: vX.Y.Z"`). The next line is `}` which closes the table returned from `buildBookendsSettingsMenu`.

Insert before that closing `}`:

```lua
        {
            text = _("Advanced"),
            sub_item_table = {
                {
                    text_func = function()
                        local b = self.dev_branch or ""
                        if b == "" then
                            return _("Development branch")
                        end
                        return _("Development branch") .. ": " .. b
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        self:editDevBranch(touchmenu_instance)
                    end,
                },
                {
                    text = _("Reset to latest stable release"),
                    keep_menu_open = true,
                    callback = function()
                        self:resetToStableRelease()
                    end,
                },
                {
                    text_func = function()
                        local current = Updater.getInstalledVersion()
                        local source = self.last_install_source or "release"
                        if source == "release" then
                            return _("Installed: v") .. current .. " (release)"
                        end
                        local branch = source:match("^branch:(.+)$") or source
                        return _("Installed: v") .. current .. " (branch: " .. branch .. ")"
                    end,
                    enabled_func = function() return false end,
                    keep_menu_open = true,
                },
            },
        },
```

The `enabled_func = function() return false end` on the status row makes it visually disabled (greyed out, untappable), which is the closest KOReader idiom to "info row".

- [ ] **Step 2: Syntax check**

Run: `luac -p menu/main_menu.lua && echo ok`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add menu/main_menu.lua
git commit -m "feat(menu): add Advanced submenu with branch switcher"
```

---

### Task 12: Push to Kindle and run smoke tests

Automated tests cover URL composition only. The rest needs device validation.

**Files:** none (deploy + manual test)

- [ ] **Step 1: Push the working tree to Kindle via tar-pipe**

Run from the plugin dir:
```bash
tar --exclude='.git' --exclude='.claude' --exclude='docs' --exclude='screenshots' --exclude='tools' --exclude='*.swp' -cf - . \
  | ssh kindle 'cd /mnt/us/koreader/plugins/bookends.koplugin && tar -xf -'
```
Expected: completes in ~1 second, no errors.

- [ ] **Step 2: Restart KOReader on the device**

Manual: on the Kindle, exit and reopen KOReader. (`killall -HUP koreader` does NOT trigger a reload — see memory.)

- [ ] **Step 3: Smoke test 1 — Stable round trip**

On the device:
1. Open Bookends → Settings → Advanced.
2. Confirm "Development branch" row shows "Development branch" with no value.
3. Confirm status row shows `Installed: vX.Y.Z (release)`.
4. Tap the version row in the parent settings (the "Installed version: vX.Y.Z" / "Update available" row).
5. Existing release flow runs (release notes if newer release available, "Bookends is up to date" if not).

Expected: existing behaviour, no regressions, `last_install_source` stays `"release"`.

- [ ] **Step 4: Smoke test 2 — Branch round trip**

On the device:
1. Settings → Advanced → Development branch.
2. Type `feature/v5.2-test`. Save.
3. Confirm the row label updates to `Development branch: feature/v5.2-test`.
4. Tap the version row in the parent settings.
5. Branch flow runs: download, restart prompt.
6. Confirm restart.
7. After restart, return to Settings → Advanced. Status row should now read `Installed: <version> (branch: feature/v5.2-test)`.

Expected: install succeeds, status line reflects the branch, the v5.2 features (`>=`, `<=`, flex layout) are exercisable.

- [ ] **Step 5: Smoke test 3 — Reset to stable**

On the device:
1. Settings → Advanced → Reset to latest stable release.
2. Confirm the dialog.
3. Release zip downloads, restart prompt fires, confirm.
4. After restart, return to Settings → Advanced.

Expected: `Development branch` row is empty again. Status row reads `Installed: vX.Y.Z (release)`.

- [ ] **Step 6: Smoke test 4 — 404 path**

On the device:
1. Settings → Advanced → Development branch. Type `does-not-exist-zzz`. Save.
2. Tap version row.
3. Download fails.

Expected: `Download failed.` `InfoMessage` (or "open releases page" prompt). `dev_branch` stays as `does-not-exist-zzz`. Status row unchanged from last successful install.

- [ ] **Step 7: Smoke test 5 — Whitespace input**

On the device:
1. Settings → Advanced → Development branch. Type `  feature/v5.2-test  ` (with leading and trailing spaces). Save.
2. Confirm row label shows `Development branch: feature/v5.2-test` (no spaces).

Expected: trim happens at save.

- [ ] **Step 8: Smoke test 6 — Wi-Fi off path**

On the device:
1. Set `dev_branch = feature/v5.2-test`.
2. Disable Wi-Fi.
3. Tap version row.

Expected: `Wi-Fi is not enabled.` `InfoMessage`. No download attempted. `dev_branch` and `last_install_source` unchanged.

- [ ] **Step 9: After all smoke tests pass, leave the device on the latest release.**

Tap Reset to latest stable release if necessary, so the device isn't left on the test branch.

---

### Task 13: Push the feature branch to origin

**Files:** none (git push)

- [ ] **Step 1: Confirm clean working tree**

Run: `git status`
Expected: `working tree clean` (everything committed across tasks 1-11).

- [ ] **Step 2: Push the branch**

Run: `git push -u origin feature/branch-switcher`
Expected: `[new branch]      feature/branch-switcher -> feature/branch-switcher`

- [ ] **Step 3: Verify on GitHub**

Run: `gh pr view feature/branch-switcher --repo AndyHazz/bookends.koplugin 2>/dev/null || gh api repos/AndyHazz/bookends.koplugin/branches/feature/branch-switcher --jq '.name'`
Expected: `feature/branch-switcher` (the branch exists on origin).

---

## Out of scope for this plan

Per the spec, deliberately not included here:

- Branch list / autocomplete via GitHub API.
- Tag picker.
- Automatic backups beyond the explicit Reset entry.
- Changes to the existing background release-poll (`Updater.checkBackground`).
- Updatesmanager integration.
- Hot-swap without restart.
- README user-facing docs update — the feature is intentionally not casually discoverable, so no README entry. (If we change our minds, add a small section under "Advanced" in the README in a follow-up commit.)
- Release version bump in `_meta.lua` — defer to whenever this ships as a release; not part of feature work.
