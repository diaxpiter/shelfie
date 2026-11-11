--[[--
Shelfie sleep screen: replaces KOReader's sleep screen with a calm,
inverted (white on black) page: the book you're reading, its progress,
one of your highlights from it, and your streak. No "Sleeping" banner.

It hooks Screensaver:setup() (called right as the device goes to sleep):
KOReader picks its own screensaver first, then Shelfie swaps in a
pre-drawn full-screen image. If anything fails, KOReader's choice stays.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local DocSettings = require("docsettings")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen

local Data = require("shelfie_data")
local W = require("shelfie_widgets")

local px = W.px
local Sleep = {}

local INK = Blitbuffer.COLOR_WHITE
local SOFT = Blitbuffer.Color8(0xC8)
local DIM = Blitbuffer.Color8(0x58)
local BG = Blitbuffer.COLOR_BLACK

local function textbox(str, font, size, width, color, lines, align)
    local face = W.face(font, size)
    local tb = TextBoxWidget:new{
        text = str, face = face, width = width, fgcolor = color, bgcolor = BG,
        alignment = align or "center", line_height = 0.15,
    }
    if lines and tb:getSize().h > lines * tb:getLineHeight() + 2 then
        tb:free()
        tb = TextBoxWidget:new{
            text = str, face = face, width = width, fgcolor = color, bgcolor = BG,
            alignment = align or "center", line_height = 0.15,
            height = lines * math.ceil(face.size * 1.15) + 2,
            height_overflow_show_ellipsis = true,
        }
    end
    return tb
end

-- A random-ish (changes every sleep) highlight from the book, short enough to look good.
local function pickHighlight(file)
    if not file or not DocSettings:hasSidecarFile(file) then return end
    local ds = DocSettings:open(file)
    local list = ds:readSetting("annotations") or {}
    local good = {}
    for _, a in ipairs(list) do
        local t = a.text and a.text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
        -- Highlights only (they have an end position); bookmarks carry chapter names.
        if a.pos1 and t and #t >= 20 and #t <= 220 then good[#good + 1] = t end
    end
    if #good == 0 then return end
    return good[(os.time() % #good) + 1]
end

-- Current reading position: live from the open document, else from its sidecar.
local function currentPercent(ui, meta)
    if ui and ui.document and ui.getCurrentPage then
        local ok, page = pcall(ui.getCurrentPage, ui)
        local ok2, total = pcall(function() return ui.document:getPageCount() end)
        if ok and ok2 and page and total and total > 0 then return page / total end
    end
    return meta and meta.percent
end

--- Draw the sleep page into a new full-screen Blitbuffer (caller owns it).
function Sleep.render(ui)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local bb = Blitbuffer.new(sw, sh, Screen.bb:getType())
    bb:fill(BG)
    local cw = sw - 2 * px(40)

    local file = ui and ui.document and ui.document.file or G_reader_settings:readSetting("lastfile")
    if file and (lfs.attributes(file, "mode") ~= "file" or not Data.isListed(file)) then file = nil end
    local meta = file and Data.bookMeta(file, false)
    local stats = Data.readingStats()

    local col = VerticalGroup:new{ align = "center" }
    local to_free = { col }

    if meta then
        -- Cover, scaled to fit about half the screen, in a thin white frame.
        local cover
        if ui and ui.bookinfo then
            local ok, c = pcall(ui.bookinfo.getCoverImage, ui.bookinfo, ui.document, file)
            if ok then cover = c end
        end
        if not cover then
            local m = Data.bookMeta(file, true)
            cover = m.cover_bb
        end
        local max_w, max_h = math.floor(sw * 0.52), math.floor(sh * 0.46)
        local cover_widget
        if cover then
            local s = math.min(max_w / cover:getWidth(), max_h / cover:getHeight())
            local cw2, ch2 = math.floor(cover:getWidth() * s), math.floor(cover:getHeight() * s)
            local scaled = cover:scale(cw2, ch2)
            cover:free()
            cover_widget = { w = cw2, h = ch2, bb = scaled }
        end

        local frame = math.max(2, px(3))
        local y = px(56)
        if cover_widget then
            local x = math.floor((sw - cover_widget.w) / 2)
            bb:paintRoundedRect(x - frame, y - frame, cover_widget.w + 2 * frame, cover_widget.h + 2 * frame,
                INK, px(6))
            bb:blitFrom(cover_widget.bb, x, y, 0, 0, cover_widget.w, cover_widget.h)
            cover_widget.bb:free()
            y = y + cover_widget.h + frame + px(30)
        else
            -- No cover: a big typographic title card instead.
            local card = textbox(meta.title or "", W.FONT_SERIF_BOLD, 40, math.floor(sw * 0.5), INK, 5)
            local ch = card:getSize().h
            local box_w, box_h = math.floor(sw * 0.52), math.max(ch + px(60), math.floor(sh * 0.36))
            local bx = math.floor((sw - box_w) / 2)
            bb:paintRoundedRect(bx, y, box_w, box_h, INK, px(10))
            bb:paintRoundedRect(bx + frame, y + frame, box_w - 2 * frame, box_h - 2 * frame, BG, px(8))
            card:paintTo(bb, math.floor((sw - card:getSize().w) / 2), y + math.floor((box_h - ch) / 2))
            card:free()
            y = y + box_h + px(30)
        end

        -- Title, author, progress.
        table.insert(col, textbox(meta.title or "", W.FONT_SERIF_BOLD, 24, cw, INK, 2))
        if meta.authors and meta.authors ~= "" then
            table.insert(col, VerticalSpan:new{ width = px(4) })
            table.insert(col, textbox(meta.authors, W.FONT_SANS_BOLD, 13, cw, SOFT, 1))
        end
        local pct = currentPercent(ui, meta)
        if pct and meta.status ~= "new" then
            table.insert(col, VerticalSpan:new{ width = px(16) })
            local bar_w = math.floor(sw * 0.5)
            table.insert(col, W.Bar:new{ width = bar_w, height = 4, percent = pct, fg = INK, bg = DIM })
            table.insert(col, VerticalSpan:new{ width = px(8) })
            local line = string.format("%d%%", math.floor(pct * 100 + 0.5))
            if meta.status == "complete" then line = _("Finished") .. " ★" end
            table.insert(col, W.text(line, W.FONT_SANS_BOLD, 13, { color = SOFT }))
        end

        -- One of your highlights from this book.
        local quote = pickHighlight(file)
        if quote then
            table.insert(col, VerticalSpan:new{ width = px(26) })
            table.insert(col, textbox("“" .. quote .. "”", W.FONT_SERIF, 15, math.floor(cw * 0.9), SOFT, 4))
        end

        col:paintTo(bb, math.floor((sw - col:getSize().w) / 2), y)
    else
        -- Nothing being read: the Shelfie wordmark and today's numbers.
        table.insert(col, W.text("Shelfie", W.FONT_SERIF_BOLD, 44, { color = INK }))
        table.insert(col, VerticalSpan:new{ width = px(10) })
        table.insert(col, W.text(_("Pick a book when you're back"), W.FONT_SANS_BOLD, 14, { color = SOFT }))
        local size = col:getSize()
        col:paintTo(bb, math.floor((sw - size.w) / 2), math.floor((sh - size.h) / 2) - px(40))
    end

    -- Footer: streak and today's minutes.
    if stats.available then
        local footer = HorizontalGroup:new{
            align = "center",
            IconWidget:new{
                file = Sleep.plugin_path .. "/icons/flame.white.svg",
                width = px(18), height = px(18), alpha = true,
            },
            HorizontalSpan:new{ width = px(8) },
            W.text(T(_("%1-day streak"), stats.streak)
                .. "  ·  " .. T(_("%1 min today"), stats.today_min), W.FONT_SANS_BOLD, 13, { color = SOFT }),
        }
        local fs = footer:getSize()
        footer:paintTo(bb, math.floor((sw - fs.w) / 2), sh - px(46) - fs.h)
        footer:free()
    end

    for _, w in ipairs(to_free) do w:free() end
    return bb
end

--- Install the hook (once per KOReader session).
function Sleep.install(plugin_path)
    Sleep.plugin_path = plugin_path
    if Sleep.installed then return end
    Sleep.installed = true
    local Screensaver = require("ui/screensaver")
    local original_setup = Screensaver.setup
    Screensaver.setup = function(ss, ...)
        original_setup(ss, ...)
        local settings = G_reader_settings:readSetting("shelfie") or {}
        if settings.sleep_screen == false then return end
        local ok, bb = pcall(Sleep.render, ss.ui)
        if ok and bb then
            if ss.image then ss.image:free() end
            ss.image = bb
            ss.image_file = nil
            ss.screensaver_type = "cover"
            ss.show_message = false
            ss.screensaver_background = "black"
        else
            logger.warn("Shelfie: sleep screen failed, using KOReader's:", bb)
        end
    end
end

return Sleep
