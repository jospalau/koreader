# Fix Page-Related Tokens for Stable Page Numbering — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all page-related tokens in tokens.lua so they produce correct values when KOReader's stable page numbering (pagemap or hidden flows) is active.

**Architecture:** The current code mixes pagemap label strings (for display) with raw page numbers (for arithmetic), causing wrong totals, empty values, and negative chapter counts. The fix uses the numeric `idx` and `count` values from `pagemap:getCurrentPageLabel()` for all arithmetic, while keeping the string label for `%c` display only. Chapter tokens get clamped to prevent negatives on unmapped pages (covers). Reading speed switches to session-based calculation.

**Tech Stack:** Lua (KOReader plugin)

---

## Key API Reference

`pagemap:getCurrentPageLabel(clean)` returns 3 values: `(label, idx, count)`
- `label` — string like "iii", "42" (for display)
- `idx` — numeric sequential index through all mapped pages (1-based, for arithmetic)
- `count` — total number of mapped pages (for arithmetic)

`doc:getPageNumberInFlow(pageno)` — numeric page within current flow
`doc:getTotalPagesInFlow(flow)` — total pages in flow
`doc:getPageFlow(pageno)` — flow ID for a page
`toc:getChapterPagesLeft(pageno)` — already handles pagemap internally, but can return negative on unmapped pages
`toc:getChapterPagesDone(pageno)` — already handles pagemap internally, can return nil on unmapped pages
`toc:getChapterPageCount(pageno)` — already handles pagemap internally, can return nil on unmapped pages

---

## Task 1: Fix %c, %t, %p, %L (page number, total, percent, pages left in book)

**Files:**
- Modify: `tokens.lua:129-165`

The core block that computes currentpage, totalpages, percent, and pages_left_book.

- [ ] **Step 1: Replace the page numbers block (lines 129–165)**

Replace the entire block from `-- Page numbers` through the closing `end` at line 165 with:

```lua
    -- Page numbers (respects hidden flows + pagemap)
    local currentpage = ""
    local totalpages = ""
    local percent = ""
    local pages_left_book = ""
    -- Numeric page indices for arithmetic (separate from display labels)
    local page_idx = nil   -- numeric current page position
    local page_count = nil -- numeric total pages
    if needs("c", "t", "p", "L") then
        if ui.pagemap and ui.pagemap:wantsPageLabels() then
            local label, idx, count = ui.pagemap:getCurrentPageLabel(true)
            currentpage = label or ""
            page_idx = idx
            page_count = count
            -- Total: show count of mapped pages (not the last label, which may be "279" while count is 247)
            totalpages = count and tostring(count) or ""
        elseif pageno and doc:hasHiddenFlows() then
            currentpage = doc:getPageNumberInFlow(pageno)
            local flow = doc:getPageFlow(pageno)
            totalpages = doc:getTotalPagesInFlow(flow)
            page_idx = tonumber(currentpage)
            page_count = tonumber(totalpages)
        else
            currentpage = pageno or 0
            totalpages = doc:getPageCount()
            page_idx = pageno
            page_count = tonumber(totalpages)
        end

        if page_idx and page_count and page_count > 0 then
            percent = math.floor(page_idx / page_count * 100) .. "%"
            pages_left_book = math.max(0, page_count - page_idx)
        end
    end
```

**What this fixes:**
- `%t` — now shows mapped page count (e.g. 247) not raw total (279) when pagemap active
- `%p` — now uses numeric idx/count, not `pageno / raw_total`
- `%L` — now uses `count - idx` (always numeric), not `tonumber("iii")` which was nil
- `%c` — still shows the pagemap label string ("iii") for display

- [ ] **Step 2: Syntax check**

Run: `luac -p tokens.lua`
Expected: no output (clean)

- [ ] **Step 3: Commit**

```bash
git add tokens.lua
git commit -m "fix: use pagemap idx/count for page arithmetic (%t, %p, %L tokens)"
```

---

## Task 2: Fix %l, %g, %G, %P (chapter pages left, done, total, percent)

**Files:**
- Modify: `tokens.lua:167-185`

- [ ] **Step 1: Replace the chapter progress block (lines 167–185)**

Replace from `-- Chapter progress` through the closing of the `if needs(...)` block:

```lua
    -- Chapter progress
    local chapter_pct = ""
    local chapter_pages_done = ""
    local chapter_pages_left = ""
    local chapter_total_pages = ""
    local chapter_title = ""
    if needs("P", "g", "G", "l", "C") and pageno and ui.toc then
        local done = ui.toc:getChapterPagesDone(pageno)
        local total = ui.toc:getChapterPageCount(pageno)
        if done and total and total > 0 then
            chapter_pages_done = math.max(0, done + 1)
            chapter_total_pages = total
            chapter_pct = math.floor(chapter_pages_done / total * 100) .. "%"
        end
        local left = ui.toc:getChapterPagesLeft(pageno)
        if left then chapter_pages_left = math.max(0, left) end
        local title = ui.toc:getTocTitleByPage(pageno)
        if title and title ~= "" then chapter_title = title end
    end
```

**What this fixes:**
- `%l` — clamped to 0 with `math.max(0, left)`, preventing "-1" on cover/unmapped pages
- `%g` — clamped to 0 with `math.max(0, done + 1)`, preventing negative values
- `%G` and `%P` — no change needed (already correct when done/total are valid)

- [ ] **Step 2: Syntax check**

Run: `luac -p tokens.lua`
Expected: no output (clean)

- [ ] **Step 3: Commit**

```bash
git add tokens.lua
git commit -m "fix: clamp chapter page tokens to zero on unmapped pages (%l, %g)"
```

---

## Task 3: Fix %r (reading speed — pages per hour)

**Files:**
- Modify: `tokens.lua:390-407`

- [ ] **Step 1: Replace the reading speed block (lines 390–407)**

Replace from `-- Reading speed` through the closing `end`:

```lua
    -- Reading speed and total book time (via statistics plugin)
    local reading_speed = ""
    local total_book_time = ""
    if needs("r", "E") then
        if needs("r") then
            -- Prefer session-based speed (respects stable page numbering)
            if session_elapsed and session_elapsed > 60 and session_pages > 0 then
                reading_speed = tostring(math.floor(session_pages / session_elapsed * 3600))
            elseif ui.statistics then
                local avg = ui.statistics.avg_time
                if avg and avg > 0 then
                    reading_speed = tostring(math.floor(3600 / avg))
                end
            end
        end
        if needs("E") and ui.statistics then
            local total_secs = ui.statistics.book_read_time
            if total_secs and total_secs > 0 then
                local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
                total_book_time = datetime.secondsToClockDuration(user_duration_format, total_secs, true)
            end
        end
    end
```

**What this fixes:**
- `%r` — uses `session_pages / session_elapsed * 3600` which respects stable page numbering (session_pages already uses stable numbers via the Task 1 helper in main.lua)
- Requires 60 seconds of session time before showing session-based speed (avoids wild numbers at session start)
- Falls back to historical `avg_time` when session data is insufficient
- `%E` (total book time) unchanged — it's time-based, not page-number-dependent

- [ ] **Step 2: Syntax check**

Run: `luac -p tokens.lua`
Expected: no output (clean)

- [ ] **Step 3: Commit**

```bash
git add tokens.lua
git commit -m "fix: session-based reading speed for %r token, respects stable pages"
```

---

## Task 4: Fix %h, %H (time left in chapter / book)

**Files:**
- Modify: `tokens.lua:274-295`

- [ ] **Step 1: Replace the time-left block (lines 274–295)**

Replace from `-- Time left in chapter` through the closing `end`:

```lua
    -- Time left in chapter / document (via statistics plugin)
    local time_left_chapter = ""
    local time_left_doc = ""
    if needs("h", "H") and pageno and ui.statistics and ui.statistics.getTimeForPages then
        if needs("h") then
            local ch_left = ui.toc and ui.toc:getChapterPagesLeft(pageno, true)
            if ch_left and ch_left > 0 then
                local result = ui.statistics:getTimeForPages(ch_left)
                if result and result ~= "N/A" then time_left_chapter = result end
            end
        end
        if needs("H") and page_count and page_idx then
            local doc_left = math.max(0, page_count - page_idx)
            if doc_left > 0 then
                local result = ui.statistics:getTimeForPages(doc_left)
                if result and result ~= "N/A" then time_left_doc = result end
            end
        end
    end
```

**What this fixes:**
- `%h` — adds `ch_left > 0` guard, preventing 0m/negative time on cover pages. Removes fallback to `getTotalPagesLeft` (which was a book-level fallback for a chapter-level token — wrong)
- `%H` — uses `page_count - page_idx` (the stable-aware values computed in Task 1) instead of raw `getTotalPagesLeft(pageno)`. The `page_count`/`page_idx` variables are set in the page numbers block and scoped to the entire function.

**Important:** This task depends on Task 1 having been implemented, because it uses `page_count` and `page_idx` which are declared in the page numbers block. These variables are local to the `expand()` function scope and visible here.

- [ ] **Step 2: Syntax check**

Run: `luac -p tokens.lua`
Expected: no output (clean)

- [ ] **Step 3: Commit**

```bash
git add tokens.lua
git commit -m "fix: time-left tokens use stable page counts, guard against negatives"
```

---

## Task 5: Fix %bar book progress for pagemap

**Files:**
- Modify: `tokens.lua:196-208`

- [ ] **Step 1: Replace the book progress calculation in the bar block (lines 196–208)**

Replace from `-- Book progress` through the closing `end` of the `if raw_total` block:

```lua
        -- Book progress (page-based, respects pagemap/hidden flows)
        local book_pct
        if page_idx and page_count and page_count > 0 then
            book_pct = page_idx / page_count
        else
            local raw_total = bar_doc:getPageCount()
            if raw_total and raw_total > 0 then
                if bar_doc:hasHiddenFlows() then
                    local flow = bar_doc:getPageFlow(bar_pageno)
                    local flow_total = bar_doc:getTotalPagesInFlow(flow)
                    local flow_page = bar_doc:getPageNumberInFlow(bar_pageno)
                    book_pct = flow_total > 0 and (flow_page / flow_total) or 0
                else
                    book_pct = bar_pageno / raw_total
                end
            end
        end
```

**What this fixes:**
- Progress bar now uses the same stable `page_idx / page_count` values as text tokens when pagemap is active
- Falls back to the existing hidden-flows and raw-page logic when pagemap is not available
- **Depends on Task 1** for `page_idx` and `page_count` variables

- [ ] **Step 2: Syntax check**

Run: `luac -p tokens.lua`
Expected: no output (clean)

- [ ] **Step 3: Commit**

```bash
git add tokens.lua
git commit -m "fix: progress bar uses stable page numbers when pagemap active"
```

---

## Task 6: Add translations and push to Kindle for testing

**Files:**
- Modify: All `locale/*.po` files and `locale/bookends.pot` (no new strings — this is a code-only fix)
- Push to Kindle for verification

- [ ] **Step 1: Verify no new translatable strings were introduced**

Run: `grep -n '_(' tokens.lua`
Expected: Only existing strings (no new `_()` calls added in Tasks 1–5)

- [ ] **Step 2: Final syntax check of all changed files**

Run: `luac -p tokens.lua main.lua`
Expected: no output (clean)

- [ ] **Step 3: Push to Kindle**

```bash
scp tokens.lua kindle:/mnt/us/koreader/plugins/bookends.koplugin/tokens.lua
```

- [ ] **Step 4: Verify on device**

Restart KOReader. On the test book (There Is No Antimemetics Division):
- Cover page should show "Page iii of [count]" where count is the number of mapped pages, not 279
- Pages left in book should be a positive number
- Chapter pages left should be 0 (not -1) on cover
- Progress percent should reflect position within mapped pages
- After reading a few pages, %r should show a session-based reading speed
