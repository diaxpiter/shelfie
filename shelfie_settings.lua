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
    local card, inner = self:card({}, self.cw, { padding = 12 })
    local items = card[1]
    table.insert(items, self:label(title))
    for i, r in ipairs(rows) do
        if i > 1 then table.insert(items, W.Rule:new{ width = inner }) end
        table.insert(items, r(inner))
    end
    table.insert(content, card)
    table.insert(content, vspan(10))
end

function Settings:buildContent(content)
    local plugin = self.plugin
    local s = plugin.settings

    local meta = dofile(plugin.path .. "/_meta.lua")
    table.insert(content, self:header(_("Settings"),
        W.text("Shelfie " .. (meta.version or ""), W.FONT_SANS_BOLD, 12, { color = W.MUTED })))
    table.insert(content, vspan(14))

    local shelfie_rows = {
        function(w)
            return self:row(w, _("Daily reading goal"),
                W.text(T(_("%1 min"), s.daily_goal) .. "  ›", W.FONT_SANS_BOLD, 14, { color = W.MUTED }),
                function() plugin:editDailyGoal() end)
        end,
        function(w)
            return self:row(w, _("Open Shelfie with the library"),
                W.Switch:new{ on = s.show_on_start },
                function() plugin:toggleShowOnStart(); self:refresh() end)
        end,
        function(w)
            return self:row(w, _("Hide dictionaries"),
                W.Switch:new{ on = s.hide_dictionaries },
                function() plugin:toggleHideDictionaries(); self:refresh() end)
        end,
    }
    local hidden = plugin:hiddenCount()
    if hidden > 0 then
        table.insert(shelfie_rows, function(w)
            return self:row(w, T(_("Hidden books: %1"), hidden),
                W.text(_("Show all") .. "  ›", W.FONT_SANS_BOLD, 14, { color = W.MUTED }),
                function() plugin:unhideAll() end)
        end)
    end
    self:section(content, _("Shelfie"), shelfie_rows)

    -- Reading & device: dictionaries, frontlight, Wi-Fi (in one card to fit the screen).
    local device_rows = {}
    if plugin.ui.dictionary then
        table.insert(device_rows, function(w)
            return self:row(w, _("Dictionaries"), chevron(),
                function() plugin.ui.dictionary:showDictionariesMenu() end)
        end)
        table.insert(device_rows, function(w)
            return self:row(w, _("Look up a word"), chevron(),
                function() plugin.ui.dictionary:onShowDictionaryLookup() end)
        end)
    end
    local dev_preview = os.getenv("SHELFIE_DEV_SHOT") ~= nil -- emulator: preview device rows
    if Device:hasFrontlight() or dev_preview then
        table.insert(device_rows, function(w)
            return self:row(w, _("Frontlight"), chevron(), function()
                local FrontLightWidget = require("ui/widget/frontlightwidget")
                UIManager:show(FrontLightWidget:new{})
            end)
        end)
    end
    if Device:hasWifiToggle() or dev_preview then
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
        self:section(content, _("Reading & device"), device_rows)
    end

    self:section(content, _("KOReader"), {
        function(w)
            return self:row(w, _("All KOReader settings"), chevron(),
                function() plugin:showKOReaderMenu() end)
        end,
        function(w)
            return self:row(w, _("Folders"), chevron(), function() plugin:showFolders() end)
        end,
    })

end

return Settings
