-- Maker `client`, dispatched right after faction_war_map_runtime_probe.lua (server_main) in the same Play.
-- Drives the map through its button, the M key handler and the pushed boards. Final line: [VRF][MapProbe] CLIENT PASS.
local ui = _FactionWarMapUI
local function await(predicate, seconds)
    for _ = 1, math.floor((seconds or 10) * 10) do
        if predicate() then return true end
        wait(0.1)
    end
    return false
end
local function strengthOf(id)
    for _, town in ipairs(ui._T.board or {}) do
        if town.id == id then return town.strength end
    end
    return nil
end
local function text(path) return ui:Ui(path).TextGUIRendererComponent.Text end
local ok, reason = pcall(function()
    local player = _UserService.LocalPlayer
    assert(await(function() return _FactionWar:IsTown(player.CurrentMapName) end, 20), "the server moved the player into a town")
    local here = player.CurrentMapName
    assert(await(function() return ui:Ui("OpenButton").Enable end, 5), "entry button shown in a town")
    assert(not ui:Ui("Overlay").Enable, "map starts closed")

    -- 1. The button opens the map and the server answers with the board.
    ui:Ui("OpenButton"):SendEvent(ButtonClickEvent(ui:Ui("OpenButton")))
    assert(ui:Ui("Overlay").Enable and ui._T.open, "button opened the map")
    assert(await(function() return strengthOf("gushan") == 70 end, 10), "first board arrived")
    assert(text("Overlay/Window/Map/Content/Towns/zuoying/Strength") == "兵力 80/100", "map strength label: " .. text("Overlay/Window/Map/Content/Towns/zuoying/Strength"))
    assert(text("Overlay/Window/Side/Rows/gushan/Value") == "70/100", "side row value")
    assert(text("Overlay/Window/Side/Rows/nanzih/Owner") == "紅方・主城", "capital row owner: " .. text("Overlay/Window/Side/Rows/nanzih/Owner"))
    assert(ui:Ui("Overlay/Window/Map/Content/Towns/nanzih/Capital").Enable and not ui:Ui("Overlay/Window/Map/Content/Towns/zuoying/Capital").Enable, "capital tags")
    local red = ui:Ui("Overlay/Window/Map/Content/Districts/zuoying").SpriteGUIRendererComponent.Color
    local blue = ui:Ui("Overlay/Window/Map/Content/Districts/gushan").SpriteGUIRendererComponent.Color
    assert(red.r > red.b and blue.b > blue.r and math.abs(red.a - ui.DistrictAlpha) < 0.01, "districts tinted by owner")
    local fill = ui:Ui("Overlay/Window/Side/Rows/zuoying/Bar/Fill").UITransformComponent.RectSize.x
    assert(math.abs(fill - ui.BarWidth * 0.8) < 0.5, "bar width follows strength: " .. tostring(fill))
    for slot = 1, 3 do
        local bar = ui:Ui("Overlay/Window/Map/Content/Links/Link" .. slot)
        assert(bar.Enable and bar.UITransformComponent.RectSize.x > 0, "link " .. slot .. " drawn")
    end
    for _, id in ipairs(_FactionWar.TownOrder) do
        assert(ui:Ui("Overlay/Window/Side/Rows/" .. id .. "/Here").Enable == (id == here), "here line in the list on " .. id)
        assert(ui:Ui("Overlay/Window/Map/Content/Towns/" .. id .. "/Arrow").Enable == (id == here), "here arrow on " .. id)
    end
    -- The arrow is an animationclip set to loop: it keeps changing frames well past one pass of its four frames.
    local arrow = ui:Ui("Overlay/Window/Map/Content/Towns/" .. here .. "/Arrow")
    -- Its frames are one image moved by pivot, which a UI sprite ignores, so the client moves the arrow itself: it must bob.
    local frames = 0
    local heights = {}
    local handler = arrow:ConnectEvent(SpriteGUIAnimPlayerChangeFrameEvent, function() frames = frames + 1 end)
    for _ = 1, 40 do
        heights[tostring(math.floor(arrow.UITransformComponent.anchoredPosition.y + 0.5))] = true
        wait(0.1)
    end
    arrow:DisconnectEvent(SpriteGUIAnimPlayerChangeFrameEvent, handler)
    local distinct = 0
    for _ in pairs(heights) do distinct = distinct + 1 end
    assert(frames > 4, "the arrow keeps animating past one pass: " .. tostring(frames) .. " frame changes in 4 s")
    assert(distinct >= 3, "the arrow bobs: " .. tostring(distinct) .. " heights seen")
    log("[VRF][MapProbe] arrow frames in 4 s=" .. tostring(frames) .. " heights=" .. tostring(distinct))
    assert(await(function() return text("Overlay/Window/Side/Faction") ~= "讀取中…" end, 5), "faction answered")
    log("[VRF][MapProbe] CLIENT1 PASS here=" .. here .. " faction=" .. text("Overlay/Window/Side/Faction"))

    -- 2. A board change is pushed while the map is open; the town HUD follows the current town.
    assert(await(function() return strengthOf("gushan") == 50 end, 15), "pushed board arrived")
    assert(text("Overlay/Window/Map/Content/Towns/gushan/Strength") == "兵力 50/100", "pushed strength shown")
    local hud = _EntityService:GetEntityByPath("/ui/FactionWarGroup/TownHUD/Strength").TextGUIRendererComponent.Text
    assert(string.find(hud, "兵力 " .. tostring(strengthOf(here)), 1, true) ~= nil, "town HUD in step: " .. hud)
    log("[VRF][MapProbe] CLIENT2 PASS pushed gushan=50")

    -- 3. M closes it; nothing is pushed while closed.
    ui:HandleKey(KeyDownEvent(KeyboardKey.M))
    assert(not ui:Ui("Overlay").Enable and not ui._T.open, "M closed the map")
    wait(4)
    assert(strengthOf("gushan") == 50, "no board pushed to a closed map")

    -- 4. M opens it again with a fresh read; leaving the town closes it and hides the button.
    ui:HandleKey(KeyDownEvent(KeyboardKey.M))
    assert(ui._T.open, "M reopened the map")
    assert(await(function() return strengthOf("gushan") == 40 end, 10), "reopen reads the board fresh")
    assert(await(function() return player.CurrentMapName == "formationlobby" end, 25), "the server moved the player to the lobby")
    assert(await(function() return not ui._T.open and not ui:Ui("Overlay").Enable and not ui:Ui("OpenButton").Enable end, 5), "leaving the town closed the map and hid the button")
    log("[VRF][MapProbe] CLIENT PASS")
end)
if not ok then log_error("[VRF][MapProbe] CLIENT FAIL " .. tostring(reason)) end
