-- Page totals in KOReader's stable page numbers (publisher pages or characters per page), for the books where
-- the reader turned them on. The book settings come from BookSettings.collect.
local StablePages = {}

-- The stable total of a book, from its settings, only when the reader uses stable page numbers in it.
function StablePages.total(settings)
    if type(settings) ~= "table" or settings.pagemap_use_page_labels ~= true then
        return nil
    end
    local pages = settings.pagemap_doc_pages
    if type(pages) ~= "number" or pages < 1 or pages ~= math.floor(pages) then
        return nil
    end
    return pages
end

-- { [md5] = stable total } for the entries with one.
function StablePages.totals(entries)
    local totals = {}
    for _, entry in ipairs(entries or {}) do
        local total = entry.md5 and StablePages.total(entry)
        if total then
            totals[entry.md5] = total
        end
    end
    return totals
end

-- books: { [id] = { md5, pages, ... } }, as the store loads them. totals: { [md5] = stable total }.
-- The screen total stays in screen_pages. Returns how many books changed.
function StablePages.apply(books, totals)
    local changed = 0
    for _, book in pairs(books or {}) do
        local total = book.md5 and totals[book.md5]
        if total then
            book.screen_pages = book.pages
            book.pages = total
            book.stable_pages = true
            changed = changed + 1
        end
    end
    return changed
end

return StablePages
