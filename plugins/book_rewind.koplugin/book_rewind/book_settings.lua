-- What KOReader keeps in each book's settings and the statistics do not: stable page numbers and the book
-- status (finished, and when). The statistics have no file path, so books are found through KOReader's
-- reading history, and matched to the statistics by the partial MD5 the settings keep.
local BookSettings = {}

local KEYS = {
    "partial_md5_checksum", "pagemap_use_page_labels", "pagemap_doc_pages", "summary", "percent_finished", "doc_props",
    "doc_pages",
}

local function read_entry(doc_settings, file)
    local values = {}
    for _, key in ipairs(KEYS) do
        values[key] = doc_settings:readSetting(key)
    end
    local summary = type(values.summary) == "table" and values.summary or {}
    local props = type(values.doc_props) == "table" and values.doc_props or {}
    return {
        md5 = type(values.partial_md5_checksum) == "string" and values.partial_md5_checksum or nil,
        file = file,
        pagemap_use_page_labels = values.pagemap_use_page_labels,
        pagemap_doc_pages = values.pagemap_doc_pages,
        status = summary.status,
        modified = summary.modified,
        percent = tonumber(values.percent_finished),
        title = type(props.title) == "string" and props.title ~= "" and props.title or nil,
        authors = type(props.authors) == "string" and props.authors ~= "" and props.authors or nil,
        doc_pages = tonumber(values.doc_pages),
    }
end

-- One entry for each book opened since `since` (only those can hold a book read in the year), as
-- { md5, file, pagemap_use_page_labels, pagemap_doc_pages, status, modified, percent, title, authors, doc_pages }.
-- opts, for tests: history (a list of { file, time }), open (a function from a file path to its settings), current
-- (the settings of the book open now, newer than the file on disk, with its file path in current_file) and help_dir
-- (KOReader's own help folder, whose quick start guide is no book).
function BookSettings.collect(since, opts)
    opts = opts or {}
    local help_dirs = {}
    if opts.help_dir then
        help_dirs[1] = opts.help_dir
    else
        local ok, DataStorage = pcall(require, "datastorage")
        if ok then
            local dir = DataStorage:getDataDir() .. "/help"
            help_dirs[1] = dir .. "/"
            -- The history keeps real paths, which differ from the data folder when it is reached through a link.
            local real_ok, real = pcall(function() return require("ffi/util").realpath(dir) end)
            if real_ok and type(real) == "string" then
                help_dirs[2] = real .. "/"
            end
        end
    end
    local function is_help(file)
        if type(file) ~= "string" then
            return false
        end
        for _, dir in ipairs(help_dirs) do
            if file:sub(1, #dir) == dir then
                return true
            end
        end
        return false
    end
    local entries, seen = {}, {}
    local function add(ok, entry)
        if ok and entry.md5 and not seen[entry.md5] then
            seen[entry.md5] = true
            entries[#entries + 1] = entry
        end
    end
    if opts.current and not is_help(opts.current_file) then
        add(pcall(read_entry, opts.current, opts.current_file))
    end
    -- KOReader keeps the history in memory; reloading it could rewrite the file, so it is only read.
    local history = opts.history or require("readhistory").hist
    local open = opts.open or function(file) return require("docsettings"):open(file) end
    for _, item in ipairs(history or {}) do
        if type(item) == "table" and type(item.file) == "string" and (item.time or 0) >= since and not is_help(item.file) then
            add(pcall(function() return read_entry(open(item.file), item.file) end))
        end
    end
    return entries
end

return BookSettings
