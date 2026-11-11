--[[--
Small drawing building blocks for Shelfie: tappable areas, the progress
ring, pattern placeholder covers and the scaling helpers that keep the
layout proportional to the 540x720 mockup on any screen.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen

local W = {}

W.BLACK = Blitbuffer.COLOR_BLACK
W.WHITE = Blitbuffer.COLOR_WHITE
W.PAPER = Blitbuffer.Color8(0xF2)
W.TRACK = Blitbuffer.Color8(0xDC)
W.DOTS = Blitbuffer.Color8(0xC9)
W.MUTED = Blitbuffer.Color8(0x44)
W.GREY = Blitbuffer.Color8(0x9A)
W.DARK = Blitbuffer.Color8(0x2A)

-- Fallbacks (bundled with KOReader); replaced by our own fonts in setupFonts().
W.FONT_SANS = "NotoSans-Regular.ttf"
W.FONT_SANS_BOLD = "NotoSans-Bold.ttf"
W.FONT_SERIF = "NotoSerif-Regular.ttf"
W.FONT_SERIF_BOLD = "NotoSerif-Bold.ttf"

-- Path of `to` relative to directory `from` (both absolute, already resolved).
local function relpath(from, to)
    local a, b = {}, {}
    for part in from:gmatch("[^/]+") do a[#a + 1] = part end
    for part in to:gmatch("[^/]+") do b[#b + 1] = part end
    local i = 1
    while a[i] and b[i] and a[i] == b[i] do i = i + 1 end
    local out = {}
    for _ = i, #a do out[#out + 1] = ".." end
    for j = i, #b do out[#out + 1] = b[j] end
    return table.concat(out, "/")
end

--- Use the fonts shipped in the plugin's fonts/ folder.
-- KOReader opens fonts as "<fontdir>/<name>", so we hand it a path relative
-- to its font directory; this works wherever the plugin is installed.
function W.setupFonts(plugin_path)
    local ffiutil = require("ffi/util")
    local FontList = require("fontlist")
    local fontdir = ffiutil.realpath(FontList.fontdir)
    local root = ffiutil.realpath(plugin_path)
    if not fontdir or not root then return end
    local function pick(file, fallback)
        local abs = root .. "/fonts/" .. file
        local f = io.open(abs, "rb")
        if not f then return fallback end
        f:close()
        local rel = relpath(fontdir, abs)
        return Font:getFace(rel, 12) and rel or fallback
    end
    W.FONT_SANS = pick("AtkinsonHyperlegible-Regular.ttf", W.FONT_SANS)
    W.FONT_SANS_BOLD = pick("AtkinsonHyperlegible-Bold.ttf", W.FONT_SANS_BOLD)
    W.FONT_SERIF = pick("Literata-Regular.ttf", W.FONT_SERIF)
    W.FONT_SERIF_BOLD = pick("Literata-Bold.ttf", W.FONT_SERIF_BOLD)
end

--- Mockup pixels (540 px wide design) -> device pixels.
function W.px(n)
    local s = math.min(Screen:getWidth() / 540, Screen:getHeight() / 720)
    return math.floor(n * s + 0.5)
end

--- A font face whose rendered size matches `n` mockup pixels.
function W.face(name, n)
    local dpi_scale = Screen:scaleBySize(1000) / 1000
    return Font:getFace(name, math.max(6, W.px(n) / dpi_scale))
end

function W.text(str, font, size, opts)
    opts = opts or {}
    return TextWidget:new{
        text = str,
        face = W.face(font, size),
        fgcolor = opts.color or W.BLACK,
        max_width = opts.max_width,
        bold = opts.bold,
    }
end

function W.textbox(str, font, size, width, opts)
    opts = opts or {}
    return TextBoxWidget:new{
        text = str,
        face = W.face(font, size),
        width = width,
        fgcolor = opts.color or W.BLACK,
        alignment = opts.alignment or "left",
        height = opts.height,
        height_overflow_show_ellipsis = true,
        line_height = opts.line_height or 0.1,
        bgcolor = opts.bgcolor,
    }
end

--[[ Tappable: wraps any widget and calls `callback` when it is tapped. ]]
W.Tappable = InputContainer:extend{
    callback = nil,
}

function W.Tappable:init()
    self.touch_dimen = Geom:new{ x = 0, y = 0, w = 0, h = 0 }
    self.ges_events = {
        TapShelfie = {
            GestureRange:new{ ges = "tap", range = function() return self.touch_dimen end },
        },
    }
end

function W.Tappable:paintTo(bb, x, y)
    local size = self[1]:getSize()
    self.touch_dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    self.dimen = self.touch_dimen
    self[1]:paintTo(bb, x, y)
end

function W.Tappable:getSize()
    return self[1]:getSize()
end

function W.Tappable:onTapShelfie()
    if self.callback then self.callback() end
    return true
end

--[[ Ring: a circular progress indicator with the percentage in the middle. ]]
W.Ring = Widget:extend{
    size = 78,       -- mockup px
    thickness = 6,   -- mockup px
    percent = 0,     -- 0..1
}

function W.Ring:init()
    self.d = W.px(self.size)
    self.t = math.max(2, W.px(self.thickness))
    self.dimen = Geom:new{ w = self.d, h = self.d }
    self.label = W.text(string.format("%d%%", math.floor(self.percent * 100 + 0.5)),
        W.FONT_SANS_BOLD, 18)
end

function W.Ring:getSize()
    return self.dimen
end

function W.Ring:paintTo(bb, x, y)
    local r = math.floor(self.d / 2)
    local cx, cy = x + r, y + r
    bb:paintCircle(cx, cy, r, W.TRACK, self.t)
    -- Progress arc: stamp filled dots along the arc, from 12 o'clock clockwise.
    local mid = r - self.t / 2
    local dot = math.max(1, math.floor(self.t / 2))
    local sweep = 2 * math.pi * math.max(0, math.min(1, self.percent))
    -- One stamp per pixel of arc length: a smooth stroke with round caps.
    local steps = math.max(1, math.ceil(mid * sweep))
    for i = 0, steps do
        local a = -math.pi / 2 + sweep * i / steps
        bb:paintCircle(math.floor(cx + mid * math.cos(a) + 0.5),
                       math.floor(cy + mid * math.sin(a) + 0.5), dot, W.BLACK)
    end
    local ls = self.label:getSize()
    self.label:paintTo(bb, cx - math.floor(ls.w / 2), cy - math.floor(ls.h / 2))
end

function W.Ring:free()
    if self.label then self.label:free() end
end

--[[ Bar: a thin rounded progress bar. ]]
W.Bar = Widget:extend{
    width = 100,  -- device px
    height = 6,   -- mockup px
    percent = 0,
    fg = nil,
    bg = nil,
}

function W.Bar:init()
    self.h = math.max(2, W.px(self.height))
    self.dimen = Geom:new{ w = self.width, h = self.h }
end

function W.Bar:getSize() return self.dimen end

function W.Bar:paintTo(bb, x, y)
    local rad = math.floor(self.h / 2)
    bb:paintRoundedRect(x, y, self.width, self.h, self.bg or W.TRACK, rad)
    local fill = math.floor(self.width * math.max(0, math.min(1, self.percent)))
    if fill >= self.h then
        bb:paintRoundedRect(x, y, fill, self.h, self.fg or W.BLACK, rad)
    end
end

--[[ PatternCover: a placeholder cover (pattern + title label) for books
     without a cached cover image, in the spirit of the mockup. ]]
W.PatternCover = Widget:extend{
    width = 100,
    height = 150,
    title = "",
    pattern = 1,
    radius = 10, -- mockup px
}

local PATTERNS = { "stripes", "grey", "dots", "dark" }

function W.PatternCover:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local pad = W.px(6)
    self.label = W.textbox(self.title, W.FONT_SERIF, 10, self.width - 4 * pad,
        { bgcolor = W.WHITE, height = W.px(30) })
end

function W.PatternCover:getSize() return self.dimen end

function W.PatternCover:paintTo(bb, x, y)
    local w, h = self.width, self.height
    local rad = W.px(self.radius)
    local border = math.max(1, W.px(2))
    local kind = PATTERNS[(self.pattern - 1) % #PATTERNS + 1]
    bb:paintRoundedRect(x, y, w, h, W.BLACK, rad)
    local ix, iy, iw, ih = x + border, y + border, w - 2 * border, h - 2 * border
    local irad = math.max(0, rad - border)
    if kind == "dark" then
        bb:paintRoundedRect(ix, iy, iw, ih, W.DARK, irad)
    elseif kind == "grey" then
        bb:paintRoundedRect(ix, iy, iw, ih, W.GREY, irad)
    else
        bb:paintRoundedRect(ix, iy, iw, ih, W.WHITE, irad)
        local step = math.max(4, W.px(kind == "dots" and 8 or 9))
        local dot = math.max(1, W.px(kind == "dots" and 2 or 3))
        for yy = iy + irad, iy + ih - irad - dot, step do
            if kind == "dots" then
                for xx = ix + step / 2, ix + iw - dot, step do
                    bb:paintRect(math.floor(xx), yy, dot, dot, W.BLACK)
                end
            else
                bb:paintRect(ix + border, yy, iw - 2 * border, dot, W.BLACK)
            end
        end
    end
    -- White title label at the bottom.
    local pad = W.px(6)
    local ls = self.label:getSize()
    local lx, ly = x + pad, y + h - pad - ls.h - 2 * pad
    bb:paintRoundedRect(lx, ly, w - 2 * pad, ls.h + 2 * pad, W.WHITE, W.px(6))
    self.label:paintTo(bb, lx + pad, ly + pad)
end

function W.PatternCover:free()
    if self.label then self.label:free() end
end

--[[ CoverImage: a real cover bitmap, scaled to fit, with a rounded black frame. ]]
W.CoverImage = Widget:extend{
    width = 100,
    height = 150,
    bb = nil, -- Blitbuffer from the cover browser cache (a fresh copy: we free it)
    radius = 10,
}

function W.CoverImage:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local border = math.max(1, W.px(2))
    local bw, bh = self.bb:getWidth(), self.bb:getHeight()
    local scale = math.min((self.width - 2 * border) / bw, (self.height - 2 * border) / bh)
    self.scaled = self.bb:scale(math.floor(bw * scale), math.floor(bh * scale))
    self.bb:free()
    self.bb = nil
end

function W.CoverImage:getSize() return self.dimen end

function W.CoverImage:paintTo(bb, x, y)
    local sw, sh = self.scaled:getWidth(), self.scaled:getHeight()
    local border = math.max(1, W.px(2))
    local ox = x + math.floor((self.width - sw) / 2)
    local oy = y + math.floor((self.height - sh) / 2)
    bb:paintRoundedRect(ox - border, oy - border, sw + 2 * border, sh + 2 * border, W.BLACK, W.px(4))
    bb:blitFrom(self.scaled, ox, oy, 0, 0, sw, sh)
end

function W.CoverImage:free()
    if self.scaled then self.scaled:free(); self.scaled = nil end
end

--- A cover widget for a book: the real cover when cached, else a pattern.
function W.cover(book, width, height, index)
    if book.cover_bb then
        local ok, widget = pcall(W.CoverImage.new, W.CoverImage,
            { width = width, height = height, bb = book.cover_bb })
        if ok then return widget end
    end
    return W.PatternCover:new{ width = width, height = height, title = book.title or "", pattern = index or 1 }
end

return W
