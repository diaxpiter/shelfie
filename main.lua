--[[--
Shelfie: a cheerful reading-dashboard home screen for KOReader.

Shows on top of the file manager whenever it opens (at startup and after
closing a book). "Library" simply reveals the normal file browser below.

@module koplugin.Shelfie
--]]

local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local Shelfie = WidgetContainer:extend{
    name = "shelfie",
    is_doc_only = false,
    home = nil,
}

local DEFAULTS = {
    show_on_start = true,
    daily_goal = 30,
}

function Shelfie:init()
    self.settings = G_reader_settings:readSetting("shelfie", {})
    for k, v in pairs(DEFAULTS) do
        if self.settings[k] == nil then self.settings[k] = v end
    end
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)

    -- Only in the file manager (not while reading). Note: plugins are created
    -- before the file manager builds its file_chooser, so test for a document.
    if not self.ui.document and self.settings.show_on_start then
        UIManager:nextTick(function() self:showHome() end)
    end
end

function Shelfie:onDispatcherRegisterActions()
    Dispatcher:registerAction("shelfie_show", {
        category = "none", event = "ShowShelfie", title = _("Shelfie home"), filemanager = true,
    })
end

function Shelfie:saveSettings()
    G_reader_settings:saveSetting("shelfie", self.settings)
end

function Shelfie:getDailyGoal()
    return self.settings.daily_goal
end

-- Actions -------------------------------------------------------------------

function Shelfie:showHome()
    if self.home then
        self.home:refresh()
        return
    end
    local ok, Home = pcall(require, "shelfie_home")
    if not ok then
        logger.err("Shelfie: failed to load home screen:", Home)
        return
    end
    local ok2, home = pcall(Home.new, Home, { plugin = self })
    if not ok2 then
        logger.err("Shelfie: failed to build home screen:", home)
        UIManager:show(InfoMessage:new{ text = _("Shelfie could not draw the home screen. See crash.log for details.") })
        return
    end
    self.home = home
    UIManager:show(home)
    logger.info("Shelfie: home screen shown")

    -- Developer hook (desktop emulator only): SHELFIE_DEV_SHOT=/path/shot.png
    -- saves a screenshot a few seconds after the home screen appears, then quits.
    local shot = os.getenv("SHELFIE_DEV_SHOT")
    if shot and shot ~= "" then
        UIManager:scheduleIn(tonumber(os.getenv("SHELFIE_DEV_DELAY")) or 4, function()
            local ok, err = pcall(function() require("device").screen:shot(shot) end)
            logger.info("Shelfie: dev screenshot", ok and "saved to" or "FAILED:", ok and shot or err)
            UIManager:quit()
        end)
    end
end

function Shelfie:onShowShelfie()
    if self.ui.file_chooser then
        self:showHome()
    end
    return true
end

function Shelfie:closeHome()
    if self.home then
        UIManager:close(self.home)
        self.home = nil
    end
end

function Shelfie:openBook(file)
    self:closeHome()
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(file)
end

function Shelfie:showLibrary()
    self:closeHome()
end

function Shelfie:showStats()
    if self.ui.statistics and self.ui.statistics.onShowCalendarView then
        self.ui.statistics:onShowCalendarView()
    else
        UIManager:show(InfoMessage:new{ text = _("Enable the Reading statistics plugin to see your stats.") })
    end
end

function Shelfie:showCollections()
    if self.ui.collections then
        self.ui.collections:onShowCollList()
    end
end

function Shelfie:showMenu()
    if self.ui.menu then
        self.ui.menu:onShowMenu()
    end
end

function Shelfie:editDailyGoal()
    UIManager:show(SpinWidget:new{
        title_text = _("Daily reading goal"),
        info_text = _("Minutes you want to read each day."),
        value = self.settings.daily_goal,
        value_min = 5, value_max = 300, value_step = 5, value_hold_step = 15,
        unit = _("min"),
        default_value = DEFAULTS.daily_goal,
        callback = function(spin)
            self.settings.daily_goal = spin.value
            self:saveSettings()
            if self.home then self.home:refresh() end
        end,
    })
end

-- Menu ----------------------------------------------------------------------

function Shelfie:addToMainMenu(menu_items)
    menu_items.shelfie = {
        text = _("Shelfie"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Open Shelfie home"),
                enabled_func = function() return self.ui.file_chooser ~= nil end,
                callback = function(touchmenu_instance)
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                    self:showHome()
                end,
            },
            {
                text = _("Show Shelfie when the library opens"),
                checked_func = function() return self.settings.show_on_start end,
                callback = function()
                    self.settings.show_on_start = not self.settings.show_on_start
                    self:saveSettings()
                end,
            },
            {
                text_func = function()
                    return _("Daily reading goal") .. ": " .. self.settings.daily_goal .. " min"
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:editDailyGoal()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
        },
    }
end

function Shelfie:onCloseWidget()
    self:closeHome()
end

-- Keep the stats fresh when coming back from sleep.
function Shelfie:onResume()
    if self.home then
        UIManager:scheduleIn(1, function() if self.home then self.home:refresh() end end)
    end
end

return Shelfie
