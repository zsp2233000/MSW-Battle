-- #129 Maker end-to-end with the REAL local client: the target selection opens zoomed on the departure town, a tap on a city crest opens the same
-- confirmation as the side list, a REAL drag does not pick, a crest that cannot be picked reacts to nothing, and the view is still the full overview.
-- This probe uses the fixture of tests/target_select_client_runtime_probe.lua (#124): run ITS SETUP (CAPITAL = false: the real profile is A in Zuoying, Gushan is
-- B's with 55 left, Yancheng is B's capital and is not adjacent) and ITS CLEANUP unchanged, with the same REAL. Disposable save only; this probe writes nothing itself.
-- Edit STEP by substitution (client context for every step below). maker_mouse_input does NOT reach the map's touch surface (it is engine UI; the mouse tool
-- logged no touch event at all in the Maker run), so a click and a drag are sent the way faction_war_map_viewport_runtime_probe.lua sends its drag: UITouchDownEvent /
-- UITouchDragEvent / UITouchUpEvent on the real touch surface (Overlay/Window/Map/Input) with screen points, through the production handlers (BeginMapDrag, DragMap,
-- EndMapDrag, IsClick, ClickMap). Buttons are pressed with ButtonClickEvent. Not exercised: the OS-level pointer.
--
-- WHERE A CREST IS ON THE SCREEN: MARKERS prints, for every town, the crest's position in the viewport (UI units) and on the screen in pixels, from the real conversion
-- _UILogic:ScreenToLocalUIPosition solved for the screen (the same conversion the click handler uses), and the TAP_ / DRAG_ steps use the same points.
-- Take the screenshots with the `screenshot` console command.
--
-- Order (one step per run, in this order):
--   #124 SETUP (server_main)
--   1 VIEW_OVERVIEW (screenshot 129-view-overview.png)  2 SELECT_ZOOM (screenshot 129-select-zoom.png)  3 MARKERS  4 TAP_TARGET
--   5 CLICK_OPENED (screenshot 129-click-confirm.png)  6 DECLINE  7 TAP_ORIGIN  8 CLICK_DIM
--   9 DRAG_TARGET  10 DRAG_NO_PICK (screenshot 129-drag-no-pick.png)
--   11 RECENTER  12 HIT_REACH  13 CLOSE
--   #124 CLEANUP (server_main)
-- Regression after CLOSE: open the view (M key) and dispatch tests/faction_war_map_viewport_runtime_probe.lua (the wheel and the drag are unchanged).
-- Final lines: [VRF][TargetClick] <STEP> PASS. Any FAIL is a failure, and so is a missing `[VRF][FactionWarMap] ui click town=<id> selectable=<bool>` line after
-- a tap (gushan true after TAP_TARGET, zuoying false after TAP_ORIGIN) or one after the drag (the drag must log `drag offset=` and no `ui click`).
local STEP = "VIEW_OVERVIEW"
local ORIGIN, TARGET, DIM_FAR = "zuoying", "gushan", "yancheng"
local ORIGIN_START, TARGET_START = 100, 55
local DRAG_PX = 150
local function await(predicate, count)
    for _ = 1, count or 100 do if predicate() then return true end wait(0.1) end
    return false
end
local ui = _FactionWarMapUI
local state = ui._T.clickProbe or {}
ui._T.clickProbe = state
local function text(path) return ui:Ui(path).TextGUIRendererComponent.Text end
local function row(id) return "Overlay/Window/Side/Rows/" .. id end
local function click(path)
    local entity = ui:Ui(path)
    assert(isvalid(entity) and entity.Enable, path .. " is shown")
    entity:SendEvent(ButtonClickEvent(entity))
end
local highlight = "<color=" .. _FactionWarUI.TownNameHighlightHex .. ">"
local function name(id) return highlight .. _FactionWarTownDocument.TownNames[id] .. "</color>" end
local function strengthText(value) return "兵力 " .. tostring(value) .. " / 100" end
local function f(value) return string.format("%.1f", value) end
local function anchored(id) return ui:Ui(ui.ViewPath .. "/Content/Towns/" .. id).UITransformComponent.anchoredPosition end
local function viewPoint(id) return ui:TownViewPoint(anchored(id), ui._T.zoom, ui._T.mapOffset) end
-- Screen pixel of a point of the viewport (UI units): the linear inverse of ScreenToLocalUIPosition, found from the two corners of the screen.
local function screenOf(localPoint)
    local transform = ui:Ui(ui.ViewPath).UITransformComponent
    local width, height = _UILogic.ScreenWidth, _UILogic.ScreenHeight
    local a = _UILogic:ScreenToLocalUIPosition(Vector2(0, 0), transform)
    local b = _UILogic:ScreenToLocalUIPosition(Vector2(width, height), transform)
    return Vector2((localPoint.x - a.x) / ((b.x - a.x) / width), (localPoint.y - a.y) / ((b.y - a.y) / height))
end
local function marks(id) return ui:Ui(ui.ViewPath .. "/Content/Towns/" .. id .. "/Mark").Enable, ui:Ui(ui.ViewPath .. "/Content/Towns/" .. id .. "/Frame").Enable end
-- A tap or a drag on the touch surface, in screen pixels (the events carry screen points).
local function touch(from, to)
    local input = ui:Ui(ui.ViewPath .. "/Input")
    assert(isvalid(input), "the map's touch surface exists")
    input:SendEvent(UITouchDownEvent(input, -1, from))
    if to ~= nil then
        local steps = 6
        for i = 1, steps do
            input:SendEvent(UITouchDragEvent(input, Vector2(0, 0), -1, Vector2(from.x + (to.x - from.x) * i / steps, from.y + (to.y - from.y) * i / steps)))
        end
    end
    input:SendEvent(UITouchUpEvent(input, -1, to or from))
end
local function noWindow() return not ui:Ui("Confirm").Enable and ui._T.selected == nil end

local ok, failure = pcall(function()
    assert(Environment:IsMakerPlay(), "Maker Play required")
    if STEP == "VIEW_OVERVIEW" then
        local player = _UserService.LocalPlayer
        assert(player.CurrentMapName == ORIGIN, "the client stands in " .. ORIGIN .. " (run the #124 SETUP)")
        assert(not ui._T.open, "the map starts closed")
        ui:HandleKey(KeyDownEvent(KeyboardKey.M))
        assert(ui._T.open and ui._T.mode == "view" and ui:Ui("Overlay").Enable, "M opened the view")
        assert(await(function() return text(row(TARGET) .. "/Value") ~= "—" end, 100), "the server answered the view")
        local offset = ui._T.mapOffset
        assert(ui._T.zoom == 1 and offset.x == 0 and offset.y == 0 and ui:Ui(ui.ViewPath .. "/Content").UITransformComponent.UIScale.x == 1, "the view opens at the full overview: zoom=" .. tostring(ui._T.zoom))
        for _, id in ipairs(_FactionWarTownDocument.TownOrder) do
            local mark, frame = marks(id)
            assert(not mark and not frame, id .. ": the view has no marks")
        end
        log("[VRF][TargetClick] VIEW_OVERVIEW PASS zoom=1 offset=(0,0) no marks; take the screenshot, then run SELECT_ZOOM")
    elseif STEP == "SELECT_ZOOM" then
        if ui._T.open then ui:Close() end
        ui:BeginSelect()
        -- What the NPC's InteractionEvent handler sends: the real RPC and the real answer.
        _FactionWarAttack:RequestSelect()
        assert(await(function() return ui._T.open and ui._T.mode == "select" and text(row(TARGET) .. "/Value") ~= "—" end, 100), "the server's answer opened the map in selection mode")
        assert(ui._T.zoom == ui.SelectZoom and ui:Ui(ui.ViewPath .. "/Content").UITransformComponent.UIScale.x == ui.SelectZoom, "the selection opens at " .. tostring(ui.SelectZoom) .. "x: zoom=" .. tostring(ui._T.zoom))
        local centre = viewPoint(ORIGIN)
        assert(math.abs(centre.x) < 1 and math.abs(centre.y) < 1, "centred on the departure town: (" .. f(centre.x) .. "," .. f(centre.y) .. ")")
        assert(ui:Ui(ui.ViewPath .. "/Content/Towns/" .. ORIGIN .. "/Name").Visible, "at 4x the town names are shown")
        for _, id in ipairs(_FactionWarTownDocument.TownOrder) do
            local mark, frame = marks(id)
            assert(mark == (id == TARGET) and not frame, id .. ": only the listed town is marked, none is framed")
        end
        log("[VRF][TargetClick] SELECT_ZOOM PASS zoom=" .. tostring(ui._T.zoom) .. " origin=" .. ORIGIN .. " at the middle; take the screenshot, then run MARKERS")
    elseif STEP == "MARKERS" then
        assert(ui._T.open and ui._T.mode == "select", "the selection is open")
        local width, height = _UILogic.ScreenWidth, _UILogic.ScreenHeight
        local perUnit = ui:ScreenPixelsPerUnit()
        log("[VRF][TargetClick] screen=" .. tostring(width) .. "x" .. tostring(height) .. " pixelsPerUnit=" .. f(perUnit) .. " hitRadius=" .. f(ui:HitRadius(ui._T.zoom, perUnit)) .. " units = " .. f(ui:HitRadius(ui._T.zoom, perUnit) * perUnit) .. " px")
        for _, id in ipairs(_FactionWarTownDocument.TownOrder) do
            local point = viewPoint(id)
            local screen = screenOf(point)
            log("[VRF][TargetClick] marker " .. id .. " view=(" .. f(point.x) .. "," .. f(point.y) .. ") screen=(" .. f(screen.x) .. "," .. f(screen.y) .. ") topLeft=(" .. f(screen.x) .. "," .. f(height - screen.y) .. ") selectable=" .. tostring(ui._T.targets[id] == true))
        end
        local target = screenOf(viewPoint(TARGET))
        log("[VRF][TargetClick] MARKERS PASS the " .. TARGET .. " crest is at screen=(" .. f(target.x) .. "," .. f(target.y) .. "); run TAP_TARGET")
    elseif STEP == "TAP_TARGET" then
        assert(ui._T.open and ui._T.mode == "select" and noWindow(), "the selection is open, no window")
        touch(screenOf(viewPoint(TARGET)))
        log("[VRF][TargetClick] TAP_TARGET PASS tapped the " .. TARGET .. " crest; run CLICK_OPENED")
    elseif STEP == "CLICK_OPENED" then
        assert(await(function() return ui._T.selected == TARGET end, 30), "the tap on the crest picked " .. TARGET .. " (selected=" .. tostring(ui._T.selected) .. "; see the ui click lines)")
        assert(ui:Ui("Confirm").Enable and not ui._T.pending, "the confirmation is open and nothing was sent")
        assert(text("Confirm/Window/Title") == "進攻 " .. name(TARGET) .. "？", "the title: " .. text("Confirm/Window/Title"))
        assert(text("Confirm/Window/Origin") == "出發城 " .. name(ORIGIN) .. "　" .. strengthText(ORIGIN_START), "the departure line: " .. text("Confirm/Window/Origin"))
        assert(text("Confirm/Window/Target") == "目標城 " .. name(TARGET) .. "　" .. strengthText(TARGET_START), "the target line: " .. text("Confirm/Window/Target"))
        assert(text("Confirm/Window/Note") == "" and text("Confirm/Window/Yes") == "是" and text("Confirm/Window/No") == "否", "the same window as the row opens")
        local mark, frame = marks(TARGET)
        assert(mark and frame, "the picked crest is marked and framed")
        log("[VRF][TargetClick] CLICK_OPENED PASS title=" .. text("Confirm/Window/Title") .. "; take the screenshot, then run DECLINE")
    elseif STEP == "DECLINE" then
        click("Confirm/Window/No")
        assert(noWindow() and ui._T.open and ui._T.mode == "select", "No closed the window and kept the map")
        local mark, frame = marks(TARGET)
        assert(mark and not frame, "the crest is marked again, not framed")
        log("[VRF][TargetClick] DECLINE PASS")
    elseif STEP == "TAP_ORIGIN" then
        assert(ui._T.open and noWindow(), "the map is open, no window")
        touch(screenOf(viewPoint(ORIGIN)))
        log("[VRF][TargetClick] TAP_ORIGIN PASS tapped the dimmed " .. ORIGIN .. " crest; run CLICK_DIM")
    elseif STEP == "CLICK_DIM" then
        -- The dimmed town is the departure town, at the middle of the viewport (its position is in the MARKERS lines).
        assert(noWindow() and ui._T.open, "a tap on the dimmed " .. ORIGIN .. " crest opened nothing")
        for _, id in ipairs(_FactionWarTownDocument.TownOrder) do
            local _, frame = marks(id)
            assert(not frame, id .. ": no frame")
        end
        local dim = ui:Ui(ui.ViewPath .. "/Content/Towns/" .. ORIGIN .. "/Crest").SpriteGUIRendererComponent.Color.a
        assert(math.abs(dim - ui.DimCrestAlpha) < 0.01, "the dimmed crest is drawn dimmer: " .. tostring(dim))
        log("[VRF][TargetClick] CLICK_DIM PASS the dimmed crest reacted to nothing")
    elseif STEP == "DRAG_TARGET" then
        assert(ui._T.open and noWindow(), "the map is open, no window")
        state.zoom, state.offset = ui._T.zoom, Vector2(ui._T.mapOffset.x, ui._T.mapOffset.y)
        local from = screenOf(viewPoint(TARGET))
        touch(from, Vector2(from.x + DRAG_PX, from.y))
        log("[VRF][TargetClick] DRAG_TARGET PASS pressed on the " .. TARGET .. " crest, moved " .. tostring(DRAG_PX) .. " px, released; run DRAG_NO_PICK")
    elseif STEP == "DRAG_NO_PICK" then
        assert(state.offset ~= nil, "run DRAG_TARGET first")
        assert(noWindow() and ui._T.open, "the drag that started on the crest picked nothing (selected=" .. tostring(ui._T.selected) .. ")")
        local dx, dy = ui._T.mapOffset.x - state.offset.x, ui._T.mapOffset.y - state.offset.y
        assert(ui._T.zoom == state.zoom and math.sqrt(dx * dx + dy * dy) > 20, "and the map was panned: moved (" .. f(dx) .. "," .. f(dy) .. ")")
        log("[VRF][TargetClick] DRAG_NO_PICK PASS panned (" .. f(dx) .. "," .. f(dy) .. ") units, nothing picked; take the screenshot")
    elseif STEP == "RECENTER" then
        ui:FocusOrigin(ORIGIN)
        local centre = viewPoint(ORIGIN)
        assert(ui._T.zoom == ui.SelectZoom and math.abs(centre.x) < 1 and math.abs(centre.y) < 1, "back on the departure town")
        log("[VRF][TargetClick] RECENTER PASS")
    elseif STEP == "HIT_REACH" then
        -- The click handler itself (ClickMap) with screen points around the crest: 20 px always hits, and far outside the reach nothing does, at every zoom.
        assert(ui.MinHitPx >= 24, "the reach is at least 24 screen px")
        for _, zoom in ipairs({ 1, 2, 4, 12 }) do
            ui:SetMapView(zoom, ui:CenterOffset(anchored(TARGET), zoom))
            local perUnit = ui:ScreenPixelsPerUnit()
            local radiusPx = ui:HitRadius(zoom, perUnit) * perUnit
            assert(radiusPx >= 24 - 1e-6, "the reach at " .. tostring(zoom) .. "x is " .. f(radiusPx) .. " px")
            local at = screenOf(viewPoint(TARGET))
            ui:ClickMap(Vector2(at.x - 20, at.y))
            assert(ui._T.selected == TARGET, "20 px from the crest picks it at " .. tostring(zoom) .. "x")
            ui:Decline()
            ui:ClickMap(Vector2(at.x - (radiusPx + 30), at.y))
            assert(ui._T.selected == nil, "30 px beyond the reach picks nothing at " .. tostring(zoom) .. "x")
            log("[VRF][TargetClick] HIT_REACH zoom=" .. tostring(zoom) .. " radius=" .. f(radiusPx) .. " px ok")
        end
        ui:FocusOrigin(ORIGIN)
        log("[VRF][TargetClick] HIT_REACH PASS")
    elseif STEP == "CLOSE" then
        if ui._T.open then click("Overlay/Window/Close") end
        assert(not ui._T.open and noWindow() and not ui:Ui("Overlay").Enable, "the map is closed and nothing is selected")
        log("[VRF][TargetClick] CLOSE PASS")
    else
        error("unknown STEP: " .. STEP)
    end
end)
if not ok then log_error("[VRF][TargetClick] " .. STEP .. " FAIL " .. tostring(failure)) end
