# Stable Page Numbers & Contrib Submission — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add setting to use stable page numbers for session stats (issue #14), and submit plugin to koreader/contrib (issue #13).

**Architecture:** A new helper method `getSessionPageNumber()` in main.lua returns a numeric stable page value using KOReader's pagemap index or hidden-flow APIs. A boolean setting `session_pages_stable` (default true) controls whether session tracking uses stable or raw page numbers. The contrib submission adds bookends as a git submodule to koreader/contrib.

**Tech Stack:** Lua (KOReader plugin), git submodules, GitHub CLI

---

## Task 1: Add `getSessionPageNumber()` helper method

**Files:**
- Modify: `main.lua:754-762` (onPageUpdate) and add new method near line 796

- [ ] **Step 1: Add the helper method after `getSessionElapsed()` (after line 802)**

```lua
function Bookends:getSessionPageNumber()
    local pageno = self.ui.view.state.page
    if not pageno then return nil end
    if not self.settings:isTrue("session_pages_stable") then
        return pageno
    end
    -- Pagemap: use numeric index (2nd return value), not the label string
    if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
        local _label, idx, _count = self.ui.pagemap:getCurrentPageLabel(true)
        if idx then return idx end
    end
    -- Hidden flows: page number within current flow
    local doc = self.ui.document
    if doc and doc:hasHiddenFlows() then
        return doc:getPageNumberInFlow(pageno)
    end
    return pageno
end
```

- [ ] **Step 2: Update `onPageUpdate` to use the helper**

Replace `main.lua:754-763`:
```lua
function Bookends:onPageUpdate()
    local current = self:getSessionPageNumber()
    if current then
        if not self.session_start_page then
            self.session_start_page = current
            self.session_max_page = current
        elseif current > self.session_max_page then
            self.session_max_page = current
        end
    end
```

- [ ] **Step 3: Update init comment to reflect new behavior**

Change `main.lua:138-139` from:
```lua
    self.session_start_page = nil -- raw page, set on first onPageUpdate
    self.session_max_page = nil   -- highest raw page reached
```
To:
```lua
    self.session_start_page = nil -- set on first onPageUpdate (stable or raw per setting)
    self.session_max_page = nil   -- highest page reached (stable or raw per setting)
```

- [ ] **Step 4: Syntax check**

Run: `luac -p main.lua`
Expected: no output (clean)

- [ ] **Step 5: Commit**

```bash
git add main.lua
git commit -m "feat: use stable page numbers for session stats (#14)"
```

---

## Task 2: Add menu toggle for stable page numbers

**Files:**
- Modify: `main.lua:1529-1534` (Settings menu, after "Progress bar colours and tick marks" separator)

- [ ] **Step 1: Add the toggle menu item after the bar colours entry (after line 1534)**

Insert before the "Disable stock status bar" entry:
```lua
                {
                    text = _("Use stable page numbers for session stats"),
                    keep_menu_open = true,
                    help_text = _("When enabled, session page counts use KOReader's stable page numbering (if available) instead of internal page numbers. Affects the %s (session pages) and %r (reading speed) tokens."),
                    checked_func = function()
                        return self.settings:isTrue("session_pages_stable")
                    end,
                    callback = function()
                        if self.settings:isTrue("session_pages_stable") then
                            self.settings:saveSetting("session_pages_stable", false)
                        else
                            self.settings:saveSetting("session_pages_stable", true)
                        end
                        -- Reset session tracking to use new page numbering
                        self.session_start_page = nil
                        self.session_max_page = nil
                        self:markDirty()
                    end,
                },
```

- [ ] **Step 2: Set default value for the setting**

In `loadSettings()` (around line 247), the setting needs to default to true. Since `isTrue()` returns false for nil, we need to initialize it. After `self.enabled = self.settings:readSetting("enabled", false)` (line 247), add:

```lua
    if self.settings:readSetting("session_pages_stable") == nil then
        self.settings:saveSetting("session_pages_stable", true)
    end
```

- [ ] **Step 3: Syntax check**

Run: `luac -p main.lua`
Expected: no output (clean)

- [ ] **Step 4: Commit**

```bash
git add main.lua
git commit -m "feat: add menu toggle for stable page numbers setting"
```

---

## Task 3: Add translations for new strings

**Files:**
- Modify: `locale/bookends.pot`, `locale/es.po`, `locale/de.po`, `locale/fr.po`, `locale/it.po`, `locale/pt_BR.po`

- [ ] **Step 1: Add msgid/msgstr entries to each file**

Two new strings to add:
1. `"Use stable page numbers for session stats"`
2. `"When enabled, session page counts use KOReader's stable page numbering (if available) instead of internal page numbers. Affects the %s (session pages) and %r (reading speed) tokens."`

Translations for the menu label:
- es: `"Usar numeración estable de páginas para estadísticas de sesión"`
- de: `"Stabile Seitennummern für Sitzungsstatistiken verwenden"`
- fr: `"Utiliser la numérotation stable des pages pour les statistiques de session"`
- it: `"Usa numerazione stabile delle pagine per le statistiche della sessione"`
- pt_BR: `"Usar numeração estável de páginas para estatísticas da sessão"`

The help_text string can be left untranslated (empty msgstr) in all locales — it's long and technical.

- [ ] **Step 2: Commit**

```bash
git add locale/
git commit -m "i18n: add translations for stable page numbers setting"
```

---

## Task 4: Fork koreader/contrib and submit PR

**Files:**
- External repo: `koreader/contrib`

- [ ] **Step 1: Fork the contrib repo**

```bash
gh repo fork koreader/contrib --clone=false
```

- [ ] **Step 2: Clone the fork and add bookends as submodule**

```bash
cd /tmp
gh repo clone AndyHazz/contrib -- --depth=1
cd contrib
git checkout -b add-bookends
git submodule add https://github.com/AndyHazz/bookends.koplugin.git bookends.koplugin
```

- [ ] **Step 3: Create OWNER file**

Create `bookends.koplugin/OWNER`:
```
AndyHazz
```

Note: The submodule clone already includes the plugin's README.md which documents features, screenshots, installation, and compatibility.

- [ ] **Step 4: Commit and push**

```bash
git add .
git commit -m "Add bookends.koplugin — configurable on-screen display overlay"
git push -u origin add-bookends
```

- [ ] **Step 5: Create PR**

```bash
gh pr create --repo koreader/contrib --title "Add bookends.koplugin" --body "$(cat <<'EOF'
## Summary

Adds [bookends.koplugin](https://github.com/AndyHazz/bookends.koplugin) — a fully configurable on-screen display overlay for KOReader.

**Features:**
- Six configurable display positions (corners/edges) with format tokens for page numbers, chapter progress, time, battery, Wi-Fi, session stats, and more
- Multiple progress bar styles (solid, bordered, rounded, metro) with per-bar color/tick customization
- File-based preset system for sharing configurations
- Line editor with symbol picker and token browser
- Full i18n support (EN, ES, DE, FR, IT, PT-BR)

**Compatibility:** Tested on Kindle Paperwhite and Kobo devices. Requires KOReader 2024.11+.

**Maintainer:** @AndyHazz (OWNER file included)
EOF
)"
```

- [ ] **Step 6: Report PR URL**
