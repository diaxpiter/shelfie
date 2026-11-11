--[[--
Shelfie settings page: Shelfie's own options as switches and rows, plus
shortcuts into KOReader (full settings menu, folders, frontlight, Wi-Fi).
--]]

local Device = require("device")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local Home = require("shelfie_home")
local Page = require("shelfie_page")
local W = require("shelfie_widgets")

local vspan = Home.vspan

local Settings = Page:extend{
    name = "shelfie_settings",
    tab = "settings",
}

local function chevron()
    return W.text("›", W.FONT_SANS_BOLD, 20, { color = W.MUTED })
end

function Settings:section(content, title, rows)
    local card, inner = self:card({}, self.cw, { padding = 14 })
    local items = card[1]
    table.insert(items, self:label(title))
    for i, r in ipairs(rows) do
        if i > 1 then table.insert(items, W.Rule:new{ width = inner }) end
        table.insert(items, r(inner))
    end
    table.insert(content, card)
    table.insert(content, vspan(12))
end

function Settings:buildContent(content)
    local plugin = self.plugin
    local s = plugin.settings

    table.insert(content, self:header(_("Settings")))
    table.insert(content, vspan(14))

    self:section(content, _("Shelfie"), {
        function(w)
            return self:row(w, _("Daily reading goal"),
                W.text(T(_("%1 min"), s.daily_goal) .. "  ›", W.FONT_SANS_BOLD, 14, { color = W.MUTED }),
                function() plugin:editDailyGoal() end,
                _("Used by the goal tile and the stats chart"))
        end,
        function(w)
            return self:row(w, _("Open Shelfie with the library"),
                W.Switch:new{ on = s.show_on_start },
                function() plugin:toggleShowOnStart(); self:refresh() end,
                _("Off: start in KOReader's file browser"))
        end,
    })

    local device_rows = {}
    if Device:hasFrontlight() then
        table.insert(device_rows, function(w)
            return self:row(w, _("Frontlight"), chevron(), function()
                local FrontLightWidget = require("ui/widget/frontlightwidget")
                UIManager:show(FrontLightWidget:new{})
            end)
        end)
    end
    if Device:hasWifiToggle() then
        table.insert(device_rows, function(w)
            local NetworkMgr = require("ui/network/manager")
            local on = NetworkMgr:isWifiOn()
            return self:row(w, _("Wi-Fi"), W.Switch:new{ on = on }, function()
                local done = function() if self._shown then self:refresh() end end
                if on then NetworkMgr:toggleWifiOff(done) else NetworkMgr:toggleWifiOn(done) end
                UIManager:scheduleIn(3, function() if self._shown then self:refresh() end end)
            end)
        end)
    end
    if #device_rows > 0 then
        self:section(content, _("Device"), device_rows)
    end

    self:section(content, _("KOReader"), {
        function(w)
            return self:row(w, _("All KOReader settings"), chevron(),
                function() plugin:showKOReaderMenu() end)
        end,
        function(w)
            return self:row(w, _("Folders"), chevron(), function() plugin:showFolders() end,
                _("KOReader's file browser: copy, move, delete"))
        end,
        function(w)
            return self:row(w, _("Reading calendar"), chevron(), function() plugin:showCalendar() end)
        end,
    })

    local meta = dofile(plugin.path .. "/_meta.lua")
    table.insert(content, W.text(
        T(_("Shelfie %1 · github.com/diaxpiter/shelfie"), meta.version or ""),
        W.FONT_SANS, 11, { color = W.MUTED }))
end

return Settings
