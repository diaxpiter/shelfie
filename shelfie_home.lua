--[[--
Shelfie home screen: the full-screen reading dashboard.

Layout (top to bottom), mirroring the "Reading Dashboard" mockup:
  date · time · battery
  Keep-reading card (cover, title, progress, Continue, ring)
  Stats tiles (streak · today vs goal · books this year)
  Recently added (4 covers)
  Bottom tab bar (Home · Library · Stats · Tags · Settings)
--]]

local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")

local Data = require("shelfie_data")
local W = require("shelfie_widgets")

local px = W.px

local Home = InputContainer:extend{
    name = "shelfie_home",
    covers_fullscreen = true,
    plugin = nil,   -- the Shelfie plugin instance (settings, actions)
}

function Home:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if not W.fonts_ready then
        pcall(W.setupFonts, self.plugin.path)
        W.fonts_ready = true
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:build()
end

function Home:icon(name, size)
    return IconWidget:new{
        file = self.plugin.path .. "/icons/" .. name .. ".svg",
        width = px(size), height = px(size), alpha = true,
    }
end

-- Fixed-width column: a horizontal span forces the group's width.
local function column(width, align, items)
    local group = VerticalGroup:new{ align = align or "left", HorizontalSpan:new{ width = width } }
    for _, item in ipairs(items) do table.insert(group, item) end
    return group
end

local function vspan(n) return VerticalSpan:new{ width = px(n) } end
local function hspan(n) return HorizontalSpan:new{ width = px(n) } end

function Home:build()
    -- Free a previous build before rebuilding.
    if self[1] then self[1]:free() end
    if self[2] then self[2]:free() end

    local sw = self.dimen.w
    local margin = px(22)
    local cw = sw - 2 * margin
    local plugin = self.plugin

    local current = Data.currentBook()
    local stats = Data.readingStats()
    local finished = Data.finishedThisYear()
    local recent = Data.recentlyAdded(12, current and current.file)
    -- The tab bar is built first: its height decides how many cover rows fit.
    self[2] = self:buildNav("home")
    self.current = current

    local content = VerticalGroup:new{ align = "left" }

    -- 1. Status row --------------------------------------------------------
    local powerd = Device:getPowerDevice()
    local right = os.date("%H:%M")
    if Device:hasBattery() then
        right = right .. "  ·  " .. powerd:getCapacity() .. "%"
    end
    local left_w = W.text(os.date("%a, %d %b"), W.FONT_SANS_BOLD, 12)
    local right_w = W.text(right, W.FONT_SANS_BOLD, 12)
    table.insert(content, vspan(16))
    table.insert(content, HorizontalGroup:new{
        left_w,
        HorizontalSpan:new{ width = cw - left_w:getSize().w - right_w:getSize().w },
        right_w,
    })
    table.insert(content, vspan(14))

    -- 2. Keep-reading card -------------------------------------------------
    local border, pad = math.max(1, px(2)), px(16)
    local cover_w, cover_h, ring_d = px(92), px(136), 78
    local text_w = cw - 2 * border - 2 * pad - cover_w - px(ring_d) - 2 * px(16)
    local card_inner
    if current then
        local percent = current.percent or 0
        local mins = Data.minutesLeft(current)
        local detail
        if current.pages then
            detail = T(_("Page %1 of %2"), math.max(1, math.floor(current.pages * percent + 0.5)), current.pages)
        else
            detail = current.authors or ""
        end
        if mins then detail = detail .. " · " .. T(_("%1 min left"), mins) end

        local continue = W.Tappable:new{
            callback = function() plugin:openBook(current.file) end,
            FrameContainer:new{
                background = W.BLACK, bordersize = 0, radius = px(16),
                padding = 0, padding_left = px(16), padding_right = px(16),
                padding_top = px(7), padding_bottom = px(7),
                W.text(_("Continue") .. " →", W.FONT_SANS_BOLD, 13, { color = W.WHITE }),
            },
        }
        card_inner = HorizontalGroup:new{
            align = "center",
            W.cover(current, cover_w, cover_h, 4),
            hspan(16),
            column(text_w, "left", {
                W.text(_("KEEP READING"), W.FONT_SANS_BOLD, 11, { color = W.MUTED }),
                vspan(4),
                W.textbox(current.title, W.FONT_SERIF_BOLD, 21, text_w, { height = px(56) }),
                vspan(2),
                W.text(detail, W.FONT_SANS, 12, { color = W.MUTED, max_width = text_w }),
                vspan(10),
                continue,
            }),
            hspan(16),
            W.Ring:new{ size = ring_d, percent = percent },
        }
    else
        card_inner = column(cw - 2 * border - 2 * pad, "left", {
            W.text(_("KEEP READING"), W.FONT_SANS_BOLD, 11, { color = W.MUTED }),
            vspan(6),
            W.textbox(_("Nothing in progress yet. Pick something from your library!"),
                W.FONT_SERIF_BOLD, 18, cw - 2 * border - 2 * pad),
            vspan(10),
            W.Tappable:new{
                callback = function() plugin:showLibrary() end,
                FrameContainer:new{
                    background = W.BLACK, bordersize = 0, radius = px(16), padding = 0,
                    padding_left = px(16), padding_right = px(16), padding_top = px(7), padding_bottom = px(7),
                    W.text(_("Open library") .. " →", W.FONT_SANS_BOLD, 13, { color = W.WHITE }),
                },
            },
        })
    end
    local card = FrameContainer:new{
        background = W.WHITE, bordersize = border, radius = px(22), padding = pad,
        card_inner,
    }
    if current then
        card = W.Tappable:new{ callback = function() plugin:openBook(current.file) end, card }
    end
    table.insert(content, card)
    table.insert(content, vspan(12))

    -- 3. Stats tiles -------------------------------------------------------
    local gap = px(10)
    local tile_w = math.floor((cw - 2 * gap) / 3)
    local tpad = px(12)
    local tinner = tile_w - 2 * tpad - 2 * border
    local goal = plugin:getDailyGoal()
    local function tile(dark, items, callback)
        local frame = FrameContainer:new{
            background = dark and W.BLACK or W.WHITE,
            bordersize = border, radius = px(18), padding = tpad,
            column(tinner, "left", items),
        }
        return W.Tappable:new{ callback = callback, frame }
    end
    local show_stats = function() plugin:showStats() end
    local tiles = HorizontalGroup:new{
        align = "top",
        tile(true, {
            self:icon("flame.white", 22),
            W.text(tostring(stats.streak), W.FONT_SANS_BOLD, 26, { color = W.WHITE }),
            W.text(stats.streak == 1 and _("day streak") or _("days streak"), W.FONT_SANS_BOLD, 11, { color = W.WHITE }),
        }, show_stats),
        HorizontalSpan:new{ width = gap },
        tile(false, {
            self:icon("clock", 22),
            HorizontalGroup:new{
                align = "bottom",
                W.text(tostring(stats.today_min), W.FONT_SANS_BOLD, 26),
                W.text("/" .. goal .. "m", W.FONT_SANS_BOLD, 14),
            },
            vspan(3),
            W.Bar:new{ width = tinner, percent = stats.today_min / math.max(1, goal) },
        }, function() plugin:editDailyGoal() end),
        HorizontalSpan:new{ width = gap },
        tile(false, {
            self:icon("books", 22),
            W.text(tostring(finished), W.FONT_SANS_BOLD, 26),
            W.text(T(_("books in %1"), os.date("%Y")), W.FONT_SANS_BOLD, 11),
        }, show_stats),
    }
    table.insert(content, tiles)
    table.insert(content, vspan(16))

    -- 4. Recently added ----------------------------------------------------
    if #recent > 0 then
        local head_l = W.text(_("Recently added"), W.FONT_SANS_BOLD, 15)
        local head_r = W.Tappable:new{
            callback = function() plugin:showLibrary() end,
            W.text(_("See all"), W.FONT_SANS_BOLD, 12, { color = W.MUTED }),
        }
        table.insert(content, HorizontalGroup:new{
            align = "bottom",
            head_l,
            HorizontalSpan:new{ width = cw - head_l:getSize().w - head_r:getSize().w },
            head_r,
        })
        table.insert(content, vspan(8))
        local rgap = px(10)
        -- Pick the grid (3-6 columns, 1+ rows) whose covers fill the space
        -- above the tab bar best. Small screens get fewer, bigger covers.
        local avail = self.dimen.h - self[2]:getSize().h - px(8) - px(14)
        -- Measure the column so far. VerticalGroup caches its layout on the first
        -- getSize(), so drop the cache again: we're still adding children.
        local used = content:getSize().h
        content._size = nil
        local space = avail - used
        local best
        for cols = 3, 6 do
            local bw = math.floor((cw - (cols - 1) * rgap) / cols)
            local bh = math.floor(bw * 1.5)
            local rows = math.floor((space + rgap) / (bh + rgap))
            if rows < 1 then -- shrink to the available height
                bh = space
                bw = math.floor(bh / 1.5)
                rows = 1
            end
            rows = math.min(rows, math.ceil(#recent / cols))
            local n = math.min(#recent, rows * cols)
            local score = n * bw * bh
            if bw >= px(70) and (not best or score > best.score) then
                best = { cols = cols, rows = rows, bw = bw, bh = bh, score = score }
            end
        end
        best = best or { cols = 4, rows = 1, bw = math.floor((cw - 3 * rgap) / 4) }
        best.bh = best.bh or math.floor(best.bw * 1.5)
        local col_gap = best.cols > 1
            and math.floor((cw - best.cols * best.bw) / (best.cols - 1)) or 0
        local shown = 0
        for r = 1, best.rows do
            local first = (r - 1) * best.cols + 1
            if first > #recent then break end
            if r > 1 then table.insert(content, VerticalSpan:new{ width = rgap }) end
            local row = HorizontalGroup:new{ align = "top" }
            for i = first, math.min(first + best.cols - 1, #recent) do
                local book = recent[i]
                if i > first then table.insert(row, HorizontalSpan:new{ width = col_gap }) end
                table.insert(row, W.Tappable:new{
                    callback = function() plugin:openBook(book.file) end,
                    hold_callback = function() plugin:bookActions(book.file, book.title) end,
                    W.cover(book, best.bw, best.bh, i),
                })
                shown = i
            end
            table.insert(content, row)
        end
        -- Release cover bitmaps of books that didn't fit.
        for i = shown + 1, #recent do
            if recent[i].cover_bb then recent[i].cover_bb:free(); recent[i].cover_bb = nil end
        end
    end

    -- Start background cover indexing for anything not cached yet.
    local books = { current }
    for _, b in ipairs(recent) do books[#books + 1] = b end
    if not self._index_requested and Data.indexMissingCovers(books, px(200), px(300)) then
        self._index_requested = true
        self:watchIndexing()
    end

    self[1] = HorizontalGroup:new{ HorizontalSpan:new{ width = margin }, content }
end

-- Shared by every Shelfie screen (Home, Library): `self` needs .plugin and .dimen.
function Home:buildNav(active_tab)
    local plugin = self.plugin
    local sw = self.dimen.w
    local tabs = {
        { "home", _("Home"), function() plugin:showHome() end },
        { "library", _("Library"), function() plugin:showLibrary() end },
        { "stats", _("Stats"), function() plugin:showStats() end },
        { "tags", _("Tags"), function() plugin:showCollections() end },
        { "settings", _("Settings"), function() plugin:showMenu() end },
    }
    local side = px(10)
    local tab_w = math.floor((sw - 2 * side) / #tabs)
    local row = HorizontalGroup:new{ HorizontalSpan:new{ width = side } }
    for _, t in ipairs(tabs) do
        local active = t[1] == (active_tab or "home")
        local fg = active and W.WHITE or W.BLACK
        local inner = column(tab_w - 2 * px(4), "center", {
            vspan(6),
            self:icon(active and (t[1] .. ".white") or t[1], 22),
            vspan(3),
            W.text(t[2], W.FONT_SANS_BOLD, 10, { color = fg }),
            vspan(6),
        })
        table.insert(row, W.Tappable:new{
            callback = t[3],
            FrameContainer:new{
                background = active and W.BLACK or nil,
                bordersize = 0, radius = px(14), padding = 0, margin = px(4),
                inner,
            },
        })
    end
    return row
end

function Home:paintTo(bb, x, y)
    local w, h = self.dimen.w, self.dimen.h
    -- Paper background with a subtle dot grid.
    bb:paintRect(x, y, w, h, W.PAPER)
    local step, dot = px(14), math.max(1, px(1.5))
    for yy = y + step, y + h, step do
        for xx = x + step, x + w, step do
            bb:paintRect(xx, yy, dot, dot, W.DOTS)
        end
    end
    -- Content from the top.
    self[1]:paintTo(bb, x, y)
    -- Tab bar pinned to the bottom, white with a top rule.
    local nav_h = self[2]:getSize().h + px(8)
    local ny = y + h - nav_h
    bb:paintRect(x, ny, w, nav_h, W.WHITE)
    bb:paintRect(x, ny, w, math.max(1, px(2)), W.BLACK)
    self[2]:paintTo(bb, x, ny + px(4))
end

function Home:refresh()
    self:build()
    UIManager:setDirty(self, "ui")
end

-- Poll the cover browser's background job, then redraw with real covers.
function Home:watchIndexing()
    if self._watching then return end
    self._watching = true
    local tries = 0
    local function check()
        tries = tries + 1
        if not self._shown then self._watching = false return end
        if Data.isIndexing() and tries < 30 then
            UIManager:scheduleIn(2, check)
        else
            self._watching = false
            logger.dbg("Shelfie: cover indexing finished, refreshing")
            self:build()
            UIManager:setDirty(self, "ui")
        end
    end
    UIManager:scheduleIn(2, check)
end

function Home:onShow()
    self._shown = true
    UIManager:setDirty(self, "full")
end

function Home:onCloseWidget()
    self._shown = false
    if self[1] then self[1]:free() end
    if self[2] then self[2]:free() end
    if self.plugin and self.plugin.screen == self then self.plugin.screen = nil end
end

function Home:onClose()
    UIManager:close(self)
    return true
end

-- Layout helpers shared with the Library screen.
Home.column = column
Home.vspan = vspan
Home.hspan = hspan

return Home
