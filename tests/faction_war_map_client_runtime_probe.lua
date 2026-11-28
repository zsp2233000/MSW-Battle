-- Maker `client`, dispatched right after faction_war_map_runtime_probe.lua (server_main) in the same Play.
-- Drives the map through its button, the M key handler and the pushed boards. Final line: [VRF][MapProbe] CLIENT PASS.
-- With CAPTURE in both scripts, capture at [VRF][FrontlineProbe] BEFORE and AFTER.
local CAPTURE = false
local ui = _FactionWarMapUI
local mapPath = "Overlay/Window/Map/Content"
local linksPath = mapPath .. "/Links/Link"
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
local function colorMatches(actual, expected)
    return math.abs(actual.r - expected.r) < 0.01 and math.abs(actual.g - expected.g) < 0.01
        and math.abs(actual.b - expected.b) < 0.01 and math.abs(actual.a - expected.a) < 0.01
end
local function checkBar(slot, split, firstColor, secondColor)
    local path = linksPath .. slot
    local bar, first, second = ui:Ui(path), ui:Ui(path .. "/First"), ui:Ui(path .. "/Second")
    assert(bar.Enable and first.Enable and second.Enable == (split < 1), "link " .. slot .. " visible segments")
    local size = bar.UITransformComponent.RectSize
    local link = ui._T.links[slot]
    local from = ui:Ui(mapPath .. "/Towns/" .. link.a).UITransformComponent.anchoredPosition
    local to = ui:Ui(mapPath .. "/Towns/" .. link.b).UITransformComponent.anchoredPosition
    local dx, dy = to.x - from.x, to.y - from.y
    assert(size.x < math.sqrt(dx * dx + dy * dy), "link " .. slot .. " splits the span between crests, not centre to centre")
    local firstSize, secondSize = first.UITransformComponent.RectSize, second.UITransformComponent.RectSize
    assert(size.x > 0 and math.abs(firstSize.x / size.x - split) < 0.01, "link " .. slot .. " first share")
    assert(math.abs((firstSize.x + secondSize.x) / size.x - 1) < 0.01, "link " .. slot .. " segments cover the full bar")
    assert(math.abs(firstSize.y * ui._T.zoom - 8) < 0.1 and math.abs(secondSize.y - firstSize.y) < 0.01, "link " .. slot .. " zoom-independent thickness")
    assert(colorMatches(first.SpriteGUIRendererComponent.Color, firstColor), "link " .. slot .. " first color")
    if split < 1 then assert(colorMatches(second.SpriteGUIRendererComponent.Color, secondColor), "link " .. slot .. " second color") end
end
local ok, reason = pcall(function()
    local player = _UserService.LocalPlayer
    assert(await(function() return _FactionWar:IsTown(player.CurrentMapName) end, 20), "the server moved the player into a town")
    local here = player.CurrentMapName
    assert(await(function() return ui:Ui("OpenButton").Enable end, 5), "entry button shown in a town")
    assert(not ui:Ui("Overlay").Enable, "map starts closed")

    -- 1. The button opens the map and the server answers with the board.
    ui:Ui("OpenButton"):SendEvent(ButtonClickEvent(ui:Ui("OpenButton")))
    assert(ui:Ui("Overlay").Enable and ui._T.open, "button opened the map")
    assert(await(function() return strengthOf("gushan") == 80 end, 10), "first board arrived")
    assert(text("Overlay/Window/Side/Rows/gushan/Value") == "80/100", "side row value")
    assert(text("Overlay/Window/Side/Rows/nanzih/Owner") == "A 方・主城", "capital row owner: " .. text("Overlay/Window/Side/Rows/nanzih/Owner"))
    assert(ui:Ui("Overlay/Window/Map/Content/Towns/nanzih/Capital").Enable and not ui:Ui("Overlay/Window/Map/Content/Towns/zuoying/Capital").Enable, "capital tags")
    assert(await(function() return text("Overlay/Window/Side/Faction") ~= "讀取中…" end, 5), "faction answered")
    local faction = ui._T.faction
    local aligned = _FactionWarTownDocument:IsFaction(faction)
    assert(not CAPTURE or aligned, "before/after captures need a local player with a faction")
    local war = _FactionWarUI
    local a = faction == "A" and war.AllyTownColor or faction == "B" and war.EnemyTownColor or war.NeutralTownColor
    local b = faction == "B" and war.AllyTownColor or faction == "A" and war.EnemyTownColor or war.NeutralTownColor
    for id, owner in pairs({ zuoying = "A", gushan = "B" }) do
        local actual = ui:Ui("Overlay/Window/Map/Content/Districts/" .. id).SpriteGUIRendererComponent.Color
        local expected = _FactionWarUI:TownColor(faction, owner)
        assert(math.abs(actual.r - expected.r) < 0.01 and math.abs(actual.b - expected.b) < 0.01
            and math.abs(actual.a - ui.DistrictAlpha) < 0.01, "district tinted by the viewer's stance: " .. id)
    end
    local fill = ui:Ui("Overlay/Window/Side/Rows/zuoying/Bar/Fill").UITransformComponent.RectSize.x
    assert(math.abs(fill - ui.BarWidth * 0.8) < 0.5, "bar width follows strength: " .. tostring(fill))
    if CAPTURE then
        local north = ui:Ui(mapPath .. "/Towns/nanzih").UITransformComponent.anchoredPosition
        local south = ui:Ui(mapPath .. "/Towns/yancheng").UITransformComponent.anchoredPosition
        ui:SetMapView(8, ui:CenterOffset(Vector2((north.x + south.x) / 2, (north.y + south.y) / 2), 8))
    end
    checkBar(1, 1, a)
    checkBar(2, aligned and 0.5 or 1, a, b)
    checkBar(3, 1, b)
    log("[VRF][FrontlineProbe] BEFORE PASS 80:80 faction=" .. faction)
    for _, id in ipairs(_FactionWarTownDocument.TownOrder) do
        assert(not isvalid(ui:Ui(mapPath .. "/Towns/" .. id .. "/Strength")), "no map strength label: " .. id)
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
    log("[VRF][MapProbe] CLIENT1 PASS here=" .. here .. " faction=" .. text("Overlay/Window/Side/Faction"))

    -- 2. A board change is pushed while the map is open; the town HUD follows the current town.
    assert(await(function() return strengthOf("gushan") == 20 end, 20), "pushed board arrived")
    assert(text("Overlay/Window/Side/Rows/gushan/Value") == "20/100", "pushed strength shown in side row")
    checkBar(1, 1, a)
    checkBar(2, aligned and 0.8 or 1, a, b)
    checkBar(3, 1, b)
    log("[VRF][FrontlineProbe] AFTER PASS 80:20 faction=" .. faction)
    local hud = _EntityService:GetEntityByPath("/ui/FactionWarGroup/TownHUD/Strength").TextGUIRendererComponent.Text
    assert(string.find(hud, "兵力 " .. tostring(strengthOf(here)), 1, true) ~= nil, "town HUD in step: " .. hud)
    log("[VRF][MapProbe] CLIENT2 PASS pushed gushan=20")

    -- 3. M closes it; nothing is pushed while closed.
    if CAPTURE then wait(8) end
    ui:HandleKey(KeyDownEvent(KeyboardKey.M))
    assert(not ui:Ui("Overlay").Enable and not ui._T.open, "M closed the map")
    wait(4)
    assert(strengthOf("gushan") == 20, "no board pushed to a closed map")

    -- 4. M opens it again with a fresh read; leaving the town closes it and hides the button.
    ui:HandleKey(KeyDownEvent(KeyboardKey.M))
    assert(ui._T.open, "M reopened the map")
    assert(await(function() return strengthOf("gushan") == 40 end, 10), "reopen reads the board fresh")
    assert(await(function() return player.CurrentMapName == "formationlobby" end, 25), "the server moved the player to the lobby")
    assert(await(function() return not ui._T.open and not ui:Ui("Overlay").Enable and not ui:Ui("OpenButton").Enable end, 5), "leaving the town closed the map and hid the button")
    log("[VRF][MapProbe] CLIENT PASS")
end)
if not ok then log_error("[VRF][MapProbe] CLIENT FAIL " .. tostring(reason)) end
