--[[--
Shelfie tags page: KOReader's collections as cards with a peek at their
covers. Tap a card to browse it in the Shelfie library grid; "Manage" opens
KOReader's own collection manager (create, rename, delete).
--]]

local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local T = require("ffi/util").template
local _ = require("gettext")

local Data = require("shelfie_data")
local Home = require("shelfie_home")
local Page = require("shelfie_page")
local W = require("shelfie_widgets")

local px = W.px
local vspan = Home.vspan

local Tags = Page:extend{
    name = "shelfie_tags",
    tab = "tags",
}

Tags.watchIndexing = Home.watchIndexing

function Tags:buildContent(content, cw)
    local plugin = self.plugin
    local colls = Data.collections()

    table.insert(content, self:header(_("Tags"), self:pill(_("Manage"), function()
        if plugin.ui.collections then plugin.ui.collections:onShowCollList() end
    end)))
    table.insert(content, vspan(4))
    table.insert(content, W.text(
        #colls == 1 and _("1 collection") or T(_("%1 collections"), #colls),
        W.FONT_SANS_BOLD, 12, { color = W.MUTED }))
    table.insert(content, vspan(14))

    local cols, gap = 2, px(12)
    local card_w = math.floor((cw - gap) / cols)
    local shown_books = {}
    local row
    for i, c in ipairs(colls) do
        if (i - 1) % cols == 0 then
            if row then
                table.insert(content, row)
                table.insert(content, VerticalSpan:new{ width = gap })
            end
            row = HorizontalGroup:new{ align = "top" }
        else
            table.insert(row, HorizontalSpan:new{ width = gap })
        end
        -- Three little covers side by side (patterns when there are fewer books).
        local probe, inner = self:card({}, card_w, { padding = 14, radius = 20 })
        probe:free()
        local mgap = px(6)
        local mw = math.floor((inner - 2 * mgap) / 3)
        local mh = math.floor(mw * 1.45)
        local minis = HorizontalGroup:new{ align = "top" }
        for k = 1, 3 do
            if k > 1 then table.insert(minis, HorizontalSpan:new{ width = mgap }) end
            local file = c.files[k]
            if file then
                local book = Data.bookMeta(file, true)
                shown_books[#shown_books + 1] = book
                table.insert(minis, W.cover(book, mw, mh, k))
            else
                table.insert(minis, W.PatternCover:new{
                    width = mw, height = mh, title = "", pattern = (i + k) % 4 + 1, radius = 8,
                })
            end
        end
        local card = self:card({
            minis,
            vspan(10),
            W.text(c.title, W.FONT_SERIF_BOLD, 17, { max_width = inner }),
            vspan(2),
            W.text(c.count == 1 and _("1 book") or T(_("%1 books"), c.count),
                W.FONT_SANS_BOLD, 12, { color = W.MUTED }),
        }, card_w, { padding = 14, radius = 20 })
        table.insert(row, W.Tappable:new{
            callback = function() plugin:showLibrary({ collection = c.name }) end,
            card,
        })
    end
    if row then table.insert(content, row) end

    if #colls <= 1 then
        table.insert(content, vspan(16))
        table.insert(content, W.textbox(
            _("Tip: tap “Manage” to create collections, then long-press a book in Folders to add it."),
            W.FONT_SANS, 13, cw, { color = W.MUTED, bgcolor = W.PAPER }))
    end

    if not self._index_requested and Data.indexMissingCovers(shown_books, px(200), px(300)) then
        self._index_requested = true
        self:watchIndexing()
    end
end

return Tags
