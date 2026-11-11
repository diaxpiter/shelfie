--[[--
Shelfie stats page: streak and totals, a 7-day bar chart against the daily
goal, and all-time numbers. "Calendar" opens KOReader's detailed calendar.
--]]

local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local T = require("ffi/util").template
local _ = require("gettext")

local Data = require("shelfie_data")
local Home = require("shelfie_home")
local Page = require("shelfie_page")
local W = require("shelfie_widgets")

local px = W.px
local vspan = Home.vspan

local Stats = Page:extend{
    name = "shelfie_stats",
    tab = "stats",
}

local function duration(minutes)
    if minutes < 60 then return T(_("%1m"), minutes) end
    local h, m = math.floor(minutes / 60), minutes % 60
    return m > 0 and T(_("%1h %2m"), h, m) or T(_("%1h"), h)
end

function Stats:buildContent(content, cw)
    local plugin = self.plugin
    local stats = Data.readingStats()
    local s = Data.statsSummary()
    local goal = plugin:getDailyGoal()

    table.insert(content, self:header(_("Stats"),
        self:pill(_("Calendar"), function() plugin:showCalendar() end)))
    table.insert(content, vspan(14))

    -- Tiles: streak · this week · this month.
    local gap = px(10)
    local tile_w = math.floor((cw - 2 * gap) / 3)
    local function tile(dark, icon, value, label)
        local color = dark and W.WHITE or W.BLACK
        local frame = self:card({
            icon and self:icon(icon, 22) or vspan(22),
            W.text(value, W.FONT_SANS_BOLD, 24, { color = color }),
            W.text(label, W.FONT_SANS_BOLD, 11, { color = color }),
        }, tile_w, { dark = dark, padding = 12, radius = 18 })
        return W.Tappable:new{ callback = function() plugin:showCalendar() end, frame }
    end
    table.insert(content, HorizontalGroup:new{
        align = "top",
        tile(true, "flame.white", tostring(stats.streak),
            stats.streak == 1 and _("day streak") or _("days streak")),
        HorizontalSpan:new{ width = gap },
        tile(false, "clock", duration(s.week_total), _("this week")),
        HorizontalSpan:new{ width = gap },
        tile(false, "books", duration(s.month_min), os.date("%B"):lower()),
    })
    table.insert(content, vspan(12))

    -- Last 7 days chart.
    local chart_card, inner = self:card({}, cw)
    local reached = 0
    for _, d in ipairs(s.week) do if d.minutes >= goal then reached = reached + 1 end end
    local chart_items = chart_card[1]
    table.insert(chart_items, HorizontalGroup:new{
        align = "center",
        self:label(_("Last 7 days")),
    })
    table.insert(chart_items, vspan(2))
    table.insert(chart_items, W.text(
        T(_("Goal of %1 min reached on %2 of 7 days"), goal, reached),
        W.FONT_SANS, 12, { color = W.MUTED, max_width = inner }))
    table.insert(chart_items, vspan(8))
    table.insert(chart_items, W.BarChart:new{
        width = inner, height = px(84), days = s.week, goal = goal,
    })
    table.insert(content, chart_card)
    table.insert(content, vspan(12))

    -- All-time numbers.
    local all_card, all_inner = self:card({}, cw)
    local items = all_card[1]
    table.insert(items, self:label(_("All time")))
    local cells = {
        { duration(s.total_min), _("time reading") },
        { tostring(s.total_pages), _("pages turned") },
        { tostring(s.books_started), _("books opened") },
        { tostring(Data.finishedThisYear()), T(_("finished in %1"), os.date("%Y")) },
    }
    -- 2 x 2 grid of big numbers with small captions.
    local half = math.floor(all_inner / 2)
    for r = 0, 1 do
        table.insert(items, vspan(8))
        local line = HorizontalGroup:new{ align = "top" }
        for c = 1, 2 do
            local cell = cells[r * 2 + c]
            table.insert(line, Home.column(half, "left", {
                W.text(cell[1], W.FONT_SANS_BOLD, 22),
                W.text(cell[2], W.FONT_SANS_BOLD, 11, { color = W.MUTED }),
            }))
        end
        table.insert(items, line)
    end
    table.insert(content, all_card)

    if not s.available then
        table.insert(content, vspan(10))
        table.insert(content, W.textbox(
            _("Turn on the Reading statistics plugin to start tracking."),
            W.FONT_SANS, 13, cw, { color = W.MUTED, bgcolor = W.PAPER }))
    end
end

return Stats
