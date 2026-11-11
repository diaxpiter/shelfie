--[[--
Shelfie: a cheerful reading-dashboard home screen for KOReader.

Shelfie draws its own full-screen pages on top of KOReader's file manager:
Home, Library, Stats, Tags and Settings, switched with a bottom tab bar.
It appears whenever the file manager opens (at startup and after closing
a book). "Folders" reveals KOReader's own file browser underneath.

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
    screen = nil, -- the Shelfie page currently shown, if any
}

local DEFAULTS = {
    show_on_start = true,
    daily_goal = 30,
    library_filter = "all",
}

local SCREENS = {
    home = "shelfie_home",
    library = "shelfie_library",
    stats = "shelfie_stats",
    tags = "shelfie_tags",
    settings = "shelfie_settings",
}

function Shelfie:init()
    self.settings = G_reader_settings:readSetting("shelfie", {})
    for k, v in pairs(DEFAULTS) do
        if self.settings[k] == nil then self.settings[k] = v end
    end
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)

    -- Load Shelfie's bundled fonts once, for every page.
    local W = require("shelfie_widgets")
    if not W.fonts_ready then
        pcall(W.setupFonts, self.path)
        W.fonts_ready = true
    end

    -- Only in the file manager (not while reading). Note: plugins are created
    -- before the file manager builds its file_chooser, so test for a document.
    if not self.ui.document and self.settings.show_on_start then
        UIManager:nextTick(function()
            -- SHELFIE_DEV_SCREEN (desktop emulator only) opens another page first.
            local dev = os.getenv("SHELFIE_DEV_SCREEN")
            self:showScreen(SCREENS[dev or ""] and dev or "home")
            self:devScreenshot()
        end)
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

-- Screens -------------------------------------------------------------------

--- Show one of Shelfie's pages, replacing the current one.
-- `args` are passed to the page (e.g. { collection = "favorites" } for Library).
function Shelfie:showScreen(name, args)
    if not self.ui.file_chooser then return end -- only in the file manager
    local current = self.screen
    if current and current.screen_name == name and not args then
        current:refresh()
        return
    end
    local ok, Page = pcall(require, SCREENS[name])
    if not ok then
        logger.err("Shelfie: cannot load page", name, Page)
        return
    end
    local opts = { plugin = self, screen_name = name }
    for k, v in pairs(args or {}) do opts[k] = v end
    local ok2, page = pcall(Page.new, Page, opts)
    if not ok2 then
        logger.err("Shelfie: failed to build page", name, page)
        UIManager:show(InfoMessage:new{ text = _("Shelfie could not draw this page. See crash.log for details.") })
        return
    end
    self.screen = page
    UIManager:show(page)
    if current then UIManager:close(current) end
    logger.info("Shelfie: showing", name)
end

function Shelfie:closeScreen()
    if self.screen then
        local page = self.screen
        self.screen = nil
        UIManager:close(page)
    end
end

function Shelfie:showHome() self:showScreen("home") end
function Shelfie:showLibrary(args) self:showScreen("library", args) end
function Shelfie:showStats() self:showScreen("stats") end
function Shelfie:showCollections() self:showScreen("tags") end
function Shelfie:showSettings() self:showScreen("settings") end
Shelfie.showMenu = Shelfie.showSettings -- the tab bar's "Settings"

function Shelfie:onShowShelfie()
    self:showHome()
    return true
end

-- Actions -------------------------------------------------------------------

function Shelfie:openBook(file)
    self:closeScreen()
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(file)
end

--- KOReader's own file browser (folders, file operations).
function Shelfie:showFolders()
    self:closeScreen()
end

function Shelfie:showBookInfo(file)
    if self.ui.bookinfo then self.ui.bookinfo:show(file) end
end

--- KOReader's calendar view of reading statistics.
function Shelfie:showCalendar()
    if self.ui.statistics and self.ui.statistics.onShowCalendarView then
        self.ui.statistics:onShowCalendarView()
    else
        UIManager:show(InfoMessage:new{ text = _("Enable the Reading statistics plugin to see your stats.") })
    end
end

--- KOReader's full settings menu.
function Shelfie:showKOReaderMenu()
    if self.ui.menu then self.ui.menu:onShowMenu() end
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
            if self.screen then self.screen:refresh() end
        end,
    })
end

function Shelfie:toggleShowOnStart()
    self.settings.show_on_start = not self.settings.show_on_start
    self:saveSettings()
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
                callback = function() self:toggleShowOnStart() end,
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
    self:closeScreen()
end

-- Keep stats fresh when coming back from sleep.
function Shelfie:onResume()
    if self.screen then
        UIManager:scheduleIn(1, function() if self.screen then self.screen:refresh() end end)
    end
end

-- Developer hook (desktop emulator only): SHELFIE_DEV_SHOT=/path/shot.png saves
-- a screenshot SHELFIE_DEV_DELAY seconds after startup, then quits.
function Shelfie:devScreenshot()
    local shot = os.getenv("SHELFIE_DEV_SHOT")
    if not shot or shot == "" then return end
    UIManager:scheduleIn(tonumber(os.getenv("SHELFIE_DEV_DELAY")) or 4, function()
        local ok, err = pcall(function() require("device").screen:shot(shot) end)
        logger.info("Shelfie: dev screenshot", ok and "saved to" or "FAILED:", ok and shot or err)
        UIManager:quit()
    end)
end

return Shelfie
