# v5 Token System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace single-letter tokens (`%A`, `%J`, `%p`) with descriptive multi-char names (`%author`, `%chap_count`, `%book_pct`) aligned to conditional-state vocabulary; legacy names stay functional via alias tables forever; add `%datetime{strftime}` escape hatch and `%series_name`/`%series_num` split; unify three disjoint brace-modifier parsers into one outer parser plus per-token dispatch.

**Architecture:** One file (`bookends_tokens.lua`) holds the core change: two small alias tables (`TOKEN_ALIAS` string-level, `STATE_ALIAS` lookup-level), a pure `Tokens.canonicaliseLegacy()` utility, a single outer brace-grammar pattern with per-token handler dispatch, and a renamed `replace` table keyed on the new vocabulary. `bookends_line_editor.lua` calls `canonicaliseLegacy` on open and passes a `legacy_literal=true` flag into the live-preview path. `menu/token_picker.lua` and `README.md` rewrite their token surfaces to the new names; locales pick up ~6 new strings. Strict additive TDD: new behaviour lands behind a test first; legacy behaviour kept functional until the last cut-over.

**Tech Stack:** Lua 5.1 (LuaJIT in KOReader runtime), standalone `lua` interpreter for tests, `luac -p` for syntax checks, KOReader plugin conventions.

---

## Reference links

- **Spec:** `docs/superpowers/specs/2026-04-23-v5-token-system-design.md` (alongside this file).
- **Test runner pattern:** `_test_conditionals.lua` (pure-Lua; stubs `device`/`datetime`/`bookends_overlay_widget`; runs via `lua _test_conditionals.lua`).
- **Existing token file:** `bookends_tokens.lua` (1135 lines as of 2026-04-23).
- **Line editor integration point:** `bookends_line_editor.lua:45` (`current_text = pos_settings.lines[line_idx] or ""`).
- **Version file:** `_meta.lua`.
- **Release-notes precedent:** `docs/release-notes-4.4.0.md` (format/tone).

## Dev workflow (per project memory)

- Iterative: edit → `luac -p *.lua` → `lua _test_tokens.lua` → `lua _test_conditionals.lua`.
- To push to device for interactive verification (final task only):
  ```
  tar --exclude=tools --exclude=.git --exclude='_test_*.lua' -cf - -C /home/andyhazz/projects/bookends.koplugin . \
    | ssh kindle "cd /mnt/us/koreader/plugins/bookends.koplugin && tar -xf -"
  ```
  User manually restarts KOReader on device after push (SIGHUP does NOT reload).
- Commit cadence: one commit per task. Never squash during execution.
- NEVER use `git commit --no-verify` or skip hooks; there are none on this repo, but discipline matters.

---

## Task 1: Scaffold `_test_tokens.lua` with stub infrastructure

**Files:**
- Create: `_test_tokens.lua` (sibling of `_test_conditionals.lua`).

**Purpose:** Establish the standalone test runner for this plan. Copies the stub/harness pattern from `_test_conditionals.lua` so `bookends_tokens.lua` loads without KOReader. Starts with one trivially-passing smoke test to confirm the harness runs.

- [ ] **Step 1: Create the test file with stubs**

Write `_test_tokens.lua`:

```lua
-- Dev-box test runner for bookends_tokens.lua token vocabulary + grammar.
-- Runs pure-Lua (no KOReader) by stubbing the modules bookends_tokens requires.
-- Usage: cd into the plugin dir, then `lua _test_tokens.lua`.
-- Exits non-zero on failure; no external dependencies.

package.loaded["device"] = {
    getPowerDevice = function() return nil end,
    isKindle = function() return false end,
    hasNaturalLight = function() return false end,
    home_dir = "/",
}
package.loaded["datetime"] = {
    secondsToClockDuration = function() return "" end,
}
package.loaded["bookends_overlay_widget"] = { BAR_PLACEHOLDER = "\x00BAR\x00" }

-- G_reader_settings is a global in KOReader; stub it so module load succeeds.
_G.G_reader_settings = setmetatable({}, {
    __index = function() return function() return false end end,
    readSetting = function() return "classic" end,
    isTrue = function() return false end,
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
-- Smoke test: harness works and Tokens module loaded.
-- ============================================================================
test("smoke: Tokens module loads", function()
    assert(type(Tokens) == "table", "Tokens is not a table")
    assert(type(Tokens.expand) == "function", "Tokens.expand missing")
end)

-- ============================================================================
-- (More tests added by subsequent tasks.)
-- ============================================================================

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
```

- [ ] **Step 2: Run the harness**

Run: `cd /home/andyhazz/projects/bookends.koplugin && lua _test_tokens.lua`

Expected:
```
1 passed, 0 failed
```
Exit code 0.

- [ ] **Step 3: Run existing conditional tests to confirm nothing broke**

Run: `cd /home/andyhazz/projects/bookends.koplugin && lua _test_conditionals.lua`

Expected: existing "N passed, 0 failed" output (currently ~50+ tests).

- [ ] **Step 4: Commit**

```bash
git add _test_tokens.lua
git commit -m "test: scaffold _test_tokens.lua harness for v5 token work"
```

---

## Task 2: Add `TOKEN_ALIAS` table and single-pass rewrite function

**Files:**
- Modify: `bookends_tokens.lua` (add near the top, after the `Tokens = {}` declaration around line 5).
- Modify: `_test_tokens.lua` (add tests).

**Purpose:** Introduce the `TOKEN_ALIAS` table (legacy-letter → new-name) and a `Tokens._rewriteLegacyTokens(format_str)` function that performs the single-pass greedy-identifier rewrite described in the spec. This is a pure string-in/string-out utility, testable in isolation. No changes to `Tokens.expand` yet — the function exists but is not wired in. Prefixed `_` marks it test-only-exported.

- [ ] **Step 1: Write the failing tests first**

Append to `_test_tokens.lua` (before the final `io.write` summary block):

```lua
-- ============================================================================
-- Legacy token rewrite (TOKEN_ALIAS)
-- ============================================================================
test("rewrite: %A → %author", function()
    eq(Tokens._rewriteLegacyTokens("%A"), "%author")
end)

test("rewrite: %J → %chap_count", function()
    eq(Tokens._rewriteLegacyTokens("%J"), "%chap_count")
end)

test("rewrite: %C1 → %chap_title_1", function()
    eq(Tokens._rewriteLegacyTokens("%C1"), "%chap_title_1")
end)

test("rewrite: %C2 → %chap_title_2", function()
    eq(Tokens._rewriteLegacyTokens("%C2"), "%chap_title_2")
end)

test("rewrite preserves braces: %A{200} → %author{200}", function()
    eq(Tokens._rewriteLegacyTokens("%A{200}"), "%author{200}")
end)

test("rewrite preserves braces: %C1{300} → %chap_title_1{300}", function()
    eq(Tokens._rewriteLegacyTokens("%C1{300}"), "%chap_title_1{300}")
end)

test("rewrite idempotent: %author unchanged", function()
    eq(Tokens._rewriteLegacyTokens("%author"), "%author")
end)

test("rewrite idempotent: %chap_title_1 unchanged", function()
    eq(Tokens._rewriteLegacyTokens("%chap_title_1"), "%chap_title_1")
end)

test("rewrite mixed: '%A — %title' → '%author — %title'", function()
    eq(Tokens._rewriteLegacyTokens("%A — %title"), "%author — %title")
end)

test("rewrite leaves unknown tokens alone: %zzz unchanged", function()
    eq(Tokens._rewriteLegacyTokens("%zzz"), "%zzz")
end)

test("rewrite leaves literal % alone: 100%% unchanged", function()
    -- %% in a format string is literal %; our rewrite should not touch it.
    eq(Tokens._rewriteLegacyTokens("100%% read"), "100%% read")
end)

test("rewrite handles all legacy single-letter aliases", function()
    local cases = {
        {"%c", "%page_num"}, {"%t", "%page_count"}, {"%p", "%book_pct"},
        {"%P", "%chap_pct"}, {"%g", "%chap_read"}, {"%G", "%chap_pages"},
        {"%l", "%chap_pages_left"}, {"%L", "%pages_left"},
        {"%j", "%chap_num"}, {"%J", "%chap_count"},
        {"%T", "%title"}, {"%A", "%author"}, {"%S", "%series"},
        {"%C", "%chap_title"}, {"%N", "%filename"}, {"%i", "%lang"},
        {"%o", "%format"}, {"%q", "%highlights"}, {"%Q", "%notes"},
        {"%x", "%bookmarks"}, {"%X", "%annotations"},
        {"%k", "%time_12h"}, {"%K", "%time_24h"},
        {"%d", "%date"}, {"%D", "%date_long"}, {"%n", "%date_numeric"},
        {"%w", "%weekday"}, {"%a", "%weekday_short"},
        {"%R", "%session_time"}, {"%s", "%session_pages"},
        {"%r", "%speed"}, {"%E", "%book_read_time"},
        {"%h", "%chap_time_left"}, {"%H", "%book_time_left"},
        {"%b", "%batt"}, {"%B", "%batt_icon"},
        {"%W", "%wifi"}, {"%V", "%invert"},
        {"%f", "%light"}, {"%F", "%warmth"},
        {"%m", "%mem"}, {"%M", "%ram"}, {"%v", "%disk"},
    }
    for _i, pair in ipairs(cases) do
        eq(Tokens._rewriteLegacyTokens(pair[1]), pair[2], "case " .. pair[1])
    end
end)
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `lua _test_tokens.lua`

Expected: failures like `FAIL  rewrite: %A → %author` with `attempt to call a nil value (method '_rewriteLegacyTokens')`.

- [ ] **Step 3: Add `TOKEN_ALIAS` and `_rewriteLegacyTokens` to `bookends_tokens.lua`**

Open `bookends_tokens.lua` and add the following **after the `Tokens.pages_left_includes_current = false` line** (around line 11):

```lua
-- Legacy token → new-name alias map. See
-- docs/superpowers/specs/2026-04-23-v5-token-system-design.md for full rationale.
-- Single-letter keys only; %C1/%C2/%C3 handled via pattern in _rewriteLegacyTokens.
local TOKEN_ALIAS = {
    A = "author", T = "title", S = "series", C = "chap_title",
    J = "chap_count", j = "chap_num",
    p = "book_pct", P = "chap_pct",
    c = "page_num", t = "page_count", L = "pages_left", l = "chap_pages_left",
    g = "chap_read", G = "chap_pages",
    k = "time_12h", K = "time_24h",
    d = "date", D = "date_long", n = "date_numeric",
    w = "weekday", a = "weekday_short",
    R = "session_time", s = "session_pages",
    r = "speed", E = "book_read_time",
    h = "chap_time_left", H = "book_time_left",
    b = "batt", B = "batt_icon",
    W = "wifi", V = "invert",
    f = "light", F = "warmth",
    m = "mem", M = "ram", v = "disk",
    N = "filename", i = "lang", o = "format",
    q = "highlights", Q = "notes", x = "bookmarks", X = "annotations",
}

--- Rewrite legacy single-letter tokens (%A, %J, %C1, ...) to their v5 names.
-- Single-pass greedy-identifier match: %author captures "author" (length > 1,
-- untouched); %A captures "A" (length 1, in TOKEN_ALIAS, rewritten); %C1 is
-- matched separately via the ^C(%d)$ sub-pattern. Any {...} following a token
-- is preserved verbatim — this function does not touch braces.
-- Idempotent: applying twice gives the same result.
local function rewriteLegacyTokens(format_str)
    return (format_str:gsub("%%([%a_][%w_]*)", function(ident)
        if #ident == 1 and TOKEN_ALIAS[ident] then
            return "%" .. TOKEN_ALIAS[ident]
        end
        local depth = ident:match("^C(%d)$")
        if depth then
            return "%chap_title_" .. depth
        end
        return nil  -- keep as-is
    end))
end
```

Then **at the bottom of the file, before `return Tokens`**, add the test-only export:

```lua
Tokens._rewriteLegacyTokens = rewriteLegacyTokens
```

- [ ] **Step 4: Syntax-check + run tests**

Run: `luac -p bookends_tokens.lua && lua _test_tokens.lua`

Expected: `N passed, 0 failed` (where N is the new total including baseline plus all 12 new tests).

- [ ] **Step 5: Run conditional tests (regression check)**

Run: `lua _test_conditionals.lua`

Expected: unchanged pass count, 0 failed.

- [ ] **Step 6: Commit**

```bash
git add bookends_tokens.lua _test_tokens.lua
git commit -m "feat(tokens): add TOKEN_ALIAS table + _rewriteLegacyTokens helper"
```

---

## Task 3: Add `STATE_ALIAS` and route `evaluateCondition` through it

**Files:**
- Modify: `bookends_tokens.lua` (add near `TOKEN_ALIAS`; modify `evaluateCondition` around line 121).
- Modify: `_test_tokens.lua` (add tests).

**Purpose:** Legacy gallery presets use conditional predicates like `[if:chapters>10]`, `[if:percent>50]`, `[if:chapter_title]`. In v5 the canonical state keys will be `chap_count`, `book_pct`, `chap_title`. `STATE_ALIAS` is a lookup-level redirect: `evaluateCondition` resolves the key through the alias table before reading `state[key]`. No string rewriting of predicates — avoids the "did `chapters` appear as a literal value?" problem.

- [ ] **Step 1: Write the failing tests**

Append to `_test_tokens.lua`:

```lua
-- ============================================================================
-- STATE_ALIAS: legacy predicate names resolve to new state keys
-- ============================================================================
test("state alias: [if:chapters>10] reads state.chap_count", function()
    local r = Tokens._processConditionals(
        "[if:chapters>10]many[/if]", { chap_count = 15 })
    eq(r, "many")
end)

test("state alias: [if:chapter_title] reads state.chap_title", function()
    local r = Tokens._processConditionals(
        "[if:chapter_title]has[/if]", { chap_title = "Chapter 1" })
    eq(r, "has")
end)

test("state alias: [if:chapter_title_2] reads state.chap_title_2", function()
    local r = Tokens._processConditionals(
        "[if:chapter_title_2]sub[/if]", { chap_title_2 = "Sub" })
    eq(r, "sub")
end)

test("state alias: [if:percent>50] reads state.book_pct (pre-v4.1 name)", function()
    local r = Tokens._processConditionals(
        "[if:percent>50]past[/if]", { book_pct = 75 })
    eq(r, "past")
end)

test("state alias: [if:pages>20] reads state.session_pages (pre-v4.1 name)", function()
    local r = Tokens._processConditionals(
        "[if:pages>20]long[/if]", { session_pages = 30 })
    eq(r, "long")
end)

test("state alias: new key [if:chap_count>10] still works direct", function()
    local r = Tokens._processConditionals(
        "[if:chap_count>10]many[/if]", { chap_count = 15 })
    eq(r, "many")
end)

test("state alias: [if:title=chapters] preserves literal value 'chapters'", function()
    -- The key 'title' isn't aliased; value 'chapters' must NOT be rewritten.
    local r = Tokens._processConditionals(
        "[if:title=chapters]match[/if]", { title = "chapters" })
    eq(r, "match")
end)

test("state alias: mixed predicate '[if:chapters>10 and chap_pct>50]' works", function()
    local r = Tokens._processConditionals(
        "[if:chapters>10 and chap_pct>50]both[/if]",
        { chap_count = 15, chap_pct = 75 })
    eq(r, "both")
end)
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `lua _test_tokens.lua`

Expected: the eight new tests fail (most with empty-string output because `state[key]` returns `nil`).

- [ ] **Step 3: Add `STATE_ALIAS` to `bookends_tokens.lua`**

Insert after the `TOKEN_ALIAS` block:

```lua
-- Legacy conditional-state key → v5 state key. Resolved at lookup time inside
-- evaluateCondition (not as a string rewrite on predicates, so literal string
-- values like [if:title=chapters] keep their value unchanged).
-- Only the legacy names that differ from the new vocabulary need entries;
-- keys already on the new vocabulary (batt, title, author, book_pct, speed,
-- session, session_pages, wifi, connected, charging, light, invert, time,
-- day, page, format, series) are unchanged and not aliased.
local STATE_ALIAS = {
    chapters        = "chap_count",    -- v4.1 name
    chapter         = "chap_num",      -- v4.1 name (chapter number)
    chapter_pct     = "chap_pct",      -- v4.1 name
    chapter_title   = "chap_title",    -- v4.1 name
    chapter_title_1 = "chap_title_1",
    chapter_title_2 = "chap_title_2",
    chapter_title_3 = "chap_title_3",
    percent         = "book_pct",      -- pre-v4.1 gallery compat
    pages           = "session_pages", -- pre-v4.1 gallery compat
}
```

- [ ] **Step 4: Modify `evaluateCondition` to resolve aliases**

Locate `evaluateCondition` (around line 121). The current implementation does:

```lua
local state_val = state[key]
```

Change both occurrences (there are two — one inside the operator branch, one inside the truthy-check branch) to:

```lua
local resolved_key = STATE_ALIAS[key] or key
local state_val = state[resolved_key]
```

For the truthy branch, the existing code is:

```lua
    local key_only = cond_str:match("^([%w_]+)$")
    if key_only then
        local v = state[key_only]
        return v ~= nil and v ~= "" and v ~= false and v ~= 0 and v ~= "off" and v ~= "no"
    end
```

Change the `local v = state[key_only]` line to:

```lua
    local v = state[STATE_ALIAS[key_only] or key_only]
```

- [ ] **Step 5: Run the tests**

Run: `lua _test_tokens.lua && lua _test_conditionals.lua`

Expected: all tests pass in both files. Conditional baseline tests still green (they use either new-style or state values that don't clash with aliases).

- [ ] **Step 6: Commit**

```bash
git add bookends_tokens.lua _test_tokens.lua
git commit -m "feat(tokens): add STATE_ALIAS + lookup-time resolution in evaluateCondition"
```

---

## Task 4: Add `Tokens.canonicaliseLegacy()` pure function

**Files:**
- Modify: `bookends_tokens.lua`.
- Modify: `_test_tokens.lua`.

**Purpose:** Canonicalise a stored format string from legacy to v5 vocabulary. Used by the line editor when opening a line for editing, and by tests. Combines the token-level rewrite (already built in Task 2) with a predicate-key rewrite that walks `[if:…]` atoms. Pure string → string, idempotent.

- [ ] **Step 1: Write failing tests**

Append to `_test_tokens.lua`:

```lua
-- ============================================================================
-- canonicaliseLegacy: tokens + predicate keys rewritten; values preserved
-- ============================================================================
test("canon: token rewrite '%A — %title' → '%author — %title'", function()
    eq(Tokens.canonicaliseLegacy("%A — %title"), "%author — %title")
end)

test("canon: predicate key rewrite '[if:chapters>10]' → '[if:chap_count>10]'", function()
    eq(Tokens.canonicaliseLegacy("[if:chapters>10]ok[/if]"),
       "[if:chap_count>10]ok[/if]")
end)

test("canon: multi-key predicate '[if:chapters>10 and percent>50]'", function()
    eq(Tokens.canonicaliseLegacy("[if:chapters>10 and percent>50]x[/if]"),
       "[if:chap_count>10 and book_pct>50]x[/if]")
end)

test("canon: literal string value 'chapters' preserved in '[if:title=chapters]'", function()
    eq(Tokens.canonicaliseLegacy("[if:title=chapters]t[/if]"),
       "[if:title=chapters]t[/if]")
end)

test("canon: nested [if] blocks both rewritten", function()
    eq(Tokens.canonicaliseLegacy("[if:chapters>10][if:percent>50]x[/if][/if]"),
       "[if:chap_count>10][if:book_pct>50]x[/if][/if]")
end)

test("canon: [if:not chapters] keeps 'not' keyword, rewrites key", function()
    eq(Tokens.canonicaliseLegacy("[if:not chapters]empty[/if]"),
       "[if:not chap_count]empty[/if]")
end)

test("canon: idempotent — running twice gives same result", function()
    local once = Tokens.canonicaliseLegacy("%A [if:chapters>10]%J[/if]")
    local twice = Tokens.canonicaliseLegacy(once)
    eq(twice, once)
end)

test("canon: mixed legacy + new untouched new names", function()
    eq(Tokens.canonicaliseLegacy("%author — %A"), "%author — %author")
end)

test("canon: empty string returns empty string", function()
    eq(Tokens.canonicaliseLegacy(""), "")
end)

test("canon: string without any tokens or predicates unchanged", function()
    eq(Tokens.canonicaliseLegacy("Just plain text."), "Just plain text.")
end)
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `lua _test_tokens.lua`

Expected: `attempt to call a nil value (method 'canonicaliseLegacy')`.

- [ ] **Step 3: Add `Tokens.canonicaliseLegacy` to `bookends_tokens.lua`**

Insert **just before the `Tokens.expand` function declaration** (around line 426). This function reuses `rewriteLegacyTokens` (Task 2) and `tokeniseExpression` (already present, line 153) plus the `evaluateCondition` key-parse shape.

```lua
--- Rewrite legacy predicate-key names inside [if:...] openers.
-- Walks each opener's predicate via tokeniseExpression, rewrites the KEY
-- portion of each atom (the leading [%w_]+ run before any operator), leaves
-- values untouched. Boolean operators (and/or/not/parens) pass through.
local function rewriteConditionalKeys(s)
    return (s:gsub("%[if:([^%]]-)%]", function(pred)
        local toks = tokeniseExpression(pred)
        local out = {}
        for _i, tok in ipairs(toks) do
            if tok.kind == "atom" then
                -- atom = "key", "key=value", "key<value", "key>value" (same
                -- shape as evaluateCondition parses). Split on first operator.
                local key, op, rest = tok.value:match("^([%w_]+)([=<>])(.*)$")
                if key and op then
                    local new_key = STATE_ALIAS[key] or key
                    table.insert(out, new_key .. op .. rest)
                else
                    -- No operator: bare key
                    local bare = tok.value:match("^([%w_]+)$")
                    if bare then
                        table.insert(out, STATE_ALIAS[bare] or bare)
                    else
                        table.insert(out, tok.value)
                    end
                end
            else
                -- keyword / paren: emit verbatim
                table.insert(out, tok.value)
            end
        end
        return "[if:" .. table.concat(out, " ") .. "]"
    end))
end

--- Canonicalise a stored format string: legacy tokens → v5 names, legacy
-- predicate state keys → v5 keys. Pure and idempotent. Used by the line
-- editor on open, so users see their stored preset in v5 vocabulary.
function Tokens.canonicaliseLegacy(format_str)
    local s = rewriteLegacyTokens(format_str)
    s = rewriteConditionalKeys(s)
    return s
end
```

Note: `tokeniseExpression` is defined at line ~153 as a local function. `rewriteConditionalKeys` must be declared **after** that definition. Placing both new functions just before `Tokens.expand` (line 426) guarantees `tokeniseExpression` is already in scope.

- [ ] **Step 4: Run tests**

Run: `luac -p bookends_tokens.lua && lua _test_tokens.lua && lua _test_conditionals.lua`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add bookends_tokens.lua _test_tokens.lua
git commit -m "feat(tokens): add Tokens.canonicaliseLegacy for open-in-editor migration"
```

---

## Task 5: Wire `rewriteLegacyTokens` into `Tokens.expand` entrypoint

**Files:**
- Modify: `bookends_tokens.lua`.
- Modify: `_test_tokens.lua`.

**Purpose:** Activate the alias pass inside `Tokens.expand` so legacy tokens render correctly at runtime. Adds the rewrite at the top of `expand()` — after the fast-path checks (line 428), before any other processing. Later in this plan we'll add a `legacy_literal` caller flag to skip this pass for the line editor's live preview.

This is a behaviour-preserving change *for now*: legacy tokens already resolve via the existing single-char `(%%%a)` pass later in the file. After this task they'll be rewritten to new names before that pass runs — but the `replace` table still uses old `%A`-style keys, so this rewrite alone would break things. We must keep the `replace` table on old keys until Task 10 switches them.

**Solution for this task:** After the `rewriteLegacyTokens` call, rewrite the string *back* to the old form right before the existing replace-table lookup. This is a throwaway round-trip used only inside this task; Task 10 removes the back-rewrite once `replace` is re-keyed. This lets us verify the alias-pass integration independently without breaking other tests.

Actually simpler: the alias-pass is invisible externally if we do **both** the forward rewrite AND the back-rewrite. We test that legacy format strings still render the same output as before. Then in Task 10 we flip the replace table and remove the back-rewrite.

Rather than add a back-rewrite, the cleanest approach is: land the alias pass *together* with the replace-table re-keying in Task 10. So **this task does nothing in-place**; it's a sequencing / planning step only. Marking it with a no-op commit to preserve task boundaries.

**This task is a no-op. Skip to Task 6.** (Retained in plan so subsequent task numbers align with initial design iteration.)

- [ ] **Step 1: Skip — no changes.**

---

## Task 6: Refactor brace mini-parsers into one outer parser + dispatcher

**Files:**
- Modify: `bookends_tokens.lua`.
- Modify: `_test_tokens.lua`.

**Purpose:** The current code has three separate gsub-based parsers for braces (`%bar{…}`, `%C<d>{N}`, `(%%%a){N}`) at lines 463–501. Replace them with one outer pattern `%%([%a_][%w_]*)(%b{})` and a per-token dispatcher. This is a pure refactor — no new tokens, no new brace shapes — so behavior is preserved. Paves the way for `%datetime` in the next task.

The existing local `token_limits` / `bar_limit_w` / `bar_limit_h` logic stays; only the *parsing* of braces into those fields changes.

- [ ] **Step 1: Write regression tests for existing brace behaviour**

Append to `_test_tokens.lua` — tests that **currently pass** and must continue to pass after the refactor. We rely on `_test_conditionals.lua` for conditional regressions. These tests hit `Tokens.expandPreview` since it doesn't need a full ui/doc:

```lua
-- ============================================================================
-- Brace grammar regression: existing forms must keep working after refactor
-- ============================================================================
-- expandPreview uses symbolic placeholders, making these tests stable across
-- devices without needing real page/book state.

test("brace: '%bar' in preview renders ▰▰▱▱", function()
    local r = Tokens.expandPreview("%bar", { view = {} }, nil, nil, 2, nil)
    -- ▰▰▱▱ = U+25B0 U+25B0 U+25B1 U+25B1 → 12 bytes UTF-8
    eq(#r, 12, "expected 4 box-chars = 12 bytes")
end)

test("brace: '%bar{100}' preview shows width annotation", function()
    local r = Tokens.expandPreview("%bar{100}", { view = {} }, nil, nil, 2, nil)
    assert(r:find("100", 1, true), "expected '100' in preview: " .. r)
end)

test("brace: '%T{200}' preview shows [title]{<=200}", function()
    local r = Tokens.expandPreview("%T{200}", { view = {} }, nil, nil, 2, nil)
    assert(r:find("200", 1, true), "expected '200' in preview: " .. r)
end)

test("brace: '%C1{300}' preview shows {ch.1<=300}", function()
    local r = Tokens.expandPreview("%C1{300}", { view = {} }, nil, nil, 2, nil)
    assert(r:find("300", 1, true), "expected '300' in preview: " .. r)
end)
```

- [ ] **Step 2: Run tests — they should pass against current code**

Run: `lua _test_tokens.lua`

Expected: all pass (these tests lock in the baseline).

- [ ] **Step 3: Refactor the brace-parsing block in `Tokens.expand`**

In `bookends_tokens.lua`, locate lines 453–501 (the block starting with `-- Pre-parse %X{N} pixel-width modifiers.` and ending with the `%%%a){N}` gsub closing brace).

**Replace** the whole block with the following unified parser:

```lua
    -- Pre-parse %name{content} modifiers.
    -- Single outer pattern captures every %<ident>{<content>} occurrence; each
    -- token decides what its brace content means. Strips the braces from the
    -- format string (storing extracted data in per-token sidecar tables) so
    -- the later bareword expansion step is unchanged.
    --   %bar                auto width, default height
    --   %bar{100}           100px wide, default height
    --   %bar{v10}           auto width, 10px tall
    --   %bar{100v10}        100px wide, 10px tall
    --   %<text-token>{N}    pixel-width cap
    --   %datetime{spec}     strftime format (see Task 7)
    local token_limits = {}  -- { ["%author"] = { [1] = 200 }, ... }
    local bar_limit_w = nil
    local bar_limit_h = nil

    format_str = format_str:gsub("%%([%a_][%w_]*)(%b{})", function(name, brace)
        local content = brace:sub(2, -2)  -- strip { and }
        if name == "bar" then
            local w = content:match("^(%d+)")
            local h = content:match("v(%d+)")
            if w then
                local px = tonumber(w)
                if px and px > 0 then bar_limit_w = px end
            end
            if h then
                local px = tonumber(h)
                if px and px > 0 then bar_limit_h = px end
            end
            return "%bar"
        end
        -- Default: pixel-width cap (digits only).
        local n = content:match("^(%d+)$")
        if n then
            local px = tonumber(n)
            if px and px > 0 then
                local key = "%" .. name
                if not token_limits[key] then token_limits[key] = {} end
                table.insert(token_limits[key], px)
            end
            return "%" .. name
        end
        -- Non-digit content on a token without a registered handler:
        -- leave intact as literal (matches today's behaviour for %A{foo}).
        return nil
    end)
```

- [ ] **Step 4: Run regression tests**

Run: `luac -p bookends_tokens.lua && lua _test_tokens.lua && lua _test_conditionals.lua`

Expected: all tests pass. Token-limit extraction for legacy `%T{200}` etc. still works because at this point in the pipeline, legacy tokens haven't been rewritten yet (we haven't wired in Task 2's rewrite inside expand yet) — `name` will be `"T"` and key will be `"%T"`, matching the current `replace` table.

The `%C<d>{N}` legacy syntax is now handled by the generic branch: `%C1{300}` → `name="C1"`, `content="300"`, key `"%C1"`, limit 300. Later pipeline stages already look up `%C1` in `token_limits["%C1"]` (line ~1064).

- [ ] **Step 5: Commit**

```bash
git add bookends_tokens.lua _test_tokens.lua
git commit -m "refactor(tokens): collapse three brace mini-parsers into one dispatcher"
```

---

## Task 7: Add `%datetime{…}` handler

**Files:**
- Modify: `bookends_tokens.lua`.
- Modify: `_test_tokens.lua`.

**Purpose:** Register `datetime` in the unified brace dispatcher. Content is passed to `os.date` with locale handling. Bare `%datetime` (no braces) falls through as literal `%datetime` — no entry in the bareword `replace` table. Plain `%time`, `%date`, `%weekday` continue to exist as fixed-format tokens (added in Task 10).

- [ ] **Step 1: Write failing tests**

Append to `_test_tokens.lua`:

```lua
-- ============================================================================
-- %datetime{...} strftime escape hatch
-- ============================================================================
test("datetime: %datetime{%Y} expands to current year", function()
    local year = os.date("%Y")
    local r = Tokens.expandPreview("%datetime{%Y}", { view = {} }, nil, nil, 2, nil)
    eq(r, year)
end)

test("datetime: %datetime{%H:%M} expands to HH:MM clock", function()
    local r = Tokens.expandPreview("%datetime{%H:%M}", { view = {} }, nil, nil, 2, nil)
    assert(r:match("^%d+:%d%d$"), "expected HH:MM, got: " .. r)
end)

test("datetime: %datetime{%d %B} expands to day + full month", function()
    local expected = os.date("%d %B")
    local r = Tokens.expandPreview("%datetime{%d %B}", { view = {} }, nil, nil, 2, nil)
    eq(r, expected)
end)

test("datetime: bare %datetime falls through as literal", function()
    local r = Tokens.expandPreview("%datetime", { view = {} }, nil, nil, 2, nil)
    eq(r, "%datetime")
end)

test("datetime: mixed with literal text", function()
    local year = os.date("%Y")
    local r = Tokens.expandPreview("Year: %datetime{%Y}",
        { view = {} }, nil, nil, 2, nil)
    eq(r, "Year: " .. year)
end)
```

- [ ] **Step 2: Run tests — expect failures**

Run: `lua _test_tokens.lua`

Expected: the 5 new tests fail with literal `%datetime` output (brace content ignored or treated as pixel-width).

- [ ] **Step 3: Extend the brace dispatcher to handle `datetime`**

In `bookends_tokens.lua`, locate the unified brace-parser block you added in Task 6. Add a `datetime` branch **before** the "default: pixel-width cap" branch:

```lua
        if name == "datetime" then
            -- Strftime escape hatch. Respect device locale (see getDateLocale).
            local loc = getDateLocale()
            local saved_locale
            if loc then
                saved_locale = os.setlocale(nil, "time")
                os.setlocale(loc, "time")
            end
            local formatted = os.date(content) or ""
            if saved_locale then os.setlocale(saved_locale, "time") end
            return formatted
        end
```

So the full block becomes:

```lua
    format_str = format_str:gsub("%%([%a_][%w_]*)(%b{})", function(name, brace)
        local content = brace:sub(2, -2)
        if name == "bar" then
            -- ... (existing bar handling, unchanged) ...
            return "%bar"
        end
        if name == "datetime" then
            local loc = getDateLocale()
            local saved_locale
            if loc then
                saved_locale = os.setlocale(nil, "time")
                os.setlocale(loc, "time")
            end
            local formatted = os.date(content) or ""
            if saved_locale then os.setlocale(saved_locale, "time") end
            return formatted
        end
        -- ... (existing default: pixel-width cap, unchanged) ...
    end)
```

- [ ] **Step 4: Run tests**

Run: `luac -p bookends_tokens.lua && lua _test_tokens.lua && lua _test_conditionals.lua`

Expected: all tests pass. Bare `%datetime` case passes because `%datetime` with no braces isn't matched by the `%b{}` outer pattern, and there's no entry in `replace` for it — the trailing bareword gsub leaves it as literal (via the "unknown token" branch at line ~1075, `if val == nil then return token end`).

- [ ] **Step 5: Commit**

```bash
git add bookends_tokens.lua _test_tokens.lua
git commit -m "feat(tokens): add %datetime{strftime} escape hatch"
```

---

## Task 8: Rename state-key builders in `buildConditionState`

**Files:**
- Modify: `bookends_tokens.lua` (the `buildConditionState` function, lines 291–423).
- Modify: `_test_tokens.lua`.

**Purpose:** Change the state keys populated by `buildConditionState` to the new v5 names. Legacy predicates continue to work via `STATE_ALIAS` (Task 3). After this task the state vocabulary is fully v5; alias is the compatibility shim for predicates.

Keys to rename:
- `state.chapters` → `state.chap_count`
- `state.chapter` → `state.chap_num`
- `state.chapter_pct` → `state.chap_pct`
- `state.chapter_title` → `state.chap_title`
- `state.chapter_title_1/2/3` → `state.chap_title_1/2/3`

Keys unchanged: everything else (`batt`, `title`, `author`, `series`, `book_pct`, `speed`, `session`, `session_pages`, `wifi`, `connected`, `charging`, `light`, `invert`, `time`, `day`, `page`, `format`).

- [ ] **Step 1: Write tests for the new state vocabulary**

Append to `_test_tokens.lua`:

```lua
-- ============================================================================
-- buildConditionState populates v5 state key names
-- ============================================================================
-- Build a minimal stub ui/doc/toc that exercises the chapter-state path.
local function stubUi(page, total_pages, chapter_data)
    return {
        view = { state = { page = page } },
        document = {
            file = "/book.epub",
            getPageCount = function() return total_pages end,
            hasHiddenFlows = function() return false end,
            getProps = function() return {} end,
        },
        toc = chapter_data and {
            toc = chapter_data.toc,
            getTocTitleByPage = function(_, _) return chapter_data.title or "" end,
            getTocTicks = function() return {} end,
            getMaxDepth = function() return 1 end,
            getPreviousChapter = function(_, _) return chapter_data.start end,
            getNextChapter = function(_, _) return chapter_data.next end,
            isChapterStart = function(_, _) return false end,
            getChapterPagesDone = function(_, _) return 0 end,
            getChapterPageCount = function(_, _) return 1 end,
            getChapterPagesLeft = function(_, _) return 0 end,
        } or nil,
        doc_props = {},
        annotation = nil,
        statistics = nil,
    }
end

test("state: chap_num / chap_count populated (new v5 names)", function()
    local ui = stubUi(5, 100, {
        toc = { { page = 1, depth = 1, title = "C1" }, { page = 10, depth = 1, title = "C2" } },
        start = 1, next = 10,
    })
    local s = Tokens.buildConditionState(ui, 0, 0)
    eq(s.chap_num, 1, "chap_num")
    eq(s.chap_count, 2, "chap_count")
    eq(s.chapter_num, nil, "chapter_num should not be set on new-vocab state")
    eq(s.chapters, nil, "chapters should not be set on new-vocab state")
end)

test("state: chap_title / chap_title_1 populated (new v5 names)", function()
    local ui = stubUi(5, 100, {
        toc = { { page = 1, depth = 1, title = "C1" } },
        title = "C1",
        start = 1, next = 10,
    })
    local s = Tokens.buildConditionState(ui, 0, 0)
    eq(s.chap_title, "C1")
    eq(s.chap_title_1, "C1")
    eq(s.chapter_title, nil, "chapter_title should not be set on new-vocab state")
end)

test("state: legacy [if:chapters>0] still evaluates via STATE_ALIAS", function()
    local ui = stubUi(5, 100, {
        toc = { { page = 1, depth = 1, title = "C1" }, { page = 10, depth = 1, title = "C2" } },
        start = 1, next = 10,
    })
    local s = Tokens.buildConditionState(ui, 0, 0)
    -- Even though state.chapters is nil, the predicate still works via alias.
    local r = Tokens._processConditionals("[if:chapters>0]ok[/if]", s)
    eq(r, "ok")
end)
```

- [ ] **Step 2: Run tests — expect failures**

Run: `lua _test_tokens.lua`

Expected: first two new tests fail (state has `chapter`/`chapters`, not `chap_num`/`chap_count`). Third test depends on first two.

- [ ] **Step 3: Rename state-key assignments in `buildConditionState`**

In `bookends_tokens.lua`, open `buildConditionState` (line 291). Find the lines populating chapter state:

```lua
        -- Chapter number / total count — same source as %j / %J tokens.
        local titles = Tokens.getChapterTitlesByDepth(ui, pageno)
        if titles.chapter_num  > 0 then state.chapter  = titles.chapter_num  end
        if titles.chapter_count > 0 then state.chapters = titles.chapter_count end
```

Change to:

```lua
        -- Chapter number / total count — match %chap_num / %chap_count tokens.
        local titles = Tokens.getChapterTitlesByDepth(ui, pageno)
        if titles.chapter_num  > 0 then state.chap_num   = titles.chapter_num  end
        if titles.chapter_count > 0 then state.chap_count = titles.chapter_count end
```

Find the `chapter_pct` assignment (lines ~348–354):

```lua
                if total > 1 then
                    state.chapter_pct = math.floor((pageno - chapter_start) / (total - 1) * 100)
                elseif total > 0 then
                    state.chapter_pct = 100
                end
```

Change `state.chapter_pct` → `state.chap_pct` (both lines).

Find the chapter-title assignments (lines ~389–394):

```lua
    if pageno and ui.toc then
        local titles = Tokens.getChapterTitlesByDepth(ui, pageno)
        state.chapter_title   = titles.chapter_title or ""
        state.chapter_title_1 = titles.chapter_titles_by_depth[1] or ""
        state.chapter_title_2 = titles.chapter_titles_by_depth[2] or ""
        state.chapter_title_3 = titles.chapter_titles_by_depth[3] or ""
    end
```

Change to:

```lua
    if pageno and ui.toc then
        local titles = Tokens.getChapterTitlesByDepth(ui, pageno)
        state.chap_title   = titles.chapter_title or ""
        state.chap_title_1 = titles.chapter_titles_by_depth[1] or ""
        state.chap_title_2 = titles.chapter_titles_by_depth[2] or ""
        state.chap_title_3 = titles.chapter_titles_by_depth[3] or ""
    end
```

- [ ] **Step 4: Run tests**

Run: `luac -p bookends_tokens.lua && lua _test_tokens.lua && lua _test_conditionals.lua`

Expected: all tests pass. Conditional tests that reference `state.chapter_pct`, `state.chapter`, `state.chapters`, `state.chapter_title`, `state.chapter_title_1..3` continue to pass because `STATE_ALIAS` redirects lookups.

*Worth double-checking* `_test_conditionals.lua` for any test that directly sets the old state key and asserts against it — if present, those tests use the aliased form via `_processConditionals` which passes the state table through; they work because the alias is on the *predicate key*, not the state key. The state table the test provides is indexed directly; our `STATE_ALIAS` redirection transforms the predicate's key before indexing. So `state = { chapter_pct = 50 }` with predicate `[if:chapter_pct>40]` works: predicate key `chapter_pct` → resolved via STATE_ALIAS → `chap_pct` → state.chap_pct is nil → fail. Hmm.

This is a subtle breakage. The test passes state with the legacy key name and expects the legacy predicate to evaluate. Before this task, state.chapter_pct = 50 and predicate `chapter_pct` → state.chapter_pct = 50 → true.

After this task, state.chapter_pct = 50 (set by test, not by buildConditionState). Predicate `chapter_pct` → STATE_ALIAS['chapter_pct'] = 'chap_pct' → state.chap_pct = nil → fail.

**Fix:** Review `_test_conditionals.lua` for any direct-state-key usages of the renamed keys (`chapter`, `chapters`, `chapter_pct`, `chapter_title`, `chapter_title_1..3`) and update the test's state table to use the new key names. The alias is for LEGACY PREDICATES reading against NEW STATE; not for NEW PREDICATES reading against LEGACY STATE.

Run: `grep -nE "state.chapter[^_]|state\.chapters|state\.chapter_pct|state\.chapter_title" _test_conditionals.lua`

For each match, if the test populates `state = { chapter_pct = N }`, change to `state = { chap_pct = N }`. Predicate strings can stay legacy (tests the alias path) or be updated to new names (tests the direct path). Prefer **direct path for new/renamed key, alias path for old name** to cover both.

Concrete edits (based on expected matches):
- Any `{ chapters = N }` → `{ chap_count = N }` in test state tables.
- Any `{ chapter = N }` → `{ chap_num = N }` in test state tables.
- Any `{ chapter_pct = N }` → `{ chap_pct = N }`.
- Any `{ chapter_title = "..." }` → `{ chap_title = "..." }`.
- Any `{ chapter_title_1 = "..." }` → `{ chap_title_1 = "..." }` (and _2, _3).

Predicate strings inside those same tests can stay as they are (legacy predicate → new state key via alias = exactly what we want to prove).

- [ ] **Step 5: Update `_test_conditionals.lua` for any direct-state-key breakages**

Run the grep above and fix each site. Add a new test in `_test_conditionals.lua` (at the end, before the summary) explicitly documenting the alias path:

```lua
test("alias: new state key name + legacy predicate name both resolve", function()
    local r = Tokens._processConditionals("[if:chapters>5]many[/if]", { chap_count = 10 })
    eq(r, "many")
end)
```

- [ ] **Step 6: Run full test suite**

Run: `luac -p bookends_tokens.lua && lua _test_tokens.lua && lua _test_conditionals.lua`

Expected: all pass, zero failures.

- [ ] **Step 7: Commit**

```bash
git add bookends_tokens.lua _test_tokens.lua _test_conditionals.lua
git commit -m "refactor(state): rename chapter* state keys to chap_* (alias covers legacy)"
```

---

## Task 9: Re-key the `replace` table to v5 names + wire in alias rewrite

**Files:**
- Modify: `bookends_tokens.lua`.
- Modify: `_test_tokens.lua`.

**Purpose:** This is the biggest single change. Renames all `replace` table keys from `%A`, `%J`, `%p`, `%c`, etc. to `%author`, `%chap_count`, `%book_pct`, `%page_num`, etc. — and activates the alias-rewrite pass at the top of `Tokens.expand` so legacy format strings still work. Also updates the `always_content` set and any other site inside `Tokens.expand` that references old `%X` keys.

**Sequencing discipline:** Do the two edits as one atomic commit. Splitting them means one half is broken.

- [ ] **Step 1: Write failing tests**

Append to `_test_tokens.lua`:

```lua
-- ============================================================================
-- v5 token names resolve through the full Tokens.expand pipeline
-- ============================================================================
-- A richer stubUi for expansion tests — covers doc props + pageno.
local function stubUiForExpand()
    return {
        view = { state = { page = 5 } },
        document = {
            file = "/Foundation.epub",
            getPageCount = function() return 100 end,
            hasHiddenFlows = function() return false end,
            getProps = function()
                return { title = "Foundation", authors = "Isaac Asimov",
                         series = "Foundation", series_index = 1 }
            end,
        },
        doc_props = { display_title = "Foundation", authors = "Isaac Asimov",
                      series = "Foundation", series_index = 1 },
        toc = nil,
        pagemap = nil,
        annotation = nil,
        statistics = nil,
    }
end

test("v5 tokens: %author expands to author name", function()
    local r = Tokens.expand("%author", stubUiForExpand(), nil, nil, false, 2, nil)
    eq(r, "Isaac Asimov")
end)

test("v5 tokens: %title expands to title", function()
    local r = Tokens.expand("%title", stubUiForExpand(), nil, nil, false, 2, nil)
    eq(r, "Foundation")
end)

test("v5 tokens: %page_num expands to current page", function()
    local r = Tokens.expand("%page_num", stubUiForExpand(), nil, nil, false, 2, nil)
    eq(r, "5")
end)

test("legacy alias via expand: %A expands to author name", function()
    local r = Tokens.expand("%A", stubUiForExpand(), nil, nil, false, 2, nil)
    eq(r, "Isaac Asimov")
end)

test("legacy alias via expand: %T expands to title", function()
    local r = Tokens.expand("%T", stubUiForExpand(), nil, nil, false, 2, nil)
    eq(r, "Foundation")
end)

test("legacy alias via expand: %c expands to current page", function()
    local r = Tokens.expand("%c", stubUiForExpand(), nil, nil, false, 2, nil)
    eq(r, "5")
end)

test("mixed legacy + new: '%A — %title' → 'Isaac Asimov — Foundation'", function()
    local r = Tokens.expand("%A — %title", stubUiForExpand(), nil, nil, false, 2, nil)
    eq(r, "Isaac Asimov — Foundation")
end)
```

- [ ] **Step 2: Run tests — expect failures for v5 names**

Run: `lua _test_tokens.lua`

Expected: "v5 tokens: %author..." tests fail (replace table still keyed `%A`). "legacy alias" tests may pass because `%A` is still the replace-table key.

- [ ] **Step 3: Wire in the alias rewrite at the top of `Tokens.expand`**

Open `bookends_tokens.lua`, locate `Tokens.expand` (line 426). Find the signature:

```lua
function Tokens.expand(format_str, ui, session_elapsed, session_pages_read, preview_mode, tick_width_multiplier, symbol_color, paint_ctx)
```

Keep it as is for now. Find the fast-path check (around line 428):

```lua
    -- Fast path: no tokens or conditionals
    if not format_str:find("%%") and not format_str:find("%[if:") then
        return format_str
    end
```

**Immediately after** this fast-path return, before the conditional-processing block, insert:

```lua
    -- v5 alias pass: rewrite legacy %X tokens to v5 names so all downstream
    -- processing uses a single vocabulary. Gallery presets and user-authored
    -- legacy strings render identically. Task 10 adds a caller flag to skip
    -- this pass for the line-editor live preview.
    format_str = rewriteLegacyTokens(format_str)
```

- [ ] **Step 4: Re-key the `replace` table to v5 names**

Locate the big `replace` table (starts line ~992). Replace it with:

```lua
    local replace = {
        -- Page/Progress
        page_num   = tostring(currentpage),
        page_count = tostring(totalpages),
        book_pct   = tostring(percent),
        chap_pct   = tostring(chapter_pct),
        chap_read  = tostring(chapter_pages_done),
        chap_pages = tostring(chapter_total_pages),
        chap_pages_left = tostring(chapter_pages_left),
        pages_left = tostring(pages_left_book),
        chap_num   = tostring(chapter_num),
        chap_count = tostring(chapter_count),
        -- Time/Reading
        chap_time_left = tostring(time_left_chapter),
        book_time_left = tostring(time_left_doc),
        time_12h = time_12h,
        time_24h = time_24h,
        time     = time_24h,              -- plain %time = %time_24h
        date          = date_short,
        date_long     = date_long,
        date_numeric  = date_num,
        weekday       = date_weekday,
        weekday_short = date_weekday_short,
        session_time  = session_time,
        session_pages = tostring(session_pages),
        -- Metadata
        title       = tostring(title),
        author      = tostring(authors),
        series      = tostring(series),
        series_name = tostring(series_name or ""),   -- populated in Task 11
        series_num  = tostring(series_num or ""),    -- populated in Task 11
        chap_title  = tostring(chapter_title),
        filename    = file_name,
        lang        = book_language,
        format      = doc_format,
        highlights  = highlights_count,
        notes       = notes_count,
        bookmarks   = bookmarks_count,
        annotations = total_annotations,
        -- Statistics
        speed          = reading_speed,
        book_read_time = total_book_time,
        -- Device
        batt      = tostring(batt_lvl),
        batt_icon = tostring(batt_symbol),
        wifi      = wifi_symbol,
        light     = fl_intensity,
        warmth    = fl_warmth,
        mem       = tostring(mem_usage),
        ram       = ram_mb,
        disk      = disk_avail,
        invert    = page_turn_symbol,
    }
```

Note: keys are **bareword** (no leading `%`) because the lookup pass now uses the captured identifier directly.

- [ ] **Step 5: Update the depth-specific chapter expansion**

Locate the `result_str:gsub("%%C(%d)", ...)` block around line 1058. Replace with:

```lua
    -- Expand depth-specific chapter tokens (%chap_title_1..3) before bareword tokens.
    local result = result_str:gsub("%%chap_title_(%d)", function(depth_str)
        local d = tonumber(depth_str)
        has_token = true
        local val = chapter_titles_by_depth[d] or ""
        if val ~= "" then all_empty = false end
        local key = "%chap_title_" .. depth_str
        if token_limits[key] then
            token_occurrence[key] = (token_occurrence[key] or 0) + 1
            local px = token_limits[key][token_occurrence[key]]
            if px then
                return "\x01" .. tostring(px) .. "\x02" .. val .. "\x03"
            end
        end
        return val
    end)
```

Note: `token_limits` keys now use the v5 prefix (`"%chap_title_1"` etc.) because the brace parser in Task 6 now stores under `"%" .. name` where `name` includes underscores and digits.

- [ ] **Step 6: Update the bareword-token expansion pass**

Locate the main expansion gsub around line 1073:

```lua
    result = result:gsub("(%%%a)", function(token)
        local val = replace[token]
        ...
    end)
```

Replace with:

```lua
    result = result:gsub("%%([%a_][%w_]*)", function(ident)
        local val = replace[ident]
        if val == nil then return "%" .. ident end  -- unknown, leave as-is
        has_token = true
        if (val ~= "" and val ~= "0") or always_content[ident] then
            all_empty = false
        end
        -- Pixel-width wrap if applicable
        local key = "%" .. ident
        if token_limits[key] then
            token_occurrence[key] = (token_occurrence[key] or 0) + 1
            local px = token_limits[key][token_occurrence[key]]
            if px then
                if val:find("\n") then
                    local wrapped = {}
                    for line in val:gmatch("([^\n]+)") do
                        table.insert(wrapped, "\x01" .. tostring(px) .. "\x02" .. line .. "\x03")
                    end
                    return table.concat(wrapped, "\n")
                end
                return "\x01" .. tostring(px) .. "\x02" .. val .. "\x03"
            end
        end
        return val
    end)
```

- [ ] **Step 7: Update `always_content` to use v5 keys**

Locate `always_content` (line ~1046) and update:

```lua
    local always_content = {
        page_num = true, page_count = true, book_pct = true, pages_left = true,
        chap_pct = true, chap_read = true, chap_pages = true, chap_pages_left = true,
        chap_num = true, chap_count = true,
        chap_time_left = true, book_time_left = true, time_12h = true, time_24h = true,
        time = true,
        session_time = true, session_pages = true, speed = true,
    }
```

- [ ] **Step 8: Update preview-mode labels to use v5 names**

Locate the `preview` table around line 504. Replace with:

```lua
        local preview = {
            page_num = "[page]", page_count = "[total]",
            book_pct = "[%]", chap_pct = "[ch%]",
            chap_read = "[ch.read]", chap_pages = "[ch.total]",
            chap_pages_left = "[ch.left]", pages_left = "[left]",
            chap_num = "[ch.num]", chap_count = "[ch.count]",
            chap_time_left = "[ch.time]", book_time_left = "[time]",
            time_12h = "[12h]", time_24h = "[24h]", time = "[24h]",
            date = "[date]", date_long = "[date.long]",
            date_numeric = "[dd/mm/yy]",
            weekday = "[weekday]", weekday_short = "[wkday]",
            session_time = "[session]", session_pages = "[pages]",
            title = "[title]", author = "[author]",
            series = "[series]", series_name = "[series.name]", series_num = "[series.#]",
            chap_title = "[chapter]",
            filename = "[file]", lang = "[lang]",
            format = "[format]",
            highlights = "[highlights]", notes = "[notes]",
            bookmarks = "[bookmarks]", annotations = "[annotations]",
            speed = "[pg/hr]", book_read_time = "[total]",
            batt = "[batt]", batt_icon = "[batt]", wifi = "[wifi]",
            invert = "[invert]",
            light = "[light]", warmth = "[warmth]",
            mem = "[mem]", ram = "[rss]",
            disk = "[disk]",
            bar = "\xE2\x96\xB0\xE2\x96\xB0\xE2\x96\xB1\xE2\x96\xB1",  -- ▰▰▱▱
        }
```

Update the preview-mode substitution passes (lines ~530–550) to use the new bareword keys:

```lua
        local r = orig_format_str:gsub("%%bar{(%d+)}", function(n)
            return preview.bar .. "{<=" .. n .. "}"
        end)
        r = r:gsub("%%bar", preview.bar)
        -- Depth-specific chapter-title before bareword tokens
        r = r:gsub("%%chap_title_(%d){(%d+)}", function(depth, n)
            return "{ch." .. depth .. "<=" .. n .. "}"
        end)
        r = r:gsub("%%chap_title_(%d)", function(depth)
            return "[ch." .. depth .. "]"
        end)
        -- Legacy %C1/2/3 fall through legacy-alias rewrite pass above this point
        r = r:gsub("%%([%a_][%w_]*){(%d+)}", function(token, n)
            local label = preview[token]
            if label then
                return "{" .. label:sub(2, -2) .. "<=" .. n .. "}"
            end
            return "%" .. token .. "{" .. n .. "}"
        end)
        r = r:gsub("%%([%a_][%w_]*)", function(token)
            local label = preview[token]
            if label then return label end
            return "%" .. token
        end)
        return r
```

(The legacy-alias rewrite at the top of `Tokens.expand` runs **before** the preview-mode branch is entered, so by the time preview substitution runs, `%C1` has already been rewritten to `%chap_title_1`. Good.)

- [ ] **Step 9: Update `needs()` single-letter checks**

Locate the `needs(...)` helper (line ~555) and the many `needs("c", "t", "p", "L")` call sites. The `needs()` function currently matches `"%%c[^%a]"` — a single literal char. We need it to match v5 bareword names like `"page_num"`.

Replace `needs` with:

```lua
    local function needs(...)
        for i = 1, select("#", ...) do
            local name = select(i, ...)
            if format_str:find("%%" .. name .. "[^%w_]")
                    or format_str:match("%%" .. name .. "$") then
                return true
            end
        end
        return false
    end
```

Update every `needs(...)` call site to use the v5 bareword names. The calls to update (grep for `needs(`):

| Line (approx) | Before | After |
|---|---|---|
| 578 | `needs("c", "t", "p", "L")` | `needs("page_num", "page_count", "book_pct", "pages_left")` |
| 632 | `needs("P", "g", "G", "l", "C", "j", "J")` | `needs("chap_pct", "chap_read", "chap_pages", "chap_pages_left", "chap_title", "chap_num", "chap_count")` |
| 730 | `needs("h", "H")` | `needs("chap_time_left", "book_time_left")` |
| 730 | `needs("h")` | `needs("chap_time_left")` |
| 744 | `needs("H")` | `needs("book_time_left")` |
| 758 | `needs("k")` | `needs("time_12h")` |
| 761 | `needs("K")` | `needs("time_24h", "time")` |
| 771 | `needs("d", "D", "n", "w", "a")` | `needs("date", "date_long", "date_numeric", "weekday", "weekday_short")` |
| 779 | `needs("d")` | `needs("date")` |
| 780 | `needs("D")` | `needs("date_long")` |
| 781 | `needs("n")` | `needs("date_numeric")` |
| 782 | `needs("w")` | `needs("weekday")` |
| 783 | `needs("a")` | `needs("weekday_short")` |
| 791 | `needs("R")` | `needs("session_time")` |
| 801 | `needs("T", "A", "S", "i")` | `needs("title", "author", "series", "series_name", "series_num", "lang")` |
| 812 | `needs("i")` | `needs("lang")` |
| 820 | `needs("N", "o")` | `needs("filename", "format")` |
| 823 | `needs("N")` | `needs("filename")` |
| 826 | `needs("o")` | `needs("format")` |
| 835 | `needs("q", "Q", "x")` | `needs("highlights", "notes", "bookmarks")` |
| 837 | `needs("q")` | `needs("highlights")` |
| 838 | `needs("Q")` | `needs("notes")` |
| 839 | `needs("x")` | `needs("bookmarks")` |
| 851 | `needs("r", "E")` | `needs("speed", "book_read_time")` |
| 852 | `needs("r")` | `needs("speed")` |
| 863 | `needs("E")` | `needs("book_read_time")` |
| 875 | `needs("b", "B")` | `needs("batt", "batt_icon")` |
| 886 | `needs("W")` | `needs("wifi")` |
| 901 | `needs("f", "F")` | `needs("light", "warmth")` |
| 903 | `needs("f")` | `needs("light")` |
| 907 | `needs("F")` | `needs("warmth")` |
| 914 | `needs("m")` | `needs("mem")` |
| 935 | `needs("M")` | `needs("ram")` |
| 951 | `needs("v")` | `needs("disk")` |
| 966 | `needs("V")` | `needs("invert")` |
| 980 | `needs("X")` | `needs("annotations")` |

(Line numbers approximate and will drift by a few after earlier tasks; use grep to find each call.)

Also locate the line computing `has_bar` (around line 564):

```lua
    local has_bar = format_str:find("%%bar") ~= nil
```

Unchanged — this is already using a bareword match.

- [ ] **Step 10: Syntax-check**

Run: `luac -p bookends_tokens.lua`

Expected: no errors.

- [ ] **Step 11: Run the full test suite**

Run: `lua _test_tokens.lua && lua _test_conditionals.lua`

Expected: all tests pass. Both legacy (`%A`) and v5 (`%author`) tokens resolve correctly.

Common issues if tests fail here:
- Forgot to update a `needs(...)` call site → that token silently evaluates to empty string.
- Missed a `replace["%X"]` reference outside the main table → grep for `replace%[`.
- Preview-mode substitution not matching a token → check the regex patterns use `[%a_][%w_]*`.

- [ ] **Step 12: Commit**

```bash
git add bookends_tokens.lua _test_tokens.lua
git commit -m "feat(tokens): v5 replace-table keys + alias rewrite pass in expand"
```

---

## Task 10: Add `%series_name` and `%series_num` split

**Files:**
- Modify: `bookends_tokens.lua`.
- Modify: `_test_tokens.lua`.

**Purpose:** The spec calls for splitting `%series` into separate `%series_name` and `%series_num` tokens while keeping combined `%series`. Task 9 already added `series_name`/`series_num` to the `replace` table shell; this task populates the two values.

- [ ] **Step 1: Write failing tests**

Append to `_test_tokens.lua`:

```lua
-- ============================================================================
-- series split: %series, %series_name, %series_num
-- ============================================================================
test("series: %series unchanged (combined 'Foundation #1')", function()
    local r = Tokens.expand("%series", stubUiForExpand(), nil, nil, false, 2, nil)
    eq(r, "Foundation #1")
end)

test("series: %series_name alone gives 'Foundation'", function()
    local r = Tokens.expand("%series_name", stubUiForExpand(), nil, nil, false, 2, nil)
    eq(r, "Foundation")
end)

test("series: %series_num alone gives '1'", function()
    local r = Tokens.expand("%series_num", stubUiForExpand(), nil, nil, false, 2, nil)
    eq(r, "1")
end)

test("series: custom layout '%series_name, book %series_num'", function()
    local r = Tokens.expand("%series_name, book %series_num",
        stubUiForExpand(), nil, nil, false, 2, nil)
    eq(r, "Foundation, book 1")
end)
```

- [ ] **Step 2: Run tests — expect empty-string failures**

Run: `lua _test_tokens.lua`

Expected: series_name and series_num tests fail (values are empty strings — the Task 9 shell wrote `series_name or ""`).

- [ ] **Step 3: Populate `series_name` and `series_num` locals in `Tokens.expand`**

Locate the metadata block (around line 801):

```lua
    if needs("title", "author", "series", "series_name", "series_num", "lang") then
        local doc_props = ui.doc_props or {}
        local ok, props = pcall(doc.getProps, doc)
        if not ok then props = {} end
        title = doc_props.display_title or props.title or ""
        authors = doc_props.authors or props.authors or ""
        series = doc_props.series or props.series or ""
        local series_index = doc_props.series_index or props.series_index
        if series ~= "" and series_index then
            series = series .. " #" .. series_index
        end
        ...
    end
```

Declare two new locals above the block:

```lua
    local series_name = ""
    local series_num = ""
```

Inside the block, after computing `series`, extract the parts:

```lua
        series_name = doc_props.series or props.series or ""
        local series_index = doc_props.series_index or props.series_index
        series_num = series_index and tostring(series_index) or ""
        series = series_name  -- reset: build combined form below
        if series ~= "" and series_index then
            series = series .. " #" .. series_index
        end
```

Update the `replace` table entries (placeholder from Task 9):

```lua
        series_name = tostring(series_name),
        series_num  = tostring(series_num),
```

- [ ] **Step 4: Run tests**

Run: `luac -p bookends_tokens.lua && lua _test_tokens.lua && lua _test_conditionals.lua`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add bookends_tokens.lua _test_tokens.lua
git commit -m "feat(tokens): add %series_name and %series_num split tokens"
```

---

## Task 11: Add `legacy_literal` caller flag and `Tokens.expandPreview` update

**Files:**
- Modify: `bookends_tokens.lua`.
- Modify: `_test_tokens.lua`.

**Purpose:** The line editor's live-preview path needs to skip the alias-rewrite pass so typing `%A` mid-edit shows literal `%A`, not "Isaac Asimov" (preventing flicker as users type new multi-char tokens like `%chap_num` through `%c` / `%ch` / etc.). Adds an options-table parameter to `Tokens.expand` and `Tokens.expandPreview`.

- [ ] **Step 1: Write failing tests**

Append to `_test_tokens.lua`:

```lua
-- ============================================================================
-- legacy_literal flag: skip alias rewrite for live-preview behaviour
-- ============================================================================
test("legacy_literal: %A stays literal in preview", function()
    local r = Tokens.expandPreview("%A", stubUiForExpand(), nil, nil, 2, nil,
        { legacy_literal = true })
    eq(r, "%A")
end)

test("legacy_literal: %author still resolves in preview", function()
    local r = Tokens.expandPreview("%author", stubUiForExpand(), nil, nil, 2, nil,
        { legacy_literal = true })
    eq(r, "[author]")  -- preview-mode label
end)

test("legacy_literal: default (no opts) keeps rewriting", function()
    local r = Tokens.expandPreview("%A", stubUiForExpand(), nil, nil, 2, nil)
    eq(r, "[author]")
end)

test("legacy_literal: [if:chapters>10] keeps legacy key literal in preview", function()
    -- In preview mode, conditionals are bypassed entirely (line 435 fast-path).
    -- The legacy predicate body just passes through untouched.
    local r = Tokens.expandPreview("[if:chapters>10]X[/if]",
        stubUiForExpand(), nil, nil, 2, nil, { legacy_literal = true })
    -- Preview mode returns the format string with bracketed labels for tokens;
    -- the [if:...] block itself is not evaluated in preview.
    assert(r:find("%[if:chapters>10%]"), "expected legacy predicate preserved: " .. r)
end)
```

- [ ] **Step 2: Run tests — expect failures**

Run: `lua _test_tokens.lua`

Expected: first two `legacy_literal` tests fail (`%A` resolves to `[author]` label regardless of the flag).

- [ ] **Step 3: Extend `Tokens.expand` signature with an options-table tail**

Modify the function signature:

```lua
function Tokens.expand(format_str, ui, session_elapsed, session_pages_read, preview_mode, tick_width_multiplier, symbol_color, paint_ctx, opts)
```

Inside the function, near the top (just after the fast-path check):

```lua
    opts = opts or {}
```

Locate the alias rewrite (added in Task 9):

```lua
    format_str = rewriteLegacyTokens(format_str)
```

Gate it on the flag:

```lua
    if not opts.legacy_literal then
        format_str = rewriteLegacyTokens(format_str)
    end
```

- [ ] **Step 4: Extend `Tokens.expandPreview` signature and pass opts**

Locate `Tokens.expandPreview` (line ~1123) and change to:

```lua
function Tokens.expandPreview(format_str, ui, session_elapsed, session_pages_read, tick_width_multiplier, symbol_color, opts)
    return Tokens.expand(format_str, ui, session_elapsed, session_pages_read, true, tick_width_multiplier, symbol_color, nil, opts)
end
```

- [ ] **Step 5: Run tests**

Run: `luac -p bookends_tokens.lua && lua _test_tokens.lua && lua _test_conditionals.lua`

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add bookends_tokens.lua _test_tokens.lua
git commit -m "feat(tokens): add legacy_literal opt for line-editor live preview"
```

---

## Task 12: Integrate `canonicaliseLegacy` into the line editor

**Files:**
- Modify: `bookends_line_editor.lua`.

**Purpose:** When the user opens a line for editing, the stored string (potentially legacy) is canonicalised to v5 vocabulary before being shown in the `InputDialog`. When they save, the new form is persisted automatically (existing save path). Live preview while typing uses `legacy_literal = true` so partial typing doesn't flicker through legacy-alias resolutions.

This has no standalone test — it's a line-editor UI integration. Manual verification only.

- [ ] **Step 1: Locate the line-editor open path**

Open `bookends_line_editor.lua`. Find line 45:

```lua
local current_text = pos_settings.lines[line_idx] or ""
```

- [ ] **Step 2: Canonicalise on open**

Change to:

```lua
local Tokens = require("bookends_tokens")
local current_text = Tokens.canonicaliseLegacy(pos_settings.lines[line_idx] or "")
```

*Caveat:* If `bookends_tokens` is already required elsewhere in the file, reuse that binding. Grep:

```bash
grep -n "require.*bookends_tokens\|require('bookends_tokens')" bookends_line_editor.lua
```

If a `Tokens = require(...)` line exists, don't add a second one. Just use `Tokens.canonicaliseLegacy(...)` in the assignment.

- [ ] **Step 3: Pass `legacy_literal = true` into the live-preview path**

The live-preview path is not in this file directly — it's in `bookends_overlay_widget.lua` where the overlay paints itself. However, the `edited_callback` at line 390 marks the widget dirty, triggering a repaint. The widget calls `Tokens.expand` during paint.

We need to thread the `legacy_literal` flag from the line editor state to the overlay paint. Options:

**Option A (lighter):** set a transient flag on the plugin instance while the line editor is open:

```lua
self._live_edit_mode = true  -- set when format_dialog is created
-- ... and ...
self._live_edit_mode = nil   -- clear when dialog is closed (in all three close paths)
```

Then in `bookends_overlay_widget.lua`, where it calls `Tokens.expand(...)`, pass `opts = { legacy_literal = self.plugin._live_edit_mode }`.

**Option B:** leave live preview resolving legacy tokens — accept the `%A` flicker in live preview, rely on the canonicalise-on-open to ensure users don't usually encounter legacy tokens in the editor at all.

Given the Q&A in the spec settled on **strict live-preview literal** for legacy tokens, implement Option A.

**Detailed steps for Option A:**

Find the `format_dialog = InputDialog:new{...}` construction in `bookends_line_editor.lua` (around line 385). **Immediately before**, set the flag:

```lua
self._live_edit_mode = true
```

Find the three close paths. Grep:

```bash
grep -n "UIManager:close(format_dialog)" bookends_line_editor.lua
```

Before each `UIManager:close(format_dialog)` call, add:

```lua
self._live_edit_mode = nil
```

Also in the `edited_callback` and at the top of any deferred callback that might fire after close, guard on it. There's also a `restoreMenu()` pattern near line 366 — after the close+restoreMenu sequence, clearing `_live_edit_mode` is sufficient.

- [ ] **Step 4: Thread the flag into overlay paint**

Open `bookends_overlay_widget.lua`. Grep for `Tokens.expand`:

```bash
grep -n "Tokens.expand\|Tokens.expandPreview" bookends_overlay_widget.lua
```

At every call site that participates in live rendering (there are typically 2–4, in the paint path), add the `opts` argument:

```lua
local result, is_empty, bar_info = Tokens.expand(
    line_text, ui, session_elapsed, session_pages_read,
    false, tick_width_multiplier, symbol_color, paint_ctx,
    { legacy_literal = plugin and plugin._live_edit_mode or false }
)
```

The `plugin` reference in the overlay widget is typically `self.plugin` or `self.bookends` — follow whatever convention the existing code uses for plugin access. If the overlay doesn't currently hold a plugin reference, use the pattern of any other field that threads through it. (Worst case, add a new field `self.live_edit_mode` updated by the line editor when it opens/closes — same end effect, cleaner coupling.)

- [ ] **Step 5: Syntax check + run tests**

Run: `luac -p bookends_line_editor.lua bookends_overlay_widget.lua bookends_tokens.lua && lua _test_tokens.lua && lua _test_conditionals.lua`

Expected: syntax clean. Unit tests still pass (they don't exercise the line editor directly).

- [ ] **Step 6: Commit**

```bash
git add bookends_line_editor.lua bookends_overlay_widget.lua
git commit -m "feat(line-editor): canonicaliseLegacy on open + legacy_literal live preview"
```

---

## Task 13: Rewrite `menu/token_picker.lua`

**Files:**
- Modify: `menu/token_picker.lua`.

**Purpose:** The picker is users' primary discovery surface for tokens. v5 names only. No legacy tokens in the picker; aliases are a runtime compatibility detail, not a documented feature.

- [ ] **Step 1: Read the current file structure**

```bash
cat menu/token_picker.lua
```

Observe the nested-category structure (outer table of `{ _("Category"), { { "%token", _("desc") }, ... } }`).

- [ ] **Step 2: Replace the file contents**

Write the full v5 token list. Categories preserved, tokens rewritten:

```lua
local _ = require("bookends_i18n").gettext

-- v5 token picker: descriptive names only. Legacy single-letter tokens still
-- resolve at runtime via the alias table in bookends_tokens.lua, but they are
-- not documented surface and not inserted by the picker.
return {
    { _("Metadata"), {
        { "%title", _("Document title") },
        { "%author", _("Author(s)") },
        { "%series", _("Series with index (combined)") },
        { "%series_name", _("Series name only") },
        { "%series_num", _("Series number only") },
        { "%chap_title", _("Chapter title (deepest)") },
        { "%chap_title_1", _("Chapter title at depth 1") },
        { "%chap_title_2", _("Chapter title at depth 2") },
        { "%chap_title_3", _("Chapter title at depth 3") },
        { "%chap_num", _("Current chapter number") },
        { "%chap_count", _("Total chapter count") },
        { "%filename", _("File name") },
        { "%lang", _("Book language") },
        { "%format", _("Document format (EPUB, PDF, etc.)") },
        { "%highlights", _("Number of highlights") },
        { "%notes", _("Number of notes") },
        { "%bookmarks", _("Number of bookmarks") },
        { "%annotations", _("Total annotations (bookmarks + highlights + notes)") },
    }},
    { _("Page / progress"), {
        { "%page_num", _("Current page number") },
        { "%page_count", _("Total pages") },
        { "%book_pct", _("Book percentage read") },
        { "%chap_pct", _("Chapter percentage read") },
        { "%chap_read", _("Pages read in chapter") },
        { "%chap_pages", _("Total pages in chapter") },
        { "%chap_pages_left", _("Pages left in chapter") },
        { "%pages_left", _("Pages left in book") },
    }},
    { _("Progress bars"), {
        { "%bar", _("Progress bar (configure type in line editor)") },
        { "%bar{100}", _("Fixed-width progress bar (100px)") },
        { "%bar{v10}", _("Progress bar, 10px tall") },
        { "%bar{100v10}", _("Progress bar, 100px × 10px") },
    }},
    { _("Time / date"), {
        { "%time", _("Current time (24h, same as %time_24h)") },
        { "%time_12h", _("Current time (12-hour)") },
        { "%time_24h", _("Current time (24-hour)") },
        { "%date", _("Short date (e.g. 23 Apr)") },
        { "%date_long", _("Long date (e.g. 23 April 2026)") },
        { "%date_numeric", _("Numeric date (dd/mm/yyyy)") },
        { "%weekday", _("Weekday name (e.g. Thursday)") },
        { "%weekday_short", _("Short weekday (e.g. Thu)") },
        { "%datetime{%d %B}", _("Custom date/time format (strftime spec)") },
        { "%chap_time_left", _("Estimated time left in chapter") },
        { "%book_time_left", _("Estimated time left in book") },
    }},
    { _("Session / reading"), {
        { "%session_time", _("Session reading time") },
        { "%session_pages", _("Pages read this session") },
        { "%speed", _("Reading speed (pages/hour)") },
        { "%book_read_time", _("Total time spent reading this book") },
    }},
    { _("Device"), {
        { "%batt", _("Battery level (percentage)") },
        { "%batt_icon", _("Battery level (icon)") },
        { "%wifi", _("Wi-Fi status (icon)") },
        { "%light", _("Frontlight intensity") },
        { "%warmth", _("Frontlight warmth") },
        { "%invert", _("Page-turn-inverted indicator") },
        { "%mem", _("System memory usage (percentage)") },
        { "%ram", _("KOReader process RAM usage (MB)") },
        { "%disk", _("Free disk space (GB)") },
    }},
}
```

- [ ] **Step 3: Syntax check**

Run: `luac -p menu/token_picker.lua`

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add menu/token_picker.lua
git commit -m "refactor(picker): rewrite token picker to v5 vocabulary"
```

---

## Task 14: Update `.pot` template + all `.po` files

**Files:**
- Modify: `locale/bookends.pot`.
- Modify: `locale/bg_BG/LC_MESSAGES/bookends.po`, `de/`, `es/`, `fr/`, `it/`, `pt_BR/`.

**Purpose:** New strings introduced by Task 13 need translation placeholders. Per `reference_translation.md` memory, dispatch parallel agents for the 6 non-English translations.

- [ ] **Step 1: Regenerate `.pot` from source**

Identify the xgettext invocation used by this project. Check for an existing script:

```bash
ls tools/ | grep -i i18n
ls tools/ | grep -i pot
cat tools/*.sh 2>/dev/null | head -30
```

If there's a script (e.g. `tools/update-pot.sh`), run it. Otherwise, use xgettext directly:

```bash
xgettext --from-code=UTF-8 --language=Lua \
    --keyword=_ --keyword=N_:1,2 \
    --output=locale/bookends.pot \
    main.lua bookends_*.lua menu/*.lua preset_*.lua
```

- [ ] **Step 2: Diff the `.pot`**

```bash
git diff locale/bookends.pot | head -60
```

Confirm the new msgids include:
- `Series with index (combined)`
- `Series name only`
- `Series number only`
- `Current time (24h, same as %time_24h)`
- `Custom date/time format (strftime spec)`
- Any depth/description adjustments.

Also expect some msgids to be **removed** (for tokens that no longer exist by name: `%C`, `%C1`, `%S`, etc. — their descriptions rename under new associations, which means msgids stay but the context changes). xgettext will report the line numbers pointing to the new identifiers; no cleanup needed on existing translations.

- [ ] **Step 3: Dispatch parallel translation agents for 6 languages**

Per memory's `reference_translation.md` workflow, launch 6 agents in parallel (one per `.po` file). Prompt template:

> "The `bookends.koplugin` project has added new translation strings for its v5 token system update. Please translate the new/modified `msgid` entries into `<LANG>` in `locale/<CODE>/LC_MESSAGES/bookends.po`. See the recent commits on branch v5-tokens for context. Run `msgfmt -c --statistics locale/<CODE>/LC_MESSAGES/bookends.po` to verify validity. Follow existing translation tone; don't add/edit the `Last-Translator:` header. Commit the file with a message like 'i18n(<CODE>): translate v5 token picker strings'. Focus on placeholder adjacency (`%series_num` must stay literal; `strftime spec` may be rendered naturally in the target language)."

Languages: `bg_BG`, `de`, `es`, `fr`, `it`, `pt_BR`.

- [ ] **Step 4: Verify all `.po` files compile**

```bash
for po in locale/*/LC_MESSAGES/bookends.po; do
    echo "=== $po ==="
    msgfmt -c --statistics "$po" 2>&1 | tail -3
done
```

Expected: all report "0 fatal errors" and a translated/fuzzy/untranslated count.

- [ ] **Step 5: Commit (if not already done by parallel agents)**

```bash
git add locale/
git commit -m "i18n(v5): translate new token picker strings across all locales"
```

---

## Task 15: Rewrite `README.md` token sections

**Files:**
- Modify: `README.md`.

**Purpose:** Documented surface switches to v5 names exclusively. Legacy aliases are a runtime compatibility detail, not a documented grammar.

- [ ] **Step 1: Locate the token reference section**

```bash
grep -n "^## Tokens\|^### Tokens\|%T\|%A\|%J" README.md | head -20
```

- [ ] **Step 2: Rewrite the token table**

Replace the legacy token reference table with a v5 table that mirrors `menu/token_picker.lua` categorisation. For each table, columns: **Token**, **Output**, **Example**.

Include a short intro paragraph **before** the table:

```markdown
## Tokens

Tokens are short markers that expand to live reader state when your format string is rendered. Type them directly into a line, or pick from the token menu in the line editor.

All tokens below use the v5 descriptive vocabulary. Older one-letter tokens like `%A` or `%J` still work — your existing presets don't need changing — but when you open an existing preset in the editor, they'll be rewritten to the new names so you can see what they mean at a glance.

Custom date and time formats use `%datetime{spec}`, which accepts any [strftime spec](https://strftime.net/). Example: `%datetime{%d %B}` → "23 April". For the common cases, use the fixed tokens like `%date` and `%time`.
```

Then the tables, one per category (Metadata, Page / progress, Progress bars, Time / date, Session, Device), using the same rows as `menu/token_picker.lua`.

- [ ] **Step 3: Update the conditional-token examples**

Grep for `[if:` in the README:

```bash
grep -n "\[if:" README.md
```

If any examples use legacy predicate names (`[if:chapters>10]`, `[if:chapter_title]`), update to v5 names (`[if:chap_count>10]`, `[if:chap_title]`). Keep the example alongside a sentence noting legacy names still work:

```markdown
> Legacy predicate names (`chapters`, `chapter_pct`, `chapter_title`, `percent`, `pages`) still evaluate — they're aliased to their v5 equivalents automatically.
```

- [ ] **Step 4: Verify README renders (local preview)**

```bash
grep -c "%title\|%author\|%chap_count" README.md
```

Expected: multiple hits.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README token sections to v5 vocabulary"
```

---

## Task 16: Create `docs/release-notes-5.0.0.md`

**Files:**
- Create: `docs/release-notes-5.0.0.md`.

**Purpose:** User-facing release narrative. Tone: focus on what the user experiences, not internal mechanics.

- [ ] **Step 1: Draft release notes**

Write `docs/release-notes-5.0.0.md`:

```markdown
# Bookends v5.0.0 — release notes

v5 is a big spring-clean of how tokens are named. The tokens you type into a
line now read like English — `%author` instead of `%A`, `%chap_count` instead
of `%J`, `%book_pct` instead of `%p`. Presets you already have keep working:
the old one-letter names still resolve on your device. Open an existing
preset in the line editor and you'll watch the old codes get rewritten to
the new names right in front of you, so you can see what each one means.

## What's new

- **Readable tokens.** All 45-ish tokens have descriptive names aligned with
  the conditional system, so `%author` and `[if:author]` speak the same
  language. See the README for the full list. Your existing presets are
  untouched on disk — the new names just show up in the editor when you open
  them.

- **Custom date formats.** New `%datetime{…}` token accepts any strftime spec.
  - `%datetime{%d %B}` → "23 April"
  - `%datetime{%A, %d %B}` → "Thursday, 23 April"
  - `%datetime{%I:%M %p}` → "7:42 PM"

  If you need a cheatsheet of strftime codes,
  [strftime.net](https://strftime.net/) is the friendliest one. Plain
  `%time`, `%date`, and `%weekday` still give you the familiar defaults.

- **Series split.** `%series` still shows "Foundation #2" combined. New
  `%series_name` and `%series_num` give you the parts separately when you
  want custom layout.

- **Line editor only shows v5 names while typing.** Mid-word typing like
  `%chap_num` no longer flickers through old meanings when you pass through
  `%c`. Legacy tokens stay literal in live preview; they resolve normally
  once your preset is rendered on the device.

## Compatibility

- Existing presets (yours and gallery) render identically. No action required.
- Conditional predicates: `[if:chapters>10]` still works; `[if:chap_count>10]`
  is the canonical form.
- Presets you edit and save in v5 use the new names in their stored form.
  If you share such a preset file with someone still on Bookends v4, they
  won't recognise the new names — that's a one-way migration. Older plugin
  versions continue to read their own presets fine.
```

- [ ] **Step 2: Commit**

```bash
git add docs/release-notes-5.0.0.md
git commit -m "docs: add v5.0.0 release notes"
```

---

## Task 17: Bump version to 5.0.0 in `_meta.lua`

**Files:**
- Modify: `_meta.lua`.

**Purpose:** Signal the version jump. No intermediate RC — the refactor is internally tested and gallery-preset-backed-up via the alias path.

- [ ] **Step 1: Update version string**

Open `_meta.lua`. Change:

```lua
    version = "4.4.0",
```

To:

```lua
    version = "5.0.0",
```

- [ ] **Step 2: Verify no other versioned references need updating**

```bash
grep -rn "4.4.0\|v4.4" --include="*.lua" --include="*.md" .
```

Expected: hits in historical release notes (`docs/release-notes-4.4.0.md`) and commit messages — those stay. If any runtime string or config mentions "4.4", update to "5.0".

- [ ] **Step 3: Commit**

```bash
git add _meta.lua
git commit -m "chore: v5.0.0"
```

---

## Task 18: Manual device verification

**Files:** none.

**Purpose:** Plugin behaviour on an actual Kindle, since a class of bugs lives at the KOReader runtime boundary (fonts, paint cycles, settings persistence) that pure-Lua tests can't catch.

- [ ] **Step 1: Push to device**

```bash
cd /home/andyhazz/projects/bookends.koplugin && \
tar --exclude=tools --exclude=.git --exclude='_test_*.lua' --exclude='docs' -cf - . \
  | ssh kindle "cd /mnt/us/koreader/plugins/bookends.koplugin && tar -xf -"
```

- [ ] **Step 2: Restart KOReader on device**

User action: restart KOReader on the Kindle. (SIGHUP does not reload — the process must be fully restarted.)

- [ ] **Step 3: Verification checklist**

Confirm on device:

- [ ] Existing gallery preset using `%A` and `%J` still renders authors and chapter count correctly.
- [ ] Create a new line with `%author` — renders author name.
- [ ] Create a new line with `%datetime{%d %B}` — renders e.g. "23 April".
- [ ] Create a new line with `%datetime{%I:%M %p}` — renders 12-hour clock with AM/PM.
- [ ] Open an existing `%A`-containing preset in the line editor — InputDialog shows `%author` (not `%A`).
- [ ] While typing a new line, `%c` stays as literal `%c` in the visible preview region; `%chap_num` resolves to the current chapter number once fully typed.
- [ ] A line with `[if:chapters>0]Chapter %chap_num of %chap_count[/if]` renders correctly.
- [ ] A line with `[if:chap_count>0]Chapter %chap_num of %chap_count[/if]` renders correctly.
- [ ] Token picker menu shows all v5 names, no single-letter codes.

- [ ] **Step 4: Capture a screenshot with the kindle-screenshot skill**

Use the `kindle-screenshot` skill to grab a reference screenshot of the token picker and one rendered preset.

- [ ] **Step 5: If all checks pass, tag the release**

Wait for explicit user confirmation before tagging. Once confirmed:

```bash
git tag -a v5.0.0 -m "v5.0.0 — readable tokens, %datetime, series split"
git push origin v5.0.0
```

**Note:** per project memory, GitHub releases require attaching the plugin `.zip` asset so the updates manager can fetch it. After `git push origin v5.0.0`, create the GitHub release via:

```bash
cd /home/andyhazz/projects/bookends.koplugin && \
zip -r /tmp/bookends.koplugin-v5.0.0.zip . \
    -x '.git/*' 'tools/submit-worker/node_modules/*' '_test_*.lua' 'docs/*'
gh release create v5.0.0 /tmp/bookends.koplugin-v5.0.0.zip \
    --title "v5.0.0 — readable tokens" \
    --notes-file docs/release-notes-5.0.0.md
```

---

## Self-review

Checked against the spec (2026-04-23-v5-token-system-design.md):

- **Scope item 1 (descriptive vocabulary):** Tasks 2 (alias table), 9 (replace-table re-key).
- **Scope item 2 (legacy functional forever):** Tasks 2 (TOKEN_ALIAS), 3 (STATE_ALIAS), 9 (alias rewrite wired in).
- **Scope item 3 (%datetime escape hatch):** Task 7.
- **Scope item 4 (series split):** Task 10.
- **Scope item 5 (unified brace grammar):** Task 6.
- **Scope item 6 (line-editor behaviour):** Tasks 11, 12.
- **Scope item 7 (state-key aliases):** Task 3.
- **Scope item 8 (token picker):** Task 13.
- **Scope item 9 (README):** Task 15.
- **Scope item 10 (release notes):** Task 16.
- **Scope item 11 (tests):** Tasks 1, 2, 3, 4, 6, 7, 8, 9, 10, 11.

Also: version bump (Task 17), i18n (Task 14), device verification (Task 18).

**Placeholder scan:** none of the steps contain TBD/TODO/"similar to"/"handle edge cases" placeholders. Every step has concrete code or exact commands.

**Type consistency check:** `TOKEN_ALIAS` and `STATE_ALIAS` are referenced consistently as module-locals in Task 2/3 and reused in Tasks 4, 9, 11 by name. `rewriteLegacyTokens` is used by `Tokens.canonicaliseLegacy` (Task 4) and inside `Tokens.expand` (Task 9). `Tokens.expand` gains the `opts` parameter in Task 11; `Tokens.expandPreview` in the same task — both signatures match their call sites in Task 12.

**Known task that's a no-op (Task 5):** retained for numbering continuity; the alias-pass wiring was folded into Task 9 for atomicity (the wiring and re-keying must land together).
