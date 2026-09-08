--[[
Shared book-count helpers for pagetextinfo.koplugin.
Counts come from _G.all_files (status per book), kept in memory by the
main app — no disk I/O needed here.
]]

-- Status -> bucket mapping for _G.all_files entries.
-- "reading" maps directly; "tbr"/"mbr" map directly; "complete" -> finished;
-- anything else (nil, "", "new", unrecognised) counts as unread.
local function bucketFor(status)
    if status == "reading" then return "reading" end
    if status == "tbr"     then return "tbr" end
    if status == "mbr"     then return "mbr" end
    if status == "complete" then return "finished" end
    return "unread"
end

local M = {}

-- Returns total (number) and counts (table keyed by bucket id).
function M.getCounts()
    local total = 0
    local counts = { reading = 0, unread = 0, tbr = 0, mbr = 0, finished = 0 }
    if _G.all_files then
        for _, info in pairs(_G.all_files) do
            total = total + 1
            local bucket = bucketFor(info and info.status)
            counts[bucket] = counts[bucket] + 1
        end
    end
    return total, counts
end

-- Books marked finished/complete during the current calendar month.
-- Relies on last_modified_year/month being stamped whenever the status
-- is committed (see BookshelfWidget:_commitBookStatus).
function M.getFinishedThisMonth()
    local count = 0
    if _G.all_files then
        local now_year  = os.date("%Y")
        local now_month = os.date("%m")
        for _, info in pairs(_G.all_files) do
            if info then
                local bucket = bucketFor(info.status)
                if bucket == "finished"
                        and info.last_modified_year == now_year
                        and info.last_modified_month == now_month then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- Convenience for callers that only want the grand total.
function M.getTotalBooks()
    local total = M.getCounts()
    return total
end

M.bucketFor = bucketFor

return M
