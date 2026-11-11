--[[--
Base for Shelfie's simpler full-screen pages (Stats, Tags, Settings):
paper background, a header, white rounded cards and the shared tab bar.
A page subclass sets `tab` and implements `buildContent(content, width)`.
--]]

local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen

local Home = require("shelfie_home")
local W = require("shelfie_widgets")

local px = W.px
local column, vspan = Home.column, Home.vspan

local Page = InputContainer:extend{
    covers_fullscreen = true,
    plugin = nil,
    tab = "home",
}

Page.buildNav = Home.buildNav
Page.paintTo = Home.paintTo
Page.icon = Home.icon

function Page:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:build()
end

function Page:build()
    if self[1] then self[1]:free() end
    if self[2] then self[2]:free() end
    local margin = px(22)
    self.cw = self.dimen.w - 2 * margin
    self[2] = self:buildNav(self.tab)
    local content = VerticalGroup:new{ align = "left" }
    table.insert(content, vspan(18))
    self:buildContent(content, self.cw)
    self[1] = HorizontalGroup:new{ HorizontalSpan:new{ width = margin }, content }
end

function Page:buildContent(content, width) end -- luacheck: ignore

--- Big serif title on the left, an optional widget (e.g. a pill) on the right.
function Page:header(title, right)
    local t = W.text(title, W.FONT_SERIF_BOLD, 28)
    if not right then return t end
    return HorizontalGroup:new{
        align = "center",
        t,
        HorizontalSpan:new{ width = math.max(0, self.cw - t:getSize().w - right:getSize().w) },
        right,
    }
end

--- An outlined pill button.
function Page:pill(text, callback, filled)
    return W.Tappable:new{
        callback = callback,
        FrameContainer:new{
            background = filled and W.BLACK or W.WHITE,
            bordersize = math.max(1, px(1.5)), radius = px(14), padding = 0,
            padding_left = px(12), padding_right = px(12), padding_top = px(5), padding_bottom = px(5),
            W.text(text, W.FONT_SANS_BOLD, 12, { color = filled and W.WHITE or W.BLACK }),
        },
    }
end

--- A white rounded card holding `items` stacked vertically, `width` wide.
function Page:card(items, width, opts)
    opts = opts or {}
    local border, pad = math.max(1, px(2)), px(opts.padding or 16)
    local inner = (width or self.cw) - 2 * border - 2 * pad
    return FrameContainer:new{
        background = opts.dark and W.BLACK or W.WHITE,
        bordersize = border, radius = px(opts.radius or 22), padding = pad,
        column(inner, "left", items),
    }, inner
end

--- A small grey section label.
function Page:label(text)
    return W.text(text:upper(), W.FONT_SANS_BOLD, 11, { color = W.MUTED })
end

--- A full-width tappable row: label on the left, `right` (widget or text) on the right.
function Page:row(width, label, right, callback, sub)
    if type(right) == "string" then
        right = W.text(right, W.FONT_SANS_BOLD, 14, { color = W.MUTED })
    end
    local left = sub and VerticalGroup:new{
        align = "left",
        W.text(label, W.FONT_SANS_BOLD, 15),
        W.text(sub, W.FONT_SANS, 12, { color = W.MUTED, max_width = width - right:getSize().w - px(12) }),
    } or W.text(label, W.FONT_SANS_BOLD, 15, { max_width = width - right:getSize().w - px(12) })
    local row = column(width, "left", {
        vspan(10),
        HorizontalGroup:new{
            align = "center",
            left,
            HorizontalSpan:new{ width = math.max(0, width - left:getSize().w - right:getSize().w) },
            right,
        },
        vspan(10),
    })
    return callback and W.Tappable:new{ callback = callback, row } or row
end

function Page:refresh()
    self:build()
    UIManager:setDirty(self, "ui")
end

function Page:onShow()
    self._shown = true
    UIManager:setDirty(self, "full")
end

function Page:onCloseWidget()
    self._shown = false
    if self[1] then self[1]:free() end
    if self[2] then self[2]:free() end
    if self.plugin and self.plugin.screen == self then self.plugin.screen = nil end
end

function Page:onClose()
    UIManager:close(self)
    return true
end

return Page
