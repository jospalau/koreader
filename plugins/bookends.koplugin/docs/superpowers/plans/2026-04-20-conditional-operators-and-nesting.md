# Conditional Operators, Nesting & Predicate Expansion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend bookends' `[if:...]...[/if]` conditional grammar with nesting, `and`/`or`/`not`/parens in predicates, new numeric predicates (`chapter`, `chapters`), new string predicates (`title`, `author`, `series`, `chapter_title`, `chapter_title_1..3`), and renamed predicates (`percent` → `book_pct`, old `chapter` → `chapter_pct`, `pages` → `session_pages`).

**Architecture:** All runtime changes live in `bookends_tokens.lua`. Three local-function replacements (`processConditionals`, new `evaluateExpression`, extended `buildConditionState`), one factored-out helper (`Tokens.getChapterTitlesByDepth`), and test-only internal exports prefixed with `_`. A new root-level scratch test script (`_test_conditionals.lua`) exercises the pure-parsing path on the dev box via stubbed KOReader requires — no on-device round-trip needed for parser regressions.

**Tech Stack:** Lua 5.1 (KOReader runtime). KOReader APIs: `ui.toc`, `ui.doc_props`, `document:getProps()`. Parser is dependency-free. Syntax validation via `luac -p`. On-device validation via SCP to Kindle following the established dev workflow.

**Spec:** `docs/superpowers/specs/2026-04-20-conditional-operators-and-nesting-design.md`

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `bookends_tokens.lua` | Token expansion and conditional evaluation | Replace `processConditionals`, add `evaluateExpression` + tokeniser, extend `buildConditionState`, add `Tokens.getChapterTitlesByDepth` helper, add test-only internal exports |
| `_test_conditionals.lua` | Dev-box test runner for pure parser logic | **New.** Stubs KOReader `require()`s, loads `bookends_tokens.lua`, runs a plain-Lua assertion suite covering nesting/operators/predicates |
| `README.md` | User docs | Update conditional-predicate table and one example |
| `docs/release-notes-4.1.0.md` | Draft for GitHub release | **New.** Copy-paste source for the GitHub release description when cutting the next version |

No other files touched. No schema migration. No new dependencies.

---

## Task 1: Branch setup

**Files:** None (git state only).

- [ ] **Step 1: Verify clean working tree on master**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin status --short --branch
```

Expected: `## master...origin/master` with nothing tracked as modified. `.claude/` and `docs/superpowers/` may appear untracked — that's fine (both gitignored).

- [ ] **Step 2: Create feature branch**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin checkout -b feature/conditional-operators
```

Expected: `Switched to a new branch 'feature/conditional-operators'`.

---

## Task 2: Scaffold the test runner

**Files:**
- Create: `_test_conditionals.lua`

- [ ] **Step 1: Create the test runner with stubbed KOReader requires**

Create `/home/andyhazz/projects/bookends.koplugin/_test_conditionals.lua` with this exact content:

```lua
-- Dev-box test runner for bookends_tokens.lua conditional parsing.
-- Runs pure-Lua (no KOReader) by stubbing the modules bookends_tokens requires.
-- Usage: cd into the plugin dir, then `lua _test_conditionals.lua`.
-- Exits non-zero on failure; no external dependencies.

package.loaded["device"] = {
    getPowerDevice = function() return nil end,
    isKindle = function() return false end,
}
package.loaded["datetime"] = {
    secondsToClockDuration = function() return "" end,
}
package.loaded["bookends_overlay_widget"] = { BAR_PLACEHOLDER = "\x00BAR\x00" }

-- G_reader_settings is a global in KOReader; stub it so module load succeeds.
_G.G_reader_settings = setmetatable({}, {
    __index = function() return function() return false end end,
})

local Tokens = dofile("bookends_tokens.lua")

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

-- ============================================================================
-- Tests go here. Filled in by later tasks.
-- ============================================================================

io.stdout:write(string.format("%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
```

- [ ] **Step 2: Run the scaffolding to verify it loads the module cleanly**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin && lua _test_conditionals.lua
```

Expected output:
```
0 passed, 0 failed
```

Exit code 0. If the module fails to load, the stubs are missing something; fix before proceeding.

- [ ] **Step 3: Commit**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
git add _test_conditionals.lua
git commit -m "test: scaffold dev-box runner for conditional parsing"
```

---

## Task 3: Expose internal parser functions for testing + baseline regression tests

**Goal:** Before changing any logic, expose the current `processConditionals` and `evaluateCondition` as `Tokens._processConditionals` and `Tokens._evaluateCondition` so the test runner can exercise them. Add a regression suite that locks in current behaviour. All tests pass against the unmodified parser — this is our safety net for the upcoming changes.

**Files:**
- Modify: `bookends_tokens.lua` (add test-only exports near the end of file, just before `return Tokens`)
- Modify: `_test_conditionals.lua` (add baseline regression suite)

- [ ] **Step 1: Add internal exports to `bookends_tokens.lua`**

Find the end of the file:
```lua
function Tokens.expandPreview(format_str, ui, session_elapsed, session_pages_read, tick_width_multiplier, symbol_color)
    return Tokens.expand(format_str, ui, session_elapsed, session_pages_read, true, tick_width_multiplier, symbol_color)
end

return Tokens
```

Insert **before** `return Tokens`:
```lua

-- Test-only internal exports. Underscore prefix marks these as private —
-- they are exposed solely so _test_conditionals.lua can exercise the parser
-- without needing a running KOReader. Not stable API; may change without notice.
Tokens._processConditionals = processConditionals
Tokens._evaluateCondition   = evaluateCondition
```

- [ ] **Step 2: Verify syntax and module still loads**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
luac -p bookends_tokens.lua && echo "syntax OK"
lua _test_conditionals.lua
```

Expected: `syntax OK`, then `0 passed, 0 failed`, exit 0.

- [ ] **Step 3: Add baseline regression tests to `_test_conditionals.lua`**

In `_test_conditionals.lua`, replace the line `-- Tests go here. Filled in by later tasks.` with:

```lua
-- ----------------------------------------------------------------------------
-- Baseline: tests that must pass against the CURRENT (pre-change) parser.
-- These lock in existing behaviour so the upcoming rewrite can't regress it.
-- ----------------------------------------------------------------------------

-- Flat truthy predicate
test("flat truthy: state value 'yes' is true", function()
    local r = Tokens._processConditionals("[if:charging=yes]+[/if]", { charging = "yes" })
    eq(r, "+")
end)

test("flat truthy: state value 'no' is false", function()
    local r = Tokens._processConditionals("[if:charging=yes]+[/if]", { charging = "no" })
    eq(r, "")
end)

-- Bare-key truthy check (no operator)
test("bare key: empty string is falsy", function()
    local r = Tokens._processConditionals("[if:x]YES[/if]", { x = "" })
    eq(r, "")
end)

test("bare key: non-empty string is truthy", function()
    local r = Tokens._processConditionals("[if:x]YES[/if]", { x = "hello" })
    eq(r, "YES")
end)

-- Numeric comparison
test("batt<20 when batt=15 → true", function()
    local r = Tokens._processConditionals("[if:batt<20]LOW[/if]", { batt = 15 })
    eq(r, "LOW")
end)

test("batt<20 when batt=85 → false", function()
    local r = Tokens._processConditionals("[if:batt<20]LOW[/if]", { batt = 85 })
    eq(r, "")
end)

-- HH:MM numeric coercion
test("time>=18:30 when time=1110 (18:30) → true", function()
    local r = Tokens._processConditionals("[if:time>18:00]evening[/if]", { time = 18*60 + 30 })
    eq(r, "evening")
end)

-- [else] branch
test("[else] branch when predicate false", function()
    local r = Tokens._processConditionals("[if:a=1]A[else]B[/if]", { a = 2 })
    eq(r, "B")
end)

test("[else] branch when predicate true → takes if-part", function()
    local r = Tokens._processConditionals("[if:a=1]A[else]B[/if]", { a = 1 })
    eq(r, "A")
end)

-- Multiple sibling blocks
test("two sibling blocks both resolve", function()
    local r = Tokens._processConditionals("[if:a=1]A[/if]-[if:b=2]B[/if]", { a = 1, b = 2 })
    eq(r, "A-B")
end)

-- No conditional content left alone
test("string with no conditionals passes through", function()
    local r = Tokens._processConditionals("plain text %T %A", {})
    eq(r, "plain text %T %A")
end)

-- Unknown key
test("unknown key evaluates to false", function()
    local r = Tokens._processConditionals("[if:xyzzy=yes]X[/if]", {})
    eq(r, "")
end)
```

- [ ] **Step 4: Run the baseline suite**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin && lua _test_conditionals.lua
```

Expected: `12 passed, 0 failed`. If any fail, the baseline is recording a misunderstanding of current behaviour — fix the test before proceeding.

- [ ] **Step 5: Commit**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
git add bookends_tokens.lua _test_conditionals.lua
git commit -m "test(tokens): baseline regression suite for conditional parsing"
```

---

## Task 4: Add `evaluateExpression` — tokeniser + recursive-descent parser

**Goal:** Introduce the new expression evaluator as a standalone function. It is NOT wired into `processConditionals` yet — we simply add it, export it for testing, and verify it works on its own. This keeps the diff bisectable.

**Files:**
- Modify: `bookends_tokens.lua` (add `tokeniseExpression` and `evaluateExpression` locals just above the existing `processConditionals` function at line 106)
- Modify: `_test_conditionals.lua` (add evaluator tests)

- [ ] **Step 1: Write failing tests for the evaluator**

Append to `_test_conditionals.lua` (after the baseline block):

```lua

-- ----------------------------------------------------------------------------
-- Expression evaluator (new) — tests exercising Tokens._evaluateExpression
-- directly, before it is wired into processConditionals.
-- ----------------------------------------------------------------------------

local function E(cond, state) return Tokens._evaluateExpression(cond, state or {}) end

test("evaluator: single atom true", function() eq(E("a=1", {a=1}), true)  end)
test("evaluator: single atom false",function() eq(E("a=1", {a=2}), false) end)

test("evaluator: AND both true",    function() eq(E("a=1 and b=2", {a=1,b=2}), true)  end)
test("evaluator: AND one false",    function() eq(E("a=1 and b=2", {a=1,b=3}), false) end)

test("evaluator: OR one true",      function() eq(E("a=1 or b=2",  {a=1,b=3}), true)  end)
test("evaluator: OR both false",    function() eq(E("a=1 or b=2",  {a=0,b=3}), false) end)

test("evaluator: NOT inverts true",  function() eq(E("not a=1", {a=1}), false) end)
test("evaluator: NOT inverts false", function() eq(E("not a=1", {a=2}), true)  end)

test("evaluator: parens group",      function()
    eq(E("(a=1 or b=2) and c=3", {a=1, b=0, c=3}), true)
    eq(E("(a=1 or b=2) and c=3", {a=0, b=2, c=3}), true)
    eq(E("(a=1 or b=2) and c=3", {a=0, b=0, c=3}), false)
    eq(E("(a=1 or b=2) and c=3", {a=1, b=0, c=4}), false)
end)

test("evaluator: precedence — and binds tighter than or", function()
    -- a=1 or b=2 and c=3  ≡  a=1 or (b=2 and c=3)
    eq(E("a=1 or b=2 and c=3", {a=1, b=0, c=0}), true)   -- a alone
    eq(E("a=1 or b=2 and c=3", {a=0, b=2, c=3}), true)   -- b and c together
    eq(E("a=1 or b=2 and c=3", {a=0, b=2, c=4}), false)  -- c fails so b alone insufficient
end)

test("evaluator: precedence — not binds tighter than and", function()
    -- not a=1 and b=2  ≡  (not a=1) and b=2
    eq(E("not a=1 and b=2", {a=2, b=2}), true)
    eq(E("not a=1 and b=2", {a=1, b=2}), false)
end)

-- Bare atom (truthy form) — existing evaluateCondition fallback must still work
test("evaluator: bare-key truthy (non-empty string)", function()
    eq(E("title", {title = "Foo"}), true)
end)

test("evaluator: bare-key truthy (empty string)", function()
    eq(E("title", {title = ""}), false)
end)
```

- [ ] **Step 2: Run the suite to confirm the new tests fail**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin && lua _test_conditionals.lua
```

Expected: `12 passed, N failed` where the new tests error with `attempt to call a nil value (method '_evaluateExpression')` or similar.

- [ ] **Step 3: Add the tokeniser and evaluator to `bookends_tokens.lua`**

Open `bookends_tokens.lua`. Find the existing `evaluateCondition` function (around line 78–103) and the existing `processConditionals` that follows it (line 106–119). Insert the new code **between** these two functions (after `evaluateCondition`'s closing `end`, before the `--- Process [if:condition]...[/if] blocks...` comment).

```lua

--- Tokenise a conditional-expression string into keyword / paren / atom tokens.
-- Whitespace separates tokens. "(" and ")" are always single tokens.
-- The words "and", "or", "not" (lowercase, exact match) are keywords.
-- Everything else is an atom, passed verbatim to evaluateCondition.
local function tokeniseExpression(cond_str)
    local tokens = {}
    local i, len = 1, #cond_str
    while i <= len do
        local c = cond_str:sub(i, i)
        if c == " " or c == "\t" then
            i = i + 1
        elseif c == "(" or c == ")" then
            tokens[#tokens + 1] = { kind = "op", value = c }
            i = i + 1
        else
            local j = i
            while j <= len do
                local cj = cond_str:sub(j, j)
                if cj == " " or cj == "\t" or cj == "(" or cj == ")" then break end
                j = j + 1
            end
            local word = cond_str:sub(i, j - 1)
            if word == "and" or word == "or" or word == "not" then
                tokens[#tokens + 1] = { kind = "op", value = word }
            else
                tokens[#tokens + 1] = { kind = "atom", value = word }
            end
            i = j
        end
    end
    return tokens
end

--- Evaluate a conditional expression with operators (and/or/not/parens).
-- Recursive-descent parser. Precedence: not > and > or (standard).
-- A bare atom is delegated to evaluateCondition, preserving all legacy
-- atom semantics (numeric comparison, HH:MM, truthiness).
local function evaluateExpression(cond_str, state)
    local tokens = tokeniseExpression(cond_str)
    local pos = 1
    local function peek() return tokens[pos] end
    local function advance()
        local t = tokens[pos]; pos = pos + 1; return t
    end

    local parseOr  -- forward declaration for mutual recursion

    local function parsePrimary()
        local t = peek()
        if not t then return false end
        if t.kind == "op" and t.value == "(" then
            advance()
            local v = parseOr()
            local cl = peek()
            if cl and cl.kind == "op" and cl.value == ")" then advance() end
            return v
        end
        if t.kind == "atom" then
            advance()
            return evaluateCondition(t.value, state)
        end
        -- Stray "and"/"or"/")"/etc. — skip and continue as false
        advance()
        return false
    end

    local function parseNot()
        local t = peek()
        if t and t.kind == "op" and t.value == "not" then
            advance()
            return not parseNot()
        end
        return parsePrimary()
    end

    local function parseAnd()
        local left = parseNot()
        while true do
            local t = peek()
            if not (t and t.kind == "op" and t.value == "and") then break end
            advance()
            local right = parseNot()
            left = left and right
        end
        return left
    end

    parseOr = function()
        local left = parseAnd()
        while true do
            local t = peek()
            if not (t and t.kind == "op" and t.value == "or") then break end
            advance()
            local right = parseAnd()
            left = left or right
        end
        return left
    end

    return parseOr()
end
```

- [ ] **Step 4: Add the export alongside the existing one**

In `bookends_tokens.lua`, find the test-only export block added in Task 3:
```lua
Tokens._processConditionals = processConditionals
Tokens._evaluateCondition   = evaluateCondition
```

Add **immediately after**:
```lua
Tokens._evaluateExpression  = evaluateExpression
```

- [ ] **Step 5: Verify syntax, then run the suite**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
luac -p bookends_tokens.lua && echo "syntax OK"
lua _test_conditionals.lua
```

Expected: all baseline tests + all new evaluator tests pass. Total around **25 passed, 0 failed**.

- [ ] **Step 6: Commit**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
git add bookends_tokens.lua _test_conditionals.lua
git commit -m "feat(tokens): add evaluateExpression with and/or/not/parens"
```

---

## Task 5: Replace `processConditionals` with peel-innermost loop + evaluator

**Goal:** Now that the evaluator exists and is tested in isolation, swap the single-pass gsub in `processConditionals` for an innermost-peel loop that calls `evaluateExpression` for the predicate. This is the one task that enables **both** nesting and operators in real format strings.

**Files:**
- Modify: `bookends_tokens.lua:106–119` (rewrite `processConditionals`)
- Modify: `_test_conditionals.lua` (append nesting + operator-via-processConditionals tests)

- [ ] **Step 1: Write failing tests for nesting + operator-end-to-end**

Append to `_test_conditionals.lua`:

```lua

-- ----------------------------------------------------------------------------
-- processConditionals with nesting (new) + operators end-to-end.
-- ----------------------------------------------------------------------------

local function P(fmt, state) return Tokens._processConditionals(fmt, state or {}) end

-- Nesting
test("nest: inner+outer both true", function()
    eq(P("[if:a=1][if:b=2]INNER[/if][/if]", {a=1, b=2}), "INNER")
end)

test("nest: outer true, inner false", function()
    eq(P("[if:a=1][if:b=2]INNER[/if][/if]", {a=1, b=9}), "")
end)

test("nest: outer false (inner irrelevant)", function()
    eq(P("[if:a=1][if:b=2]INNER[/if][/if]", {a=9, b=2}), "")
end)

test("nest: 3 levels, all true", function()
    eq(P("[if:a=1][if:b=2][if:c=3]X[/if][/if][/if]", {a=1,b=2,c=3}), "X")
end)

test("nest: outer has text before and after inner", function()
    eq(P("[if:a=1]X[if:b=2]Y[/if]Z[/if]", {a=1, b=2}), "XYZ")
    eq(P("[if:a=1]X[if:b=2]Y[/if]Z[/if]", {a=1, b=9}), "XZ")
end)

test("nest: [else] on outer with nested inner", function()
    eq(P("[if:a=1][if:b=2]bb[/if][else]A-else[/if]", {a=1, b=2}), "bb")
    eq(P("[if:a=1][if:b=2]bb[/if][else]A-else[/if]", {a=1, b=9}), "")
    eq(P("[if:a=1][if:b=2]bb[/if][else]A-else[/if]", {a=9, b=2}), "A-else")
end)

test("nest: [else] on inner", function()
    eq(P("[if:a=1][if:b=2]bb[else]b-else[/if][/if]", {a=1, b=2}), "bb")
    eq(P("[if:a=1][if:b=2]bb[else]b-else[/if][/if]", {a=1, b=9}), "b-else")
    eq(P("[if:a=1][if:b=2]bb[else]b-else[/if][/if]", {a=9, b=2}), "")
end)

test("nest: [else] on both inner and outer", function()
    eq(P("[if:a=1][if:b=2]bb[else]b-else[/if][else]A-else[/if]", {a=9, b=2}), "A-else")
    eq(P("[if:a=1][if:b=2]bb[else]b-else[/if][else]A-else[/if]", {a=1, b=9}), "b-else")
end)

-- Operators inside processConditionals (end-to-end)
test("ops: AND in predicate", function()
    eq(P("[if:a=1 and b=2]X[/if]", {a=1, b=2}), "X")
    eq(P("[if:a=1 and b=2]X[/if]", {a=1, b=9}), "")
end)

test("ops: OR in predicate", function()
    eq(P("[if:day=Sat or day=Sun]WE[/if]", {day="Sat"}), "WE")
    eq(P("[if:day=Sat or day=Sun]WE[/if]", {day="Mon"}), "")
end)

test("ops: NOT in predicate", function()
    eq(P("[if:not charging=yes]batt[/if]", {charging="no"}), "batt")
    eq(P("[if:not charging=yes]batt[/if]", {charging="yes"}), "")
end)

test("ops: grouping with parens", function()
    eq(P("[if:(a=1 or b=2) and c=3]X[/if]", {a=1, b=9, c=3}), "X")
    eq(P("[if:(a=1 or b=2) and c=3]X[/if]", {a=9, b=9, c=3}), "")
end)

-- Edge cases
test("edge: unbalanced opener passes through", function()
    eq(P("[if:a=1]foo", {a=1}), "[if:a=1]foo")
end)

test("edge: orphan closer passes through", function()
    eq(P("foo[/if]bar", {}), "foo[/if]bar")
end)

test("edge: empty predicate evaluates to false", function()
    eq(P("[if:]X[else]Y[/if]", {}), "Y")
end)
```

- [ ] **Step 2: Run the suite to confirm the nesting tests fail**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin && lua _test_conditionals.lua
```

Expected: baseline + evaluator tests pass (25). Most nesting tests fail — the current gsub parser mangles nested blocks as expected. Operator-via-processConditionals tests also fail (current parser calls `evaluateCondition`, not `evaluateExpression`).

- [ ] **Step 3: Rewrite `processConditionals` in `bookends_tokens.lua`**

Find the existing function (starts at line 105 with the comment `--- Process [if:condition]...[/if] blocks...`):

```lua
--- Process [if:condition]...[/if] blocks in a format string.
local function processConditionals(format_str, state)
    return format_str:gsub("%[if:([^%]]+)%](.-)%[/if%]", function(cond, body)
        local if_part, else_part = body:match("^(.-)%[else%](.*)$")
        if not if_part then
            if_part = body
            else_part = ""
        end
        if evaluateCondition(cond, state) then
            return if_part
        else
            return else_part
        end
    end)
end
```

Replace it with:

```lua
--- Process [if:condition]...[/if] blocks, supporting nesting and boolean
-- operators in predicates. Peels the innermost block each iteration:
--   1. Find the first [/if]
--   2. Find the last [if:...] that appears before it
--   3. That pair is the innermost block (no nested [if:] can sit between them)
--   4. Evaluate its predicate, substitute the chosen branch, repeat
-- Unbalanced tags are left in place (no [/if] → break; orphan closer → break).
local function processConditionals(format_str, state)
    local result = format_str
    while true do
        local close_s, close_e = result:find("%[/if%]", 1, false)
        if not close_s then break end

        -- Scan forward for all [if:...] openers that start before close_s,
        -- keeping the last one — that's the innermost opener for this closer.
        local open_s, open_e, cond
        local search_from = 1
        while true do
            local s, e, c = result:find("%[if:([^%]]-)%]", search_from, false)
            if not s or s >= close_s then break end
            open_s, open_e, cond = s, e, c
            search_from = s + 1
        end
        if not open_s then break end  -- orphan [/if], leave string as-is

        local body = result:sub(open_e + 1, close_s - 1)
        local if_part, else_part = body:match("^(.-)%[else%](.*)$")
        if not if_part then
            if_part = body
            else_part = ""
        end
        local chosen = evaluateExpression(cond, state) and if_part or else_part
        result = result:sub(1, open_s - 1) .. chosen .. result:sub(close_e + 1)
    end
    return result
end
```

- [ ] **Step 4: Verify syntax and run the full suite**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
luac -p bookends_tokens.lua && echo "syntax OK"
lua _test_conditionals.lua
```

Expected: **all tests pass**. Total around **41 passed, 0 failed**. If any baseline (Task 3) tests regress, the rewrite broke backward compatibility — stop and investigate before continuing.

- [ ] **Step 5: Commit**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
git add bookends_tokens.lua _test_conditionals.lua
git commit -m "feat(tokens): nested [if:] blocks + and/or/not in predicates"
```

---

## Task 6: Rename predicates — percent, chapter, pages

**Goal:** Rename `state.percent` → `state.book_pct`, existing `state.chapter` (% through chapter) → `state.chapter_pct`, `state.pages` → `state.session_pages`. These are the cleanup renames before adding the new `chapter` and `chapters` predicates that would collide with the old name.

**Files:**
- Modify: `bookends_tokens.lua:124–228` (inside `buildConditionState`)
- Modify: `_test_conditionals.lua` (add rename tests)

- [ ] **Step 1: Rename `state.percent` → `state.book_pct`**

In `bookends_tokens.lua`, find the block inside `buildConditionState` (around lines 157–171) that starts:
```lua
        -- Book percent
        if doc:hasHiddenFlows() then
            local flow = doc:getPageFlow(pageno)
            local flow_page = doc:getPageNumberInFlow(pageno)
            local flow_total = doc:getTotalPagesInFlow(flow)
            if flow_total and flow_total > 0 then
                state.percent = math.floor(flow_page / flow_total * 100 + 0.5)
            end
        else
            local raw_total = doc:getPageCount()
            if raw_total and raw_total > 0 then
                state.percent = math.floor(pageno / raw_total * 100 + 0.5)
            end
        end
```

Replace both `state.percent` with `state.book_pct`.

- [ ] **Step 2: Rename `state.chapter` → `state.chapter_pct`**

In the same function, find the Chapter percent block (around lines 173–189):
```lua
        -- Chapter percent
        if ui.toc then
            local chapter_start = ui.toc:getPreviousChapter(pageno)
            if ui.toc:isChapterStart(pageno) then
                chapter_start = pageno
            end
            if chapter_start then
                local next_chapter = ui.toc:getNextChapter(pageno)
                local chapter_end = next_chapter or (doc:getPageCount() + 1)
                local total = chapter_end - chapter_start
                if total > 1 then
                    state.chapter = math.floor((pageno - chapter_start) / (total - 1) * 100)
                elseif total > 0 then
                    state.chapter = 100
                end
            end
        end
```

Replace both `state.chapter` with `state.chapter_pct`.

- [ ] **Step 3: Rename `state.pages` → `state.session_pages`**

Find (around line 211):
```lua
    state.pages = math.max(0, session_pages_read or 0)
```

Replace with:
```lua
    state.session_pages = math.max(0, session_pages_read or 0)
```

- [ ] **Step 4: Update the `state.speed` heuristic**

`state.speed` at line 214 reads `session_pages_read` directly from the argument — no `state.pages` dependency — so no change needed. Verify by re-reading the speed block:

```lua
    -- Reading speed (pages/hr)
    if session_elapsed and session_elapsed > 60 and (session_pages_read or 0) > 0 then
        state.speed = math.floor(session_pages_read / session_elapsed * 3600)
    elseif ui.statistics and ui.statistics.avg_time then
```

No edit required. Proceed.

- [ ] **Step 5: Add rename regression tests to `_test_conditionals.lua`**

Append:

```lua

-- ----------------------------------------------------------------------------
-- Predicate renames — percent → book_pct, chapter → chapter_pct,
-- pages → session_pages. Tests exercise the state-table lookup via
-- processConditionals directly; buildConditionState runtime sourcing is
-- verified on-device (requires ui/doc).
-- ----------------------------------------------------------------------------

test("rename: book_pct is the new name for book percent", function()
    eq(P("[if:book_pct>50]past half[/if]", {book_pct=75}), "past half")
    eq(P("[if:book_pct>50]past half[/if]", {book_pct=25}), "")
end)

test("rename: chapter_pct is the new name for chapter percent", function()
    eq(P("[if:chapter_pct>50]x[/if]", {chapter_pct=75}), "x")
end)

test("rename: session_pages is the new name for session pages read", function()
    eq(P("[if:session_pages>10]many[/if]", {session_pages=25}), "many")
    eq(P("[if:session_pages>10]many[/if]", {session_pages=5}), "")
end)

test("rename: old names (percent, pages) no longer recognised → false", function()
    -- These state keys wouldn't be set by the new buildConditionState, but a
    -- user's old preset might still reference them. Unknown key → false.
    eq(P("[if:percent>50]x[/if]", { percent = 75 }), "x") -- still works if someone manually supplies state (no-op rename test)
    eq(P("[if:percent>50]x[/if]", {}), "")                -- unknown key, falsy
end)
```

- [ ] **Step 6: Run the suite**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
luac -p bookends_tokens.lua && echo "syntax OK"
lua _test_conditionals.lua
```

Expected: all tests still pass. The renames don't affect the parser; they only affect how `buildConditionState` populates keys, which is not exercised by the test harness.

- [ ] **Step 7: Commit**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
git add bookends_tokens.lua _test_conditionals.lua
git commit -m "refactor(tokens): rename ambiguous predicates

- percent → book_pct
- chapter (% through chapter) → chapter_pct
- pages → session_pages

Frees up 'chapter' for the upcoming current-chapter-number predicate."
```

---

## Task 7: Extract `Tokens.getChapterTitlesByDepth` helper

**Goal:** The TOC-walk code that derives `chapter_title`, `chapter_titles_by_depth`, `chapter_num`, and `chapter_count` currently lives inline in `Tokens.expand` (around lines 436–499). Factor it into a reusable `Tokens.getChapterTitlesByDepth(ui, pageno)` so `buildConditionState` (later tasks) can call the same code — preventing the predicate values from ever drifting from the rendered token values.

**Files:**
- Modify: `bookends_tokens.lua` (add new `Tokens.getChapterTitlesByDepth` function near the top, refactor `Tokens.expand` to call it)

- [ ] **Step 1: Add the helper function**

In `bookends_tokens.lua`, find `Tokens.computeTickFractions` (starts at line 44). Immediately **after** its closing `end` and before the next `local function parseNumericValue`, insert:

```lua

--- Walk the TOC once and return a table of chapter-title data derived from it.
-- @param ui     KOReader ReaderUI instance (must have .toc)
-- @param pageno current page number (1-indexed)
-- @return table with keys:
--   chapter_title       — deepest (most-specific) chapter title covering the page
--   chapter_titles_by_depth — { [1]="Part II", [2]="Ch 3", ... }
--   chapter_num         — 1-indexed flat position of the current entry
--   chapter_count       — total TOC entries across all depths
-- Returns an empty-ish table if ui.toc or page data is unavailable.
function Tokens.getChapterTitlesByDepth(ui, pageno)
    local out = {
        chapter_title = "",
        chapter_titles_by_depth = {},
        chapter_num = 0,
        chapter_count = 0,
    }
    if not ui or not ui.toc or not pageno then return out end

    local title = ui.toc:getTocTitleByPage(pageno)
    if title and title ~= "" then out.chapter_title = title end

    local full_toc = ui.toc.toc
    if not full_toc then return out end

    out.chapter_count = #full_toc
    local idx = 0
    for i, entry in ipairs(full_toc) do
        if entry.page and entry.page <= pageno then
            idx = i
        else
            break
        end
    end
    if idx > 0 then out.chapter_num = idx end

    for _, entry in ipairs(full_toc) do
        if entry.page and entry.page <= pageno and entry.depth then
            out.chapter_titles_by_depth[entry.depth] = entry.title or ""
        end
    end
    return out
end
```

- [ ] **Step 2: Refactor `Tokens.expand` to use the helper**

In `Tokens.expand`, find the block around lines 436–499 that begins:

```lua
    if needs("P", "g", "G", "l", "C", "j", "J") and pageno and ui.toc then
        -- Raw page calculation for %P (percentage)
        local chapter_start = ui.toc:getPreviousChapter(pageno)
```

Keep the `%P` (chapter-percent) block and the stable-page-counts block unchanged, but replace the title / chapter-number / depth walk (lines 466–499) with a call to the helper.

**Before** (lines 466–499 approximately — everything from `local title = ui.toc:getTocTitleByPage(pageno)` through the closing `end` of the outer `if needs(...)` block):

```lua
        local title = ui.toc:getTocTitleByPage(pageno)
        if title and title ~= "" then chapter_title = title end

        -- Chapter number / total count, from the flat TOC.
        -- "Chapter number" = the 1-indexed position of the deepest entry that
        -- covers the current page. A book with nested Parts/Chapters/Sections
        -- counts every entry, so the number reflects flat reading order rather
        -- than the structural "Chapter N" in the book's own numbering — an
        -- approximation that works well for most e-books without TOC hierarchy.
        local full_toc = ui.toc.toc
        if full_toc then
            chapter_count = #full_toc
            local idx = 0
            for i, entry in ipairs(full_toc) do
                if entry.page and entry.page <= pageno then
                    idx = i
                else
                    break
                end
            end
            if idx > 0 then chapter_num = idx end
        end
        -- Depth-specific chapter titles for %C1, %C2, etc.
        -- getTocTitleByPage above ensures the TOC is populated.
        if format_str:find("%%C%d") then
            local full_toc = ui.toc.toc
            if full_toc then
                for _, entry in ipairs(full_toc) do
                    if entry.page and entry.page <= pageno and entry.depth then
                        chapter_titles_by_depth[entry.depth] = entry.title or ""
                    end
                end
            end
        end
    end
```

**After**:

```lua
        local titles = Tokens.getChapterTitlesByDepth(ui, pageno)
        if titles.chapter_title ~= "" then chapter_title = titles.chapter_title end
        chapter_titles_by_depth = titles.chapter_titles_by_depth
        if titles.chapter_num > 0  then chapter_num   = titles.chapter_num   end
        if titles.chapter_count > 0 then chapter_count = titles.chapter_count end
    end
```

(Note: the `if format_str:find("%%C%d") then` guard that only walked the TOC for depth tables when needed is dropped — the helper always populates them. Net cost is one extra pass over `full_toc` per paint (tens of entries, nanoseconds) — not measurable.)

- [ ] **Step 3: Verify syntax and run the suite**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
luac -p bookends_tokens.lua && echo "syntax OK"
lua _test_conditionals.lua
```

Expected: all tests still pass. This task is a refactor — it shouldn't change observable behaviour.

- [ ] **Step 4: Commit**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
git add bookends_tokens.lua
git commit -m "refactor(tokens): extract getChapterTitlesByDepth helper

Shared source of truth for %C/%C1..3/%j/%J tokens and the upcoming
chapter* conditional predicates."
```

---

## Task 8: Add `chapter` and `chapters` numeric predicates

**Goal:** Wire the new current-chapter-number and total-chapter-count predicates into `buildConditionState` using the helper factored out in Task 7.

**Files:**
- Modify: `bookends_tokens.lua` (inside `buildConditionState`)
- Modify: `_test_conditionals.lua` (add tests)

- [ ] **Step 1: Populate `state.chapter` and `state.chapters` in `buildConditionState`**

In `bookends_tokens.lua`, find the Chapter percent block in `buildConditionState` (where `state.chapter_pct` now lives, around lines 173–189). Immediately **after** the closing `end` of that `if ui.toc then` block (but still inside the `if pageno and doc then` outer block), insert:

```lua

        -- Chapter number / total count — same source as %j / %J tokens.
        local titles = Tokens.getChapterTitlesByDepth(ui, pageno)
        if titles.chapter_num  > 0 then state.chapter  = titles.chapter_num  end
        if titles.chapter_count > 0 then state.chapters = titles.chapter_count end
```

- [ ] **Step 2: Write tests**

Append to `_test_conditionals.lua`:

```lua

-- ----------------------------------------------------------------------------
-- New numeric predicates: chapter, chapters.
-- ----------------------------------------------------------------------------

test("new: chapters>20 true", function()
    eq(P("[if:chapters>20]long[/if]", {chapters=25}), "long")
end)

test("new: chapters>20 false", function()
    eq(P("[if:chapters>20]long[/if]", {chapters=15}), "")
end)

test("new: chapter=1 (first chapter)", function()
    eq(P("[if:chapter=1]intro[/if]", {chapter=1}), "intro")
    eq(P("[if:chapter=1]intro[/if]", {chapter=2}), "")
end)

test("new: combined chapter + chapters", function()
    eq(P("[if:chapter=1 and chapters>20]long intro[/if]", {chapter=1, chapters=25}), "long intro")
end)
```

- [ ] **Step 3: Verify syntax and run the suite**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
luac -p bookends_tokens.lua && echo "syntax OK"
lua _test_conditionals.lua
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
git add bookends_tokens.lua _test_conditionals.lua
git commit -m "feat(tokens): chapter and chapters conditional predicates

Closes #23."
```

---

## Task 9: Add string predicates (title / author / series / chapter_title*)

**Goal:** Populate `state.title`, `state.author`, `state.series`, `state.chapter_title`, `state.chapter_title_1..3` in `buildConditionState`, mirroring what `%T`/`%A`/`%S`/`%C`/`%C1..3` resolve to in `Tokens.expand`. Enables empty-check conditionals like `[if:chapter_title_2]%C2[else]%C1[/if]`.

**Files:**
- Modify: `bookends_tokens.lua` (inside `buildConditionState`)
- Modify: `_test_conditionals.lua` (add tests)

- [ ] **Step 1: Extract book-metadata fields in `buildConditionState`**

In `bookends_tokens.lua`, find the Document format block near the end of `buildConditionState` (around line 196–199):

```lua
    -- Document format
    local doc = ui.document
    if doc and doc.file then
        state.format = (doc.file:match("%.([^.]+)$") or ""):upper()
    end
```

Immediately **after** this block, insert the following. It mirrors the `%T`/`%A`/`%S` derivation in `Tokens.expand` lines 629–648 verbatim so the predicate values match the rendered tokens exactly:

```lua

    -- Book metadata (mirrors %T / %A / %S derivation in Tokens.expand)
    if doc then
        local doc_props = ui.doc_props or {}
        local ok, props = pcall(doc.getProps, doc)
        if not ok then props = {} end
        state.title  = doc_props.display_title or props.title   or ""
        state.author = doc_props.authors       or props.authors or ""
        local series = doc_props.series        or props.series  or ""
        local series_index = doc_props.series_index or props.series_index
        if series ~= "" and series_index then
            series = series .. " #" .. series_index
        end
        state.series = series
    end

    -- Chapter titles (reuses the helper already called for state.chapter/chapters)
    if pageno and ui.toc then
        local titles = Tokens.getChapterTitlesByDepth(ui, pageno)
        state.chapter_title   = titles.chapter_title or ""
        state.chapter_title_1 = titles.chapter_titles_by_depth[1] or ""
        state.chapter_title_2 = titles.chapter_titles_by_depth[2] or ""
        state.chapter_title_3 = titles.chapter_titles_by_depth[3] or ""
    end
```

Note: the helper is called twice within `buildConditionState` (once for `chapter`/`chapters` in Task 8, once here). That's two TOC walks per paint, each over tens of entries — trivial. A small optimisation is possible (compute once, share) but the speed_cost is negligible and duplicating one line of call is clearer than introducing a local. Leave as-is.

- [ ] **Step 2: Write tests**

Append to `_test_conditionals.lua`:

```lua

-- ----------------------------------------------------------------------------
-- New string predicates: title, author, series, chapter_title, chapter_title_1..3
-- ----------------------------------------------------------------------------

test("string: chapter_title_2 empty falls to else", function()
    eq(P("[if:chapter_title_2]%C2[else]%C1[/if]", {chapter_title_2=""}), "%C1")
end)

test("string: chapter_title_2 present takes if", function()
    eq(P("[if:chapter_title_2]%C2[else]%C1[/if]", {chapter_title_2="Subchapter A"}), "%C2")
end)

test("string: not series → standalone", function()
    eq(P("[if:not series]solo[else]%S[/if]", {series=""}),       "solo")
    eq(P("[if:not series]solo[else]%S[/if]", {series="Foo #2"}), "%S")
end)

test("string: author = Anonymous", function()
    eq(P("[if:author=Anonymous]?[/if]", {author="Anonymous"}), "?")
    eq(P("[if:author=Anonymous]?[/if]", {author="Ursula K. Le Guin"}), "")
end)

test("string: combined with operators", function()
    eq(
        P("[if:series and not chapter_title_2]%S · %C1[/if]",
          {series="Foo #2", chapter_title_2=""}),
        "%S · %C1"
    )
    eq(
        P("[if:series and not chapter_title_2]%S · %C1[/if]",
          {series="Foo #2", chapter_title_2="Sub"}),
        ""
    )
end)
```

- [ ] **Step 3: Verify syntax and run the suite**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
luac -p bookends_tokens.lua && echo "syntax OK"
lua _test_conditionals.lua
```

Expected: all tests pass. Final count should be around **57 passed, 0 failed**.

- [ ] **Step 4: Commit**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
git add bookends_tokens.lua _test_conditionals.lua
git commit -m "feat(tokens): string predicates for emptiness/equality checks

Adds title, author, series, chapter_title, chapter_title_1..3 to the
conditional state table. Sourced from the same derivation as the
corresponding %T/%A/%S/%C/%C1..3 tokens so predicate and token can't drift.

Enables [if:chapter_title_2]%C2[else]%C1[/if] and similar patterns."
```

---

## Task 9a: Update token picker (`menu/token_picker.lua`)

**Goal:** The token picker's **Conditional** sub-menu exposes user-facing examples and a reference list of predicate names. Those strings lock in the pre-rename names (`percent`, `chapter`, `pages`) and don't yet advertise the new operators, nesting, or new predicates. Update in-place; this task covers the English source strings. Task 9b then re-translates.

**Files:**
- Modify: `menu/token_picker.lua` (Conditional catalog at approximately lines 79–111, plus the Operators label at line 163)

- [ ] **Step 1: Update the Examples section**

Current Examples block (lines 80–93):

```lua
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
```

Replace with:

```lua
    { _("Examples"), {
        { "[if:wifi=on]%W[/if]", _("Show wifi icon when connected") },
        { "[if:batt<20]LOW %b[/if]", _("Warning when battery below 20%") },
        { "[if:charging=yes]\xE2\x9A\xA1[/if] %b", _("Bolt icon when charging") },
        { "[if:invert=yes]\xE2\x87\x84[/if]", _("Arrows when page-turn direction is flipped") },
        { "[if:speed>0]%r pg/hr[/if]", _("Speed, hidden until calculated") },
        { "[if:session>0]%R[/if]", _("Session time, hidden at start") },
        { "[if:page=odd]%c[else]%c[/if]", _("Different content on odd/even pages") },
        { "[if:book_pct>90]Almost done![/if]", _("Message near end of book") },
        { "[if:light=off]Light off[else]Light on[/if]", _("Frontlight status") },
        { "[if:format=PDF]%c / %t[/if]", _("Only show for PDF documents") },
        { "[if:time>22:00]Late night reading![/if]", _("After 10pm") },
        { "[if:day=Sat or day=Sun]Weekend![/if]", _("Weekend days (OR operator)") },
        { "[if:time>=18:00 and time<18:30]6\xE2\x80\x936:30[/if]", _("Half-hour window (AND operator)") },
        { "[if:not series]Standalone[/if]", _("Books not in a series") },
        { "[if:chapter_title_2]%C2[else]%C1[/if]", _("Sub-chapter title when present") },
        { "[if:chapters>20]Long read[/if]", _("Books with many chapters") },
    }},
```

One existing rename (`percent` → `book_pct`), the `[if:day=Sat]…[else]%a[/if]` line becomes an OR example, plus four new examples exercising `and`, `or`, `not`, string-emptiness, and `chapters`.

- [ ] **Step 2: Update the Reference section**

Current Reference block (lines 94–110):

```lua
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
```

Replace with:

```lua
    { _("Reference"), {
        { "[if:wifi=on]...[/if]", _("wifi — on / off") },
        { "[if:connected=yes]...[/if]", _("connected — yes / no") },
        { "[if:batt<50]...[/if]", _("batt — 0 to 100") },
        { "[if:charging=yes]...[/if]", _("charging — yes / no") },
        { "[if:invert=yes]...[/if]", _("invert — yes / no (page-turn direction)") },
        { "[if:book_pct>50]...[/if]", _("book_pct — 0 to 100 (book progress)") },
        { "[if:chapter_pct>50]...[/if]", _("chapter_pct — 0 to 100 (chapter progress)") },
        { "[if:chapter=1]...[/if]", _("chapter — current chapter number") },
        { "[if:chapters>20]...[/if]", _("chapters — total chapter count") },
        { "[if:speed>0]...[/if]", _("speed — pages per hour") },
        { "[if:session>30]...[/if]", _("session — minutes reading") },
        { "[if:session_pages>0]...[/if]", _("session_pages — pages read this session") },
        { "[if:page=odd]...[/if]", _("page — odd / even") },
        { "[if:light=on]...[/if]", _("light — on / off") },
        { "[if:format=EPUB]...[/if]", _("format — EPUB / PDF / CBZ etc.") },
        { "[if:time>18:00]...[/if]", _("time — use HH:MM (24h)") },
        { "[if:day=Mon]...[/if]", _("day — Mon Tue Wed Thu Fri Sat Sun") },
        { "[if:title]...[/if]", _("title — book title (empty string is falsy)") },
        { "[if:author]...[/if]", _("author — author name") },
        { "[if:series]...[/if]", _("series — series + index, empty when standalone") },
        { "[if:chapter_title]...[/if]", _("chapter_title — current chapter title") },
        { "[if:chapter_title_2]...[/if]", _("chapter_title_1/2/3 — title at depth 1/2/3") },
    }},
```

Three renames (`percent` → `book_pct`, `chapter` → `chapter_pct`, `pages` → `session_pages`). Nine new rows (`chapter`, `chapters`, `title`, `author`, `series`, `chapter_title`, `chapter_title_2`, plus the two existing renamed-description entries).

- [ ] **Step 3: Update the Operators hint label**

Current (line 163):
```lua
                { text = _("Operators:  =  <  >"), dim = true, callback = dim },
```

Replace with:
```lua
                { text = _("Compare:  =  <  >     Boolean:  and  or  not  ( )"), dim = true, callback = dim },
```

- [ ] **Step 4: Syntax check**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin && luac -p menu/token_picker.lua && echo "syntax OK"
```

Expected: `syntax OK`.

- [ ] **Step 5: Commit**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
git add menu/token_picker.lua
git commit -m "feat(picker): conditional examples/reference for new predicates

Renames percent/chapter/pages to their new names, adds reference rows
for chapter, chapters, title, author, series, chapter_title(_2),
new examples for and/or/not and string-emptiness, and expands the
Operators hint to mention boolean operators and parens."
```

---

## Task 9b: Refresh translations

**Goal:** Task 9a added new English source strings in `menu/token_picker.lua` and renamed three existing ones. Every `.po` file in `locale/` needs to pick up the new strings, drop or update the renamed ones, and have translations provided where feasible.

**Files:**
- Modify: `locale/bookends.pot` — regenerate from source
- Modify: `locale/de.po`, `locale/en_GB.po`, `locale/es.po`, `locale/fr.po`, `locale/it.po`, `locale/pt_BR.po`

### What strings changed

**Removed** (old names no longer appear in source):
- `"percent — 0 to 100 (book)"`
- `"chapter — 0 to 100 (chapter)"`
- `"pages — session pages read"`
- `"Operators:  =  <  >"`

**New strings** added (need translation in every non-English `.po`):
- `"Weekend days (OR operator)"`
- `"Half-hour window (AND operator)"`
- `"Books not in a series"`
- `"Sub-chapter title when present"`
- `"Books with many chapters"`
- `"book_pct — 0 to 100 (book progress)"`
- `"chapter_pct — 0 to 100 (chapter progress)"`
- `"chapter — current chapter number"`
- `"chapters — total chapter count"`
- `"session_pages — pages read this session"`
- `"title — book title (empty string is falsy)"`
- `"author — author name"`
- `"series — series + index, empty when standalone"`
- `"chapter_title — current chapter title"`
- `"chapter_title_1/2/3 — title at depth 1/2/3"`
- `"Compare:  =  <  >     Boolean:  and  or  not  ( )"`

- [ ] **Step 1: Regenerate `locale/bookends.pot`**

The project already has a `.pot` file (last regenerated today per its `POT-Creation-Date`). Regenerate by hand if no automated tooling exists; otherwise use whatever command the previous translation commit (e.g., `965da46 feat: install-from-gallery collision warning + en masse translation refresh`) used.

Manual regeneration: extract every unique string inside `_(...)` from all `.lua` files under the repo root and under `menu/`, sort alphabetically, write as `msgid "..."\nmsgstr ""` pairs to `locale/bookends.pot`. Preserve the existing header block.

If you're unsure about the tooling, **inspect `git show 965da46 -- locale/` and/or `git log --oneline --follow locale/bookends.pot`** to see what the pattern was last time.

- [ ] **Step 2: Update each `.po` file — parallel dispatch**

Dispatch five subagents concurrently (one per target language, except `en_GB` which is near-identical to English):

- `locale/de.po` (German)
- `locale/es.po` (Spanish)
- `locale/fr.po` (French)
- `locale/it.po` (Italian)
- `locale/pt_BR.po` (Brazilian Portuguese)

Each subagent should:
1. Read the updated `bookends.pot` for the current English strings.
2. Read the existing `.po` to understand house style (terse vs verbose, punctuation, capitalisation conventions).
3. For each **new** `msgid`, add a `msgstr` with the translation.
4. For each **removed** old string (`percent — 0 to 100 (book)` etc.), drop its entry from the `.po` if present.
5. Preserve unrelated existing translations exactly.
6. Keep header metadata intact.
7. Commit with message `chore(i18n): refresh <lang> translations for new conditional predicates`.

For `en_GB.po`, most strings are identical to the source — add the new strings as `msgstr "same text"` unless there's a British-English variant worth applying (unlikely here; the new strings have no US/GB-sensitive vocabulary).

- [ ] **Step 3: Verify all `.po` files are valid**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
for f in locale/*.po locale/*.pot; do
  # Basic sanity: balanced quotes, msgid/msgstr pairs
  msgfmt --check-format -c -v -o /dev/null "$f" 2>&1 | tail -3
done
```

Expected: each file reports a summary like `N translated messages, M untranslated messages` with no errors.

(If `msgfmt` isn't installed, skip and rely on the next task's on-device smoke test to catch obvious breakage.)

- [ ] **Step 4: Commit `.pot` and any files not already committed in Step 2**

```bash
cd /home/andyhazz/projects/bookends.koplugin
git add locale/
git commit -m "chore(i18n): refresh .pot for new conditional strings"
```
(Only if there are uncommitted changes remaining — the per-language subagents in Step 2 may have already committed each `.po` individually.)

---

## Task 10: Update README

**Files:**
- Modify: `README.md` — three edits: rename in example block, extend operators sentence, replace predicate table.

The conditionals section in README.md lives at lines 160–198 inside a `<details>` block. Confirm by reading:

```bash
sed -n '160,198p' /home/andyhazz/projects/bookends.koplugin/README.md
```

- [ ] **Step 1: Rename the `percent` example**

Replace this exact block (currently at lines 165–175):

```
[if:wifi=on]📶[/if]
[if:batt<20]LOW %b[/if]
[if:charging=yes]⚡[/if] %b
[if:page=odd]%T[else]%C[/if]
[if:percent>90]Almost done![/if]
[if:time>22:00]Late night reading![/if]
[if:day=Sat]Weekend![else]%a[/if]
[if:speed>0]%r pg/hr[/if]
[if:format=PDF]%c / %t[/if]
```

With:

```
[if:wifi=on]📶[/if]
[if:batt<20]LOW %b[/if]
[if:charging=yes]⚡[/if] %b
[if:page=odd]%T[else]%C[/if]
[if:book_pct>90]Almost done![/if]
[if:time>22:00]Late night reading![/if]
[if:day=Sat]Weekend![else]%a[/if]
[if:chapter_title_2]%C2[else]%C1[/if]
[if:not series]Standalone[/if]
[if:day=Sat or day=Sun]Weekend[/if]
[if:format=PDF]%c / %t[/if]
```

The rename fixes `percent` → `book_pct`, and three new lines demonstrate string predicates, `or`, and `not`.

- [ ] **Step 2: Extend the operators sentence**

Replace line 177 (currently: `Operators: = (equals), < (less than), > (greater than).`) with:

```markdown
Comparison operators: `=` (equals), `<` (less than), `>` (greater than). Boolean operators: `and`, `or`, `not`, with parens `()` for grouping. Conditionals can be nested to any depth — `[if:A][if:B]…[/if][/if]` — and compose with `[else]`.
```

- [ ] **Step 3: Replace the predicate table**

Replace this exact table (currently at lines 179–194):

```markdown
| Condition | Values | Description |
|-----------|--------|-------------|
| `wifi` | on / off | Wi-Fi radio state |
| `connected` | yes / no | Network connection state |
| `batt` | 0–100 | Battery percentage |
| `charging` | yes / no | Charging or charged |
| `percent` | 0–100 | Book progress percentage |
| `chapter` | 0–100 | Chapter progress percentage |
| `speed` | pages/hr | Reading speed |
| `session` | minutes | Session reading time |
| `pages` | count | Session pages read |
| `page` | odd / even | Current page parity |
| `light` | on / off | Frontlight state |
| `format` | EPUB / PDF / CBZ… | Document format |
| `time` | HH:MM (24h) | Time of day |
| `day` | Mon–Sun | Day of week |
```

With:

```markdown
| Condition | Values | Description |
|-----------|--------|-------------|
| `wifi` | on / off | Wi-Fi radio state |
| `connected` | yes / no | Network connection state |
| `batt` | 0–100 | Battery percentage |
| `charging` | yes / no | Charging or charged |
| `book_pct` | 0–100 | Book progress percentage (matches `%p`) |
| `chapter_pct` | 0–100 | Chapter progress percentage (matches `%P`) |
| `chapter` | 1–N | Current chapter number (matches `%j`) |
| `chapters` | count | Total chapter count (matches `%J`) |
| `speed` | pages/hr | Reading speed |
| `session` | minutes | Session reading time |
| `session_pages` | count | Session pages read |
| `page` | odd / even | Current page parity |
| `light` | on / off | Frontlight state |
| `format` | EPUB / PDF / CBZ… | Document format |
| `time` | HH:MM (24h) | Time of day |
| `day` | Mon–Sun | Day of week |
| `invert` | yes / no | Page-turn direction flipped |
| `title` | string | Book title (matches `%T`) — test with `[if:not title]` or `[if:title=…]` |
| `author` | string | Author (matches `%A`) |
| `series` | string | Series, e.g. `"Foo #2"` (matches `%S`) — empty when not in a series |
| `chapter_title` | string | Current chapter title (matches `%C`) |
| `chapter_title_1` | string | Chapter title at depth 1 (matches `%C1`) |
| `chapter_title_2` | string | Chapter title at depth 2 (matches `%C2`) |
| `chapter_title_3` | string | Chapter title at depth 3 (matches `%C3`) |
```

(String predicates evaluate as falsy when the string is empty, so `[if:not series]` means "book isn't in a series" and `[if:chapter_title_2]` means "we're in a sub-chapter at depth 2".)

- [ ] **Step 4: Verify**

Run:
```bash
grep -nE "\[if:percent|\[if:chapter>|\[if:pages|book_pct|chapter_pct|session_pages|chapter_title" /home/andyhazz/projects/bookends.koplugin/README.md
```

Expected: no matches for `[if:percent`, `[if:chapter>`, or `[if:pages` (the old names are gone). Multiple matches for `book_pct`, `chapter_pct`, `session_pages`, and `chapter_title*` (the new content).

- [ ] **Step 5: Commit**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
git add README.md
git commit -m "docs(readme): conditional operators, nesting, new predicates

Documents and/or/not/parens and nesting, the chapter/chapters/title/
author/series/chapter_title(_1..3) predicates, and renames the
percent/chapter(pct)/pages examples to their new names."
```

---

## Task 11: Draft release-notes snippet

**Files:**
- Create: `docs/release-notes-4.1.0.md`

This file is a draft for the GitHub release description — the plugin has no `CHANGELOG.md` convention, so release notes live in GitHub releases. This doc is source material to copy-paste when cutting the release.

- [ ] **Step 1: Create the release-notes draft**

Create `/home/andyhazz/projects/bookends.koplugin/docs/release-notes-4.1.0.md`:

```markdown
# Bookends 4.1.0 — release notes (draft)

## Breaking: conditional predicate renames

Three conditional predicates have been renamed for clarity. Update any preset that used the old names.

| Old                        | New                          |
|----------------------------|------------------------------|
| `[if:percent>N]`           | `[if:book_pct>N]`            |
| `[if:chapter>N]`           | `[if:chapter_pct>N]`         |
| `[if:pages>N]`             | `[if:session_pages>N]`       |

The name `chapter` now means the **current chapter number** (matching the `%j` token), and a new `chapters` predicate exposes the total chapter count (matching `%J`). If you had a preset around `[if:chapter>50]` meaning "more than halfway through current chapter", that expression now compares *chapter number* to 50 and will silently render differently. Update it to `[if:chapter_pct>50]`.

None of the presets in the community gallery use these old names, so gallery presets are unaffected.

## New: nested conditionals

`[if:...][if:...]...[/if][/if]` now works to any depth and composes with `[else]` on either level.

```
[if:time<18:30][if:time>=18:00]between 6 and 6:30[/if][/if]
```

## New: boolean operators and grouping

`and`, `or`, `not` are now supported inside conditional predicates, with parens for grouping. Standard precedence (`not` binds tightest, `or` loosest).

```
[if:time>=18:00 and time<18:30]6–6:30[/if]
[if:day=Sat or day=Sun]weekend[/if]
[if:not charging=yes]battery[/if]
[if:(day=Sat or day=Sun) and batt<50]low on a weekend[/if]
```

## New: chapter number / count predicates

Requested in issue #23.

```
[if:chapters>20]Long read[/if]
[if:chapter=1]Foreword[/if]
```

## New: text-field emptiness and equality predicates

Book-metadata and chapter-title strings are now testable in conditionals. Empty strings are falsy, so a bare-key truthy check is the idiomatic emptiness test.

```
[if:chapter_title_2]%C2[else]%C1[/if]    — show sub-chapter title if present, parent otherwise
[if:not series]Standalone[/if]           — books not in a series
[if:author=Anonymous]?[/if]              — string equality
```

Predicates added: `title`, `author`, `series`, `chapter_title`, `chapter_title_1`, `chapter_title_2`, `chapter_title_3`.
```

- [ ] **Step 2: Commit**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
git add docs/release-notes-4.1.0.md
git commit -m "docs: draft release notes for 4.1.0"
```

---

## Task 12: Bump plugin version

**Files:**
- Modify: `_meta.lua`

- [ ] **Step 1: Bump version from 4.0.7 to 4.1.0**

Current contents of `_meta.lua`:
```lua
local _ = require("bookends_i18n").gettext
return {
    name = "bookends",
    fullname = _("Bookends"),
    description = _([[Configurable text overlays at screen corners and edges with token expansion and icon support.]]),
    version = "4.0.7",
}
```

Change `version = "4.0.7"` to `version = "4.1.0"`. Minor bump — the predicate renames are breaking for users who had `[if:percent…]` / `[if:chapter…]` / `[if:pages…]` in their presets, but (a) none of the gallery presets do, and (b) the plugin's release history treats feature additions with minor-predicate renames as minor bumps. Release notes flag the break; if maintainer prefers a major bump (5.0.0), adjust here.

- [ ] **Step 2: Verify**

Run:
```bash
grep "^    version" /home/andyhazz/projects/bookends.koplugin/_meta.lua
```
Expected: `    version = "4.1.0",`

- [ ] **Step 3: Commit**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
git add _meta.lua
git commit -m "chore(release): v4.1.0"
```

---

## Task 13: On-device smoke test

**Files:** None (Kindle testing only).

The pure-parser tests exercise the conditional machinery end-to-end, but `buildConditionState` runs against real KOReader data (TOC, book metadata, UI state) that the test harness can't simulate. This task verifies that the renamed and new predicates actually populate on the device.

- [ ] **Step 1: Syntax-check before SCP**

Run:
```bash
cd /home/andyhazz/projects/bookends.koplugin
luac -p bookends_tokens.lua && echo "syntax OK"
lua _test_conditionals.lua
```

Both must pass before pushing.

- [ ] **Step 2: Push changed files to the Kindle**

Run:
```bash
scp /home/andyhazz/projects/bookends.koplugin/bookends_tokens.lua \
    /home/andyhazz/projects/bookends.koplugin/_meta.lua \
    kindle:/mnt/us/koreader/plugins/bookends.koplugin/
```

Expected: two `100%` lines, no errors. (`scp` is the established iterative dev-loop; see memory `feedback_dev_workflow.md`.)

- [ ] **Step 3: Restart KOReader on the Kindle**

Tell the user: "Please force-restart KOReader on the Kindle so the new `bookends_tokens.lua` is loaded (menu → Exit, then reopen, or reboot)."

Wait for the user to confirm it's restarted before proceeding.

- [ ] **Step 4: Open a book with a known TOC and configure a test preset**

Ask the user to open a book that:
- Has a multi-depth TOC (for `chapter_title_1..3` coverage)
- Has author + series metadata (for `author` / `series`)
- Has >1 chapter (so `chapter`/`chapters` are non-trivial)

Ask them to add a temporary test-line somewhere in their active bookends preset:

```
[if:chapter_title_2]D2:%C2[else]D1:%C1[/if] · ch=%j/%J · [if:series]S:%S[else]no-series[/if] · [if:book_pct>50]>50%[/if]
```

- [ ] **Step 5: Verify the rendered line**

Ask the user to screenshot or describe what the line renders as. Check:
- `D2:<subchapter>` appears only when in a sub-chapter; `D1:<chapter>` appears otherwise.
- `ch=N/M` matches reality (N = current chapter index, M = total count).
- `S:<series>` appears for series books, `no-series` for standalone.
- `>50%` appears only past halfway.

If any check fails, troubleshoot:
- Check the Kindle crash log (`/mnt/us/koreader/crash.log`).
- `luac -p` the file on the Kindle (`ssh kindle "luac -p /mnt/us/koreader/plugins/bookends.koplugin/bookends_tokens.lua"`).
- Verify the right file actually got copied (`ssh kindle "md5sum /mnt/us/koreader/plugins/bookends.koplugin/bookends_tokens.lua"` vs local).

- [ ] **Step 6: Backwards-compat sanity check with existing gallery presets**

Ask the user to apply one of the shipped gallery presets (e.g. `Rich detail`, `Paper`) and verify it still renders correctly — specifically:
- `[if:connected=yes]%W[/if]` still works (WiFi symbol)
- `[if:batt<20]%B %b[/if]` still works (low-battery highlight)
- `[if:charging=yes] ⚡[/if]` still works
- `[if:format=EPUB]...[/if]` still works
- `%W`, `%j`, `%J`, `%C1`, `%C2`, `%C3` still render the same as before the refactor (the Task 7 helper extraction should be visually identical)

If any of these regress, the helper extraction (Task 7) or the rename (Task 6) likely broke something — bisect via git log.

- [ ] **Step 7: Ask the user to confirm the smoke test**

If all checks pass, the implementation is complete.

---

## Task 14: Wrap-up

**Files:** None (git state + reporting).

- [ ] **Step 1: Verify the commit history on the branch**

Run:
```bash
git -C /home/andyhazz/projects/bookends.koplugin log --oneline master..HEAD
```

Expected shape (order may vary slightly):
```
<sha> chore(release): v4.1.0
<sha> docs: draft release notes for 4.1.0
<sha> docs(readme): conditional operators, nesting, new predicates
<sha> feat(tokens): string predicates for emptiness/equality checks
<sha> feat(tokens): chapter and chapters conditional predicates
<sha> refactor(tokens): extract getChapterTitlesByDepth helper
<sha> refactor(tokens): rename ambiguous predicates
<sha> feat(tokens): nested [if:] blocks + and/or/not in predicates
<sha> feat(tokens): add evaluateExpression with and/or/not/parens
<sha> test(tokens): baseline regression suite for conditional parsing
<sha> test: scaffold dev-box runner for conditional parsing
```

Eleven commits. The `test: scaffold…` commit is temporary scaffolding — decide in the next step whether to squash.

- [ ] **Step 2: Decide on squash strategy**

The user's preference (per memory `feedback_dev_workflow.md`) is "squash before release". The twelve commits above tell the story during development, but for the merge it usually makes sense to squash into one or two commits:

Option A — **single squash commit** on merge:
```
feat(conditionals): nesting, operators, chapter/string predicates

- Nested [if:][if:][/if][/if] blocks
- and/or/not operators with parens in predicates
- New numeric predicates: chapter (%j), chapters (%J)
- New string predicates: title, author, series, chapter_title(_1..3)
- Renames: percent → book_pct, chapter(pct) → chapter_pct,
  pages → session_pages
- Closes #23

Breaking: the name `chapter` now means current-chapter-number
(matches %j). Any preset using `[if:chapter>N]` as a %-through-chapter
check must be updated to `[if:chapter_pct>N]`.
```

Option B — **two commits**: one for the feature, one for README + release notes + version bump.

Ask the user which they prefer before squashing.

- [ ] **Step 3: Report completion**

Summarise for the user:
- All tests pass (`lua _test_conditionals.lua` → 57+ passed, 0 failed).
- On-device smoke test succeeded.
- Branch is ready to merge.
- Release notes drafted at `docs/release-notes-4.1.0.md`.
- Version bumped to 4.1.0 in `_meta.lua`.

---

## Appendix: What's NOT tested by the dev-box runner

The pure-Lua test runner covers the conditional parser end-to-end, but does NOT exercise:

- `buildConditionState` runtime sourcing (requires `ui`, `doc`, `ui.toc`, `powerd`, `NetworkMgr`). Verified by on-device smoke test (Task 13).
- `Tokens.expand` full pipeline (tokens like `%T`, `%K`, pixel-width modifiers, symbol colours, bar info). Unchanged by this feature; relies on the Task 13 backwards-compat check.
- Interaction with preview mode (conditionals skipped in preview per `bookends_tokens.lua:239`). Unchanged.
- Translation-key churn (no new user-facing strings in this feature; all new keys are technical / README-only).

If future work materially changes the renderer-side expansion, consider extending `_test_conditionals.lua` with a mock `ui` harness. For this feature, the dev-box/on-device split is an appropriate coverage vs. infrastructure trade-off.
