--[[--
Shelfie data layer: everything the home screen shows, gathered from
KOReader's own sources (reading history, book sidecars, the cover
browser cache and the statistics database). Read-only: never writes.
--]]

local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local ReadHistory = require("readhistory")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local Data = {}

local STATS_DB = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

-- The cover browser plugin's cache. Optional: Shelfie works without it.
local function getBookInfoManager()
    local ok, bim = pcall(require, "bookinfomanager")
    if ok then return bim end
end

local function openStatsDb()
    if lfs.attributes(STATS_DB, "mode") ~= "file" then return end
    local ok, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok then return end
    local ok2, conn = pcall(SQ3.open, STATS_DB)
    if ok2 then return conn end
end

local function startOfToday()
    local t = os.date("*t")
    return os.time{ year = t.year, month = t.month, day = t.day, hour = 0 }
end

--- Title/author/progress for one book file. Never fails: falls back to the filename.
function Data.bookMeta(file, want_cover)
    local meta = { file = file }
    local _, filename = util.splitFilePathName(file)
    -- From the filename: drop extension and Amazon/Calibre ID suffixes, tidy separators.
    meta.title = filename:gsub("%.[^.]+$", ""):gsub("_[A-Z0-9]+$", ""):gsub("_", " ")

    if DocSettings:hasSidecarFile(file) then
        local ds = DocSettings:open(file)
        local props = ds:readSetting("doc_props") or {}
        if props.title and props.title ~= "" then meta.title = props.title end
        meta.authors = props.authors
        meta.percent = ds:readSetting("percent_finished")
        meta.pages = ds:readSetting("doc_pages")
            or (ds:readSetting("stats") or {}).pages
        meta.md5 = ds:readSetting("partial_md5_checksum")
        local summary = ds:readSetting("summary") or {}
        meta.status = summary.status or "reading"
        meta.modified = summary.modified
        meta.opened = true
    else
        meta.status = "new"
        meta.opened = false
    end

    local bim = getBookInfoManager()
    if bim then
        local ok, info = pcall(bim.getBookInfo, bim, file, want_cover)
        if ok and info then
            if info.title and info.title ~= "" and not meta.opened then meta.title = info.title end
            meta.authors = meta.authors or info.authors
            meta.pages = meta.pages or info.pages
            if want_cover and info.has_cover and not info.ignore_cover then
                meta.cover_bb = info.cover_bb
            end
            meta.indexed = info.cover_fetched == "Y" or info.unsupported ~= nil
        end
    end
    if meta.authors then
        meta.authors = meta.authors:gsub("\n.*", "") -- first author only
    end
    return meta
end

--- The book to "keep reading": the most recent history entry that still
-- exists and isn't finished.
function Data.currentBook()
    ReadHistory:reload()
    for _, item in ipairs(ReadHistory.hist) do
        if item.file and lfs.attributes(item.file, "mode") == "file" then
            local meta = Data.bookMeta(item.file, true)
            if meta.status ~= "complete" then
                return meta
            end
        end
    end
end

--- Estimated minutes left in a book, from its average time per page.
function Data.minutesLeft(meta)
    if not (meta and meta.pages and meta.percent) then return end
    local conn = openStatsDb()
    if not conn then return end
    local ok, read_time, read_pages = pcall(function()
        if meta.md5 then
            local t, p = conn:rowexec(string.format(
                "SELECT total_read_time, total_read_pages FROM book WHERE md5 = '%s' LIMIT 1",
                meta.md5:gsub("'", "")))
            if t then return t, p end
        end
        return conn:rowexec(string.format(
            "SELECT total_read_time, total_read_pages FROM book WHERE title = '%s' LIMIT 1",
            (meta.title or ""):gsub("'", "''")))
    end)
    conn:close()
    read_time, read_pages = tonumber(read_time), tonumber(read_pages)
    if not ok or not read_time or not read_pages or read_pages < 5 then return end
    local sec_per_page = read_time / read_pages
    local pages_left = meta.pages * (1 - meta.percent)
    return math.max(1, math.floor(pages_left * sec_per_page / 60 + 0.5))
end

--- Reading streak (consecutive days with reading, ending today or
-- yesterday) and minutes read today.
function Data.readingStats()
    local stats = { streak = 0, today_min = 0, available = false }
    local conn = openStatsDb()
    if not conn then return stats end
    local ok, err = pcall(function()
        local today = startOfToday()
        local secs = conn:rowexec(string.format(
            "SELECT sum(duration) FROM page_stat_data WHERE start_time >= %d", today))
        stats.today_min = math.floor((tonumber(secs) or 0) / 60)

        local days = {}
        local stmt = conn:prepare([[
            SELECT DISTINCT date(start_time, 'unixepoch', 'localtime') AS d
            FROM page_stat_data ORDER BY d DESC LIMIT 400]])
        for row in stmt:rows() do days[#days + 1] = row[1] end
        stmt:close()

        local day = os.time() -- walk backwards one day at a time
        local key = os.date("%Y-%m-%d", day)
        local i = 1
        if days[1] ~= key then -- not read yet today: streak may still end yesterday
            day = day - 86400
            key = os.date("%Y-%m-%d", day)
        end
        while days[i] == key do
            stats.streak = stats.streak + 1
            i = i + 1
            day = day - 86400
            key = os.date("%Y-%m-%d", day)
        end
        stats.available = true
    end)
    conn:close()
    if not ok then logger.warn("Shelfie: reading stats failed:", err) end
    return stats
end

--- Books marked finished this calendar year (from the reading history).
function Data.finishedThisYear()
    local year = os.date("%Y")
    local count = 0
    for _, item in ipairs(ReadHistory.hist) do
        if item.file and DocSettings:hasSidecarFile(item.file) then
            local summary = DocSettings:open(item.file):readSetting("summary")
            if summary and summary.status == "complete"
                and summary.modified and summary.modified:sub(1, 4) == year then
                count = count + 1
            end
        end
    end
    return count
end

--- The newest book files under the home folder (by file date), max depth 2.
function Data.recentlyAdded(limit, exclude_file)
    local home = G_reader_settings:readSetting("home_dir")
    if not home or lfs.attributes(home, "mode") ~= "directory" then return {} end
    local found = {}
    local function scan(dir, depth)
        for name in lfs.dir(dir) do
            if name ~= "." and name ~= ".." and not name:match("^%.") and not name:match("%.sdr$") then
                local path = dir .. "/" .. name
                local attr = lfs.attributes(path)
                if attr and attr.mode == "directory" and depth < 2 then
                    scan(path, depth + 1)
                elseif attr and attr.mode == "file" and path ~= exclude_file
                    and DocumentRegistry:hasProvider(path) and not name:match("%.sh$")
                    and not name:match("%.txt$") then
                    found[#found + 1] = { file = path, mtime = attr.modification }
                end
            end
        end
    end
    pcall(scan, home, 1)
    table.sort(found, function(a, b) return a.mtime > b.mtime end)
    local books = {}
    for i = 1, math.min(limit, #found) do
        books[i] = Data.bookMeta(found[i].file, true)
    end
    return books
end

--- Ask the cover browser to index books whose covers aren't cached yet.
-- Returns true when a background job was started.
function Data.indexMissingCovers(books, cover_w, cover_h)
    local bim = getBookInfoManager()
    if not bim or bim:isExtractingInBackground() then return false end
    local todo = {}
    for _, b in ipairs(books) do
        if b and not b.indexed then
            todo[#todo + 1] = {
                filepath = b.file,
                cover_specs = { max_cover_w = cover_w, max_cover_h = cover_h },
            }
        end
    end
    if #todo == 0 then return false end
    return bim:extractInBackground(todo) and true or false
end

function Data.isIndexing()
    local bim = getBookInfoManager()
    return bim and bim:isExtractingInBackground() or false
end

return Data
