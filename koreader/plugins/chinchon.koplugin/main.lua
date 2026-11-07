local WidgetContainer = require("ui/widget/container/widgetcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextWidget = require("ui/widget/textwidget")
local Button = require("ui/widget/button")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")
local _ = require("gettext")

local Chinchon = WidgetContainer:extend({
    name = "chinchon",
})

function Chinchon:init()
    self.num_players = nil -- nil muestra el selector inicial de jugadores
    self.limit = 100
    self.scores = {}
    self.window = nil

    self.ui.menu:registerToMainMenu(self)
end

function Chinchon:addToMainMenu(menu_items)
    menu_items.chinchon = {
        text = _("Chinchón — Marcador"),
        sorting_hint = "tools",
        callback = function()
            self:show()
        end,
    }
end

function Chinchon:_makeText(text, font_size)
    return TextWidget:new({
        text = text,
        face = Font:getFace("cfont", font_size or 20),
    })
end

function Chinchon:_makeButton(text, callback, width, height, bordersize)
    return Button:new({
        text = text,
        callback = function()
            callback()
        end,
        width = width,
        height = height,
        bordersize = bordersize or 2,
        radius = 0,
        margin = 2,
        padding = 2,
    })
end

function Chinchon:_closeWindow(is_exiting)
    if self.window then
        UIManager:close(self.window)
        self.window = nil
        if is_exiting then
            UIManager:setDirty("all", "ui")
        end
    end
end

function Chinchon:_startGame(count)
    self.num_players = count
    self.scores = {}
    for i = 1, count do
        self.scores[i] = 0
    end
    self:show()
end

function Chinchon:_resetScores()
    if not self.num_players then return end
    for i = 1, self.num_players do
        self.scores[i] = 0
    end
    self:show()
end

function Chinchon:_toggleLimit()
    self.limit = (self.limit == 100) and 50 or 100
    self:show()
end

function Chinchon:_addScore(player_idx, delta)
    self.scores[player_idx] = self.scores[player_idx] + delta
    self:show()
end

function Chinchon:_getMaxActiveScore()
    local max_s = 0
    for i = 1, (self.num_players or 0) do
        local s = self.scores[i] or 0
        if s <= self.limit and s > max_s then
            max_s = s
        end
    end
    return max_s
end

function Chinchon:_reenganchar(player_idx)
    self.scores[player_idx] = self:_getMaxActiveScore()
    self:show()
end

-- PANTALLA 1: Selección de número de jugadores
function Chinchon:_buildSetupView()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local content_w = screen_w - 40
    local btn_w = math.floor((content_w - 16) / 2)
    local btn_h = math.max(64, math.floor(screen_h * 0.11))

    local rows = VerticalGroup:new({
        align = "center",
        self:_makeText(_("CHINCHÓN"), 28),
        self:_makeText(_("Selecciona cuántos jugadores sois:"), 20),
        HorizontalGroup:new({
            align = "center",
            self:_makeButton(_("2 Jugadores"), function() self:_startGame(2) end, btn_w, btn_h, 3),
            self:_makeButton(_("3 Jugadores"), function() self:_startGame(3) end, btn_w, btn_h, 3),
        }),
        HorizontalGroup:new({
            align = "center",
            self:_makeButton(_("4 Jugadores"), function() self:_startGame(4) end, btn_w, btn_h, 3),
            self:_makeButton(_("5 Jugadores"), function() self:_startGame(5) end, btn_w, btn_h, 3),
        }),
        HorizontalGroup:new({
            align = "center",
            self:_makeButton(_("6 Jugadores"), function() self:_startGame(6) end, content_w - 8, btn_h, 3),
        }),
        HorizontalGroup:new({
            align = "center",
            self:_makeButton(
                string.format(_("Límite: %d ptos (Cambiar)"), self.limit),
                function() self:_toggleLimit() end,
                btn_w,
                math.floor(btn_h * 0.8),
                2
            ),
            self:_makeButton(
                _("Salir"),
                function() self:_closeWindow(true) end,
                btn_w,
                math.floor(btn_h * 0.8),
                2
            ),
        }),
    })

    return rows
end

-- PANTALLA 2: Marcador rápido en partida
function Chinchon:_buildGameView()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local n = self.num_players

    local panel_w = screen_w - 20
    local btn_w_6 = math.floor((panel_w - 36) / 6)
    local btn_w_4 = math.floor((panel_w - 24) / 4)

    -- Ajuste dinámico de altura según cantidad de jugadores (2 a 6)
    local avail_h = screen_h - 130
    local row_block_h = math.floor(avail_h / n)
    local btn_h = math.max(38, math.min(68, math.floor(row_block_h * 0.52)))
    local font_sz = (n >= 5) and 18 or 21

    local main_list = VerticalGroup:new({
        align = "center",
        self:_makeText(
            string.format(_("CHINCHÓN (%d Jugadores) — Límite: %d ptos"), n, self.limit),
            19
        ),
    })

    for i = 1, n do
        local player_idx = i -- Capture this row's player for its button callbacks.
        local sc = self.scores[player_idx] or 0
        local is_out = sc > self.limit
        local status_label = is_out
            and string.format(_("Jugador %d:   %d ptos   [ELIMINADO]"), player_idx, sc)
            or string.format(_("Jugador %d:   %d ptos"), player_idx, sc)

        local header_group = HorizontalGroup:new({
            align = "center",
            self:_makeText(status_label, font_sz),
        })

        if is_out then
            local reeng_score = self:_getMaxActiveScore()
            table.insert(header_group, self:_makeButton(
                string.format(_("Reenganchar (%d)"), reeng_score),
                function() self:_reenganchar(player_idx) end,
                math.floor(panel_w * 0.42),
                math.max(32, math.floor(btn_h * 0.78)),
                2
            ))
        end

        local buttons_row = HorizontalGroup:new({
            align = "center",
            self:_makeButton(_("-10"), function() self:_addScore(player_idx, -10) end, btn_w_6, btn_h, 2),
            self:_makeButton(_("-1"), function() self:_addScore(player_idx, -1) end, btn_w_6, btn_h, 1),
            self:_makeButton(_("+1"), function() self:_addScore(player_idx, 1) end, btn_w_6, btn_h, 2),
            self:_makeButton(_("+2"), function() self:_addScore(player_idx, 2) end, btn_w_6, btn_h, 2),
            self:_makeButton(_("+5"), function() self:_addScore(player_idx, 5) end, btn_w_6, btn_h, 2),
            self:_makeButton(_("+10"), function() self:_addScore(player_idx, 10) end, btn_w_6, btn_h, 2),
        })

        local player_box = FrameContainer:new({
            background = Blitbuffer.COLOR_WHITE,
            bordersize = is_out and 1 or 2,
            padding = (n >= 6) and 3 or 6,
            margin = 2,
            VerticalGroup:new({
                align = "center",
                header_group,
                buttons_row,
            }),
        })

        table.insert(main_list, player_box)
    end

    local ctrl_h = math.max(40, math.min(56, math.floor(screen_h * 0.055)))
    local bottom_controls = HorizontalGroup:new({
        align = "center",
        self:_makeButton(_("Jugadores"), function()
            self.num_players = nil
            self:show()
        end, btn_w_4, ctrl_h, 2),
        self:_makeButton(_("A Cero"), function()
            self:_resetScores()
        end, btn_w_4, ctrl_h, 2),
        self:_makeButton(string.format(_("Lím: %d"), self.limit), function()
            self:_toggleLimit()
        end, btn_w_4, ctrl_h, 2),
        self:_makeButton(_("Salir"), function()
            self:_closeWindow(true)
        end, btn_w_4, ctrl_h, 2),
    })

    table.insert(main_list, bottom_controls)
    return main_list
end

function Chinchon:show()
    self:_closeWindow(false)

    local content_view
    if not self.num_players then
        content_view = self:_buildSetupView()
    else
        content_view = self:_buildGameView()
    end

    self.window = FrameContainer:new({
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        CenterContainer:new({
            dimen = Screen:getSize(),
            content_view,
        }),
    })

    UIManager:show(self.window)
    UIManager:setDirty(self.window, "ui")
    UIManager:setDirty("all", "ui")
end

return Chinchon
