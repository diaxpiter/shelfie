--[[--
Shelfie library screen: every book in the home folder as a cover grid,
with status filters, pages (tap the arrows or swipe) and the shared tab bar.
Tap a cover to read it, long-press for KOReader's book info.
--]]

local BD = require("ui/bidi")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local Data = require("shelfie_data")
local Home = require("shelfie_home")
local W = require("shelfie_widgets")

local px = W.px
local column, vspan = Home.column, Home.vspan

local FILTERS = {
    { "all", _("All") },
    { "reading", _("Reading") },
    { "new", _("New") },
    { "complete", _("Finished") },
}

local Library = InputContainer:extend{
    name = "shelfie_library",
    covers_fullscreen = true,
    plugin = nil,
    filter = "all",
    page = 1,
}

-- Same tab bar, background and cover-indexing watcher as the home screen.
Library.buildNav = Home.buildNav
Library.icon = Home.icon
Library.watchIndexing = Home.watchIndexing

function Library:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.NextPage = { { Device.input.group.PgFwd } }
        self.key_events.PrevPage = { { Device.input.group.PgBack } }
    end
    self.ges_events.Swipe = {
        GestureRange:new{ ges = "swipe", range = function() return self.dimen end },
    }
    self.filter = self.plugin.settings.library_filter or "all"
    self:build()
end

local function pill(text, active, callback)
    return W.Tappable:new{
        callback = callback,
        FrameContainer:new{
            background = active and W.BLACK or W.WHITE,
            color = W.BLACK, bordersize = math.max(1, px(1.5)), radius = px(14),
            padding = 0, padding_left = px(12), padding_right = px(12),
            padding_top = px(5), padding_bottom = px(5),
            W.text(text, W.FONT_SANS_BOLD, 12, { color = active and W.WHITE or W.BLACK }),
        },
    }
end

function Library:build()
    for i = 1, 3 do
        if self[i] then self[i]:free() end
    end
    self[3] = nil

    local plugin = self.plugin
    local sw = self.dimen.w
    local margin = px(22)
    local cw = sw - 2 * margin

    -- Either the whole library (with filters) or one collection (from Tags).
    local books, counts
    if self.collection then
        self[2] = self:buildNav("tags")
        books = Data.collectionBooks(self.collection)
        counts = { all = #books }
    else
        self[2] = self:buildNav("library")
        books, counts = Data.library(self.filter)
    end
    self.book_count = #books

    local content = VerticalGroup:new{ align = "left" }
    table.insert(content, vspan(18))

    -- Header: title, book count, and a way out (folders, or back to Tags).
    local title = W.text(self.collection and Data.collectionTitle(self.collection) or _("Library"),
        W.FONT_SERIF_BOLD, 28, { max_width = math.floor(cw * 0.6) })
    local count = W.text(T(_("%1 books"), counts.all), W.FONT_SANS_BOLD, 12, { color = W.MUTED })
    local action = self.collection
        and pill("‹ " .. _("Tags"), false, function() plugin:showCollections() end)
        or pill(_("Folders"), false, function() plugin:showFolders() end)
    local used = title:getSize().w + count:getSize().w + action:getSize().w + px(10)
    table.insert(content, HorizontalGroup:new{
        align = "center",
        title,
        HorizontalSpan:new{ width = px(10) },
        count,
        HorizontalSpan:new{ width = math.max(0, cw - used) },
        action,
    })
    table.insert(content, vspan(14))

    -- Filter pills (whole library only).
    local pills = HorizontalGroup:new{ align = "center" }
    for i, f in ipairs(FILTERS) do
        if i > 1 then table.insert(pills, HorizontalSpan:new{ width = px(8) }) end
        local label = f[2]
        if f[1] ~= "all" and (counts[f[1]] or 0) > 0 then
            label = label .. " " .. counts[f[1]]
        end
        table.insert(pills, pill(label, self.filter == f[1], function()
            self.filter = f[1]
            self.page = 1
            plugin.settings.library_filter = f[1]
            plugin:saveSettings()
            self:refresh()
        end))
    end
    if not self.collection then
        table.insert(content, pills)
        table.insert(content, vspan(16))
    else
        pills:free()
        table.insert(content, vspan(4))
    end

    -- Grid geometry: 3 columns; as many rows as fit above the pager and tab bar.
    local cols, gap = 3, px(16)
    local bw = math.floor((cw - (cols - 1) * gap) / cols)
    local label_h = px(34)
    local pager_h = px(64) -- arrows (~50) + breathing room above the tab bar
    local head_h = content:getSize().h
    content._size = nil -- still adding children (see VerticalGroup caching)
    local avail = self.dimen.h - self[2]:getSize().h - px(8) - head_h - pager_h
    -- Prefer at least two rows: shrink covers (keeping 2:3) rather than show one row.
    local bh = math.floor(bw * 1.45)
    local fit2 = math.floor((avail - gap) / 2) - px(6) - label_h
    if fit2 < bh and fit2 >= px(130) then bh = fit2 end
    local cell_h = bh + px(6) + label_h
    local rows = math.max(1, math.floor((avail + gap) / (cell_h + gap)))
    local per_page = rows * cols
    self.pages = math.max(1, math.ceil(#books / per_page))
    self.page = math.max(1, math.min(self.page, self.pages))

    if #books == 0 then
        table.insert(content, vspan(40))
        table.insert(content, W.textbox(
            (self.filter == "all" and not self.collection) and _("No books yet. Copy some EPUBs into your home folder!")
                or _("No books here yet."),
            W.FONT_SERIF_BOLD, 18, cw, { alignment = "center", bgcolor = W.PAPER }))
    end

    local shown = {}
    local first = (self.page - 1) * per_page + 1
    for r = 1, rows do
        local row = HorizontalGroup:new{ align = "top" }
        local any = false
        for c = 1, cols do
            local i = first + (r - 1) * cols + (c - 1)
            local meta = books[i]
            if meta then
                any = true
                if c > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
                local book = Data.bookMeta(meta.file, true)
                shown[#shown + 1] = book
                local status_line
                if meta.group == "complete" then
                    status_line = W.text(_("Finished") .. " ★", W.FONT_SANS_BOLD, 11, { color = W.MUTED })
                elseif meta.group == "new" then
                    status_line = W.text(_("New"), W.FONT_SANS_BOLD, 11, { color = W.MUTED })
                else
                    local pct = meta.percent or 0
                    status_line = HorizontalGroup:new{
                        align = "center",
                        W.Bar:new{ width = bw - px(40), height = 4, percent = pct },
                        HorizontalSpan:new{ width = px(6) },
                        W.text(string.format("%d%%", math.floor(pct * 100 + 0.5)),
                            W.FONT_SANS_BOLD, 11, { color = W.MUTED }),
                    }
                end
                table.insert(row, W.Tappable:new{
                    callback = function() plugin:openBook(book.file) end,
                    hold_callback = function() plugin:showBookInfo(book.file) end,
                    column(bw, "left", {
                        W.cover(book, bw, bh, i),
                        vspan(6),
                        W.text(book.title or "", W.FONT_SANS_BOLD, 13, { max_width = bw }),
                        vspan(3),
                        status_line,
                    }),
                })
            end
        end
        if not any then break end
        if r > 1 then table.insert(content, VerticalSpan:new{ width = gap }) end
        table.insert(content, row)
    end

    -- Pager, pinned just above the tab bar.
    self.pager = nil
    if self.pages > 1 then
        local function arrow(text, enabled, cb)
            return W.Tappable:new{
                callback = function() if enabled then cb() end end,
                FrameContainer:new{
                    background = enabled and W.WHITE or W.PAPER,
                    color = enabled and W.BLACK or W.GREY,
                    bordersize = math.max(1, px(1.5)), radius = px(16),
                    padding = 0, padding_left = px(14), padding_right = px(14),
                    padding_top = px(4), padding_bottom = px(4),
                    W.text(text, W.FONT_SANS_BOLD, 15, { color = enabled and W.BLACK or W.GREY }),
                },
            }
        end
        local label = W.text(T("%1 / %2", self.page, self.pages), W.FONT_SANS_BOLD, 13)
        self.pager = HorizontalGroup:new{
            align = "center",
            arrow(BD.mirroredUILayout() and "›" or "‹", self.page > 1, function() self:onPrevPage() end),
            HorizontalSpan:new{ width = px(18) },
            label,
            HorizontalSpan:new{ width = px(18) },
            arrow(BD.mirroredUILayout() and "‹" or "›", self.page < self.pages, function() self:onNextPage() end),
        }
        self[3] = self.pager -- a child, so its arrows receive taps
    end

    if not self._index_requested and Data.indexMissingCovers(shown, px(260), px(380)) then
        self._index_requested = true
        self:watchIndexing()
    end

    self[1] = HorizontalGroup:new{ HorizontalSpan:new{ width = margin }, content }
end

-- Home:paintTo draws background, self[1] and the tab bar; add the pager.
function Library:paintTo(bb, x, y)
    Home.paintTo(self, bb, x, y)
    if self.pager then
        local ps = self.pager:getSize()
        local nav_h = self[2]:getSize().h + px(8)
        self.pager:paintTo(bb, x + math.floor((self.dimen.w - ps.w) / 2),
            y + self.dimen.h - nav_h - ps.h - px(10))
    end
end

function Library:onNextPage()
    if self.page < self.pages then
        self.page = self.page + 1
        self._index_requested = false
        self:refresh()
    end
    return true
end

function Library:onPrevPage()
    if self.page > 1 then
        self.page = self.page - 1
        self._index_requested = false
        self:refresh()
    end
    return true
end

function Library:onSwipe(_, ges)
    local dir = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if dir == "west" then return self:onNextPage()
    elseif dir == "east" then return self:onPrevPage() end
end

function Library:refresh()
    self:build()
    UIManager:setDirty(self, "ui")
end

function Library:onShow()
    self._shown = true
    UIManager:setDirty(self, "full")
end

function Library:onCloseWidget()
    self._shown = false
    for i = 1, 3 do
        if self[i] then self[i]:free() end
    end
    if self.plugin and self.plugin.screen == self then self.plugin.screen = nil end
end

function Library:onClose()
    UIManager:close(self)
    return true
end

return Library
