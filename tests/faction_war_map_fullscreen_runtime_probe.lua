-- #132 Maker client probe: the world map opens nearly full screen. Run it in the CLIENT of a fresh Play, one step per dispatch (edit STEP by substitution), with the real
-- local player standing in a town and the isolated board of the #130 probe: dispatch tests/faction_war_stance_runtime_probe.lua with FACTION = "A" and STEP = "SETUP" in
-- server_main first (it also writes the board that gives the screenshots their colours), and with STEP = "CLEANUP" in server_main LAST, before stopping Play.
-- Nothing is written by this probe. Every rectangle is measured on the SCREEN, in pixels, from the real conversion _UILogic:ScreenToLocalUIPosition (the one the click, the
-- drag and the wheel use): for the transform it is given, local = (screen - the pivot's screen pixel) / (the transform's own scale), so the screen rectangle of a node is
-- found from two screen points. The conversion ignores the scale of a PARENT (Maker run of #132: a child of the scaled viewport reported 1:1), so the map content is
-- placed from the viewport's own measure.
--
-- Order (one step per run, in this order; take the screenshots with the `screenshot` console command):
--   #130 SETUP (server_main, FACTION = "A")
--   1 OPEN (screenshot 132-open.png)  2 MASK  3 CENTRE  4 PANEL  5 ZOOM_COVER (screenshot 132-zoom-cover.png)  6 TOUCH  7 CREST_CLICK  8 CLOSE
--   #130 CLEANUP (server_main)
-- Regression after CLOSE: open the map (M key), dispatch tests/faction_war_map_viewport_runtime_probe.lua (the wheel and the drag are unchanged), close it again.
-- Final lines: [VRF][MapFullscreen] <STEP> PASS. Any FAIL is a failure.
local STEP = "OPEN"
local function await(predicate, count)
    for _ = 1, count or 100 do if predicate() then return true end wait(0.1) end
    return false
end
local ui = _FactionWarMapUI
local SIDE = "Overlay/Window/Side"
local function near(a, b, tolerance) return math.abs(a - b) <= (tolerance or 1) end
local function f(value) return string.format("%.1f", value) end
-- The screen rectangle of a node (pixels, the origin at the bottom left of the screen): two screen points give the units per pixel and the screen pixel of the pivot.
local function frame(path)
    local transform = ui:Ui(path).UITransformComponent
    local a = _UILogic:ScreenToLocalUIPosition(Vector2(0, 0), transform)
    local b = _UILogic:ScreenToLocalUIPosition(Vector2(100, 100), transform)
    local kx, ky = (b.x - a.x) / 100, (b.y - a.y) / 100
    local pivotX, pivotY = -a.x / kx, -a.y / ky
    local size, pivot = transform.RectSize, transform.Pivot
    local left, bottom = pivotX - pivot.x * size.x / kx, pivotY - pivot.y * size.y / ky
    return { left = left, bottom = bottom, right = left + size.x / kx, top = bottom + size.y / ky, perUnit = 1 / kx }
end
local function middle(rect) return (rect.left + rect.right) / 2, (rect.bottom + rect.top) / 2 end
-- The map content: the viewport's own measure turns its offset and its zoomed size into pixels.
local function contentFrame()
    local view = frame(ui.ViewPath)
    local content = ui:Ui(ui.ViewPath .. "/Content").UITransformComponent
    local cx, cy = middle(view)
    cx, cy = cx + content.anchoredPosition.x * view.perUnit, cy + content.anchoredPosition.y * view.perUnit
    local halfX = content.RectSize.x * content.UIScale.x * view.perUnit / 2
    local halfY = content.RectSize.y * content.UIScale.y * view.perUnit / 2
    return { left = cx - halfX, right = cx + halfX, bottom = cy - halfY, top = cy + halfY }
end
local function covers(outer, inner, slack) slack = slack or 1 return inner.left >= outer.left - slack and inner.right <= outer.right + slack and inner.bottom >= outer.bottom - slack and inner.top <= outer.top + slack end
local function overlapArea(a, b)
    local w = math.min(a.right, b.right) - math.max(a.left, b.left)
    local h = math.min(a.top, b.top) - math.max(a.bottom, b.bottom)
    return (w > 0 and h > 0) and w * h or 0
end
-- Where a crest is on the screen, in pixels: the viewport's own measure turns its position in the viewport into pixels.
local function crestOnScreen(id)
    local view = frame(ui.ViewPath)
    local vx, vy = middle(view)
    local anchored = ui:Ui(ui.ViewPath .. "/Content/Towns/" .. id).UITransformComponent.anchoredPosition
    local point = ui:TownViewPoint(anchored, ui._T.zoom, ui._T.mapOffset)
    return Vector2(vx + point.x * view.perUnit, vy + point.y * view.perUnit)
end
-- A tap on the touch surface, the way faction_war_map_viewport_runtime_probe.lua sends its drag (maker_mouse_input does not reach the surface).
local function tap(screen)
    local input = ui:Ui(ui.ViewPath .. "/Input")
    input:SendEvent(UITouchDownEvent(input, -1, screen))
    input:SendEvent(UITouchUpEvent(input, -1, screen))
end
local function sibling(path) return _UILogic:GetSiblingIndex(ui:Ui(path).UITransformComponent) end
local function click(path)
    local entity = ui:Ui(path)
    assert(isvalid(entity) and entity.Enable, path .. " is shown")
    entity:SendEvent(ButtonClickEvent(entity))
end
local ok, failure = pcall(function()
    assert(Environment:IsMakerPlay(), "Maker Play required")
    local player = _UserService.LocalPlayer
    if STEP == "OPEN" then
        assert(_FactionWar:IsTown(player.CurrentMapName), "stand in a town (run the #130 SETUP)")
        assert(await(function() return ui:Ui("OpenButton").Enable end), "the entry button is shown in a town")
        if not ui._T.open then click("OpenButton") end
        assert(ui._T.open and ui._T.mode == "view" and ui:Ui("Overlay").Enable, "the entry button opened the view")
        assert(await(function() return ui:Ui(SIDE .. "/Faction").TextGUIRendererComponent.Text ~= "讀取中…" end), "the board answered")
        assert(ui._T.zoom == 1, "the view opens at the full overview")
        local scale = ui:Ui(ui.ViewPath).UITransformComponent.UIScale
        assert(near(scale.x, ui.BaseScale, 1e-6) and near(scale.y, ui.BaseScale, 1e-6), "opening the map drew the viewport at the base scale: " .. tostring(scale))
        log("[VRF][MapFullscreen] OPEN PASS baseScale=" .. f(scale.x) .. "; take the screenshot, then run MASK")
    elseif STEP == "MASK" then
        assert(ui._T.open, "the map is open")
        local overlay = ui:Ui("Overlay")
        local screen = frame("Overlay")
        assert(near(screen.left, 0) and near(screen.bottom, 0) and near(screen.right, _UILogic.ScreenWidth) and near(screen.top, _UILogic.ScreenHeight), "the mask is the whole screen")
        local paint = overlay.SpriteGUIRendererComponent
        local color = paint.Color
        assert(color.a == 1 and color.r > color.g and color.g > color.b and color.r < 0.25, "the mask is an opaque deep brown: " .. tostring(color))
        assert(paint.RaycastTarget == true, "and takes every click")
        local mapOrder = _EntityService:GetEntityByPath("/ui/WorldMapGroup").UIGroupComponent.GroupOrder
        local hudOrder = _EntityService:GetEntityByPath("/ui/FactionWarGroup").UIGroupComponent.GroupOrder
        assert(mapOrder > hudOrder, "the map's group is above the town HUD's (" .. tostring(mapOrder) .. " > " .. tostring(hudOrder) .. ")")
        assert(isvalid(_EntityService:GetEntityByPath("/ui/FactionWarGroup/SiegePanel")), "the siege panel is in that group, under the mask")
        assert(sibling("OpenButton") < sibling("Overlay"), "the entry button is under the mask too")
        local perCanvas = screen.perUnit
        local window = frame("Overlay/Window")
        local margins = { window.left / perCanvas, (screen.right - window.right) / perCanvas, window.bottom / perCanvas, (screen.top - window.top) / perCanvas }
        for index, margin in ipairs(margins) do assert(near(margin, 40, 2), "the window leaves about 40 px: side " .. tostring(index) .. " = " .. f(margin)) end
        assert(sibling("Confirm") > sibling("Overlay") and sibling("Message") > sibling("Confirm"), "the confirmation and the message window are drawn above the mask")
        log("[VRF][MapFullscreen] MASK PASS margins=" .. f(margins[1]) .. "," .. f(margins[2]) .. "," .. f(margins[3]) .. "," .. f(margins[4]) .. " group " .. tostring(mapOrder) .. ">" .. tostring(hudOrder))
    elseif STEP == "CENTRE" then
        assert(ui._T.open, "the map is open")
        ui:SetMapView(1, Vector2(0, 0))
        local perCanvas = frame("Overlay").perUnit
        local window, view, content = frame("Overlay/Window"), frame(ui.ViewPath), contentFrame()
        local ratio = view.perUnit / perCanvas
        assert(near(ratio, ui.BaseScale, 0.01) and ratio > 1.15 and ratio < 1.25, "a unit of the viewport is " .. f(ratio * 100) .. " % of a canvas unit: the base scale of about 1.2")
        local windowHeight, mapHeight = window.top - window.bottom, content.top - content.bottom
        assert(mapHeight / windowHeight >= 0.95 and mapHeight <= windowHeight + 1, "the map is as tall as the window: " .. f(mapHeight) .. " of " .. f(windowHeight) .. " px")
        local wx, wy = middle(window)
        local cx, cy = middle(content)
        assert(near(cx, wx) and near(cy, wy), "and centred in it: (" .. f(cx - wx) .. "," .. f(cy - wy) .. ") px off")
        assert(covers(view, content), "the whole map is inside the viewport at 1x")
        assert(covers(window, view) and (view.right - view.left) / (window.right - window.left) >= 0.95, "the viewport fills the window")
        local terrain = ui:Ui(ui.ViewPath .. "/Content/Terrain").UITransformComponent.RectSize
        assert(terrain.x == 740 and terrain.y == 810, "the artwork is the painted size, scaled and not painted again")
        log("[VRF][MapFullscreen] CENTRE PASS scale=" .. f(ratio * 100) .. "% mapHeight=" .. f(mapHeight) .. " windowHeight=" .. f(windowHeight) .. " off=(" .. f(cx - wx) .. "," .. f(cy - wy) .. ")")
    elseif STEP == "PANEL" then
        assert(ui._T.open, "the map is open")
        ui:SetMapView(1, Vector2(0, 0))
        local perCanvas = frame("Overlay").perUnit
        local window, view, content, side = frame("Overlay/Window"), frame(ui.ViewPath), contentFrame(), frame(SIDE)
        local paint = ui:Ui(SIDE).SpriteGUIRendererComponent
        assert(paint.Color.a > 0.3 and paint.Color.a < 0.95, "the town list is translucent: alpha " .. f(paint.Color.a))
        assert(paint.RaycastTarget == true, "and takes the touches that land on it")
        assert(side.left >= content.right + 8 * perCanvas, "at 1x it does not cover the map: it starts " .. f(side.left - content.right) .. " px after the map")
        assert(covers(window, side) and covers(view, side), "it floats inside the window and the viewport")
        assert(sibling(SIDE) > sibling(ui.ViewPath), "and over the map")
        for _, name in ipairs({ "Title", "Close", "MapHint", "Hint" }) do
            assert(sibling("Overlay/Window/" .. name) > sibling(SIDE), name .. " is drawn above the map and the list")
        end
        local close = frame("Overlay/Window/Close")
        assert(close.right - close.left >= 88 * perCanvas - 1 and close.top - close.bottom >= 88 * perCanvas - 1, "the close button is a full touch target")
        local zoneLeft, zoneBottom = _UILogic.ScreenWidth - 220 * perCanvas, _UILogic.ScreenHeight - 130 * perCanvas
        assert(not (close.right > zoneLeft and close.top > zoneBottom), "and does not sit under the engine's buttons in the top-right corner")
        local ww, wh = middle(window)
        for name, signs in pairs({ Title = { -1, 1 }, Close = { 1, 1 }, MapHint = { -1, -1 }, Hint = { 1, -1 } }) do
            local rect = frame("Overlay/Window/" .. name)
            local x, y = middle(rect)
            assert((x - ww) * signs[1] > 0 and (y - wh) * signs[2] > 0 and covers(window, rect), name .. " is in its own corner of the window")
        end
        log("[VRF][MapFullscreen] PANEL PASS gap=" .. f(side.left - content.right) .. " alpha=" .. f(paint.Color.a * 100) .. "% corners ok")
    elseif STEP == "ZOOM_COVER" then
        assert(ui._T.open, "the map is open")
        ui:SetMapView(3, Vector2(0, 0))
        local view, content, side = frame(ui.ViewPath), contentFrame(), frame(SIDE)
        local covered = overlapArea(content, side)
        assert(covered > 0.5 * (side.right - side.left) * (side.top - side.bottom), "zoomed in, the map goes under the town list: " .. f(covered) .. " px2 of it")
        assert(covers(view, side), "the list stays inside the viewport")
        local sx, sy = middle(side)
        assert(ui:IsOverSidePanel(Vector2(sx, sy)), "a point on the list is the list's")
        assert(not ui:IsOverSidePanel(Vector2(view.left + 60, sy)), "a point on the map beside it is not")
        assert(ui:Ui(ui.ViewPath .. "/Input").Parent == ui:Ui(ui.ViewPath) and sibling(SIDE) > sibling(ui.ViewPath), "the list is over the viewport that holds the touch surface, so a touch on it never reaches the map")
        local zoom = ui._T.zoom
        log("[VRF][MapFullscreen] ZOOM_COVER PASS zoom=" .. tostring(zoom) .. " covered=" .. f(covered) .. " px2; take the screenshot, then run TOUCH")
    elseif STEP == "TOUCH" then
        assert(ui._T.open, "the map is open")
        ui:SetMapView(3, Vector2(0, 0))
        local view, side = frame(ui.ViewPath), frame(SIDE)
        local before = contentFrame()
        local input = ui:Ui(ui.ViewPath .. "/Input")
        local py = (view.bottom + view.top) / 2
        local p = Vector2(view.left + 200, py)
        assert(p.x < side.left, "the press starts beside the list")
        local q = Vector2(p.x + 80, p.y - 45)
        input:SendEvent(UITouchDownEvent(input, -1, p))
        input:SendEvent(UITouchDragEvent(input, Vector2(0, 0), -1, q))
        input:SendEvent(UITouchUpEvent(input, -1, q))
        local after = contentFrame()
        assert(ui._T.dragId == nil, "the pointer was released")
        assert(near(after.left - before.left, 80, 0.5) and near(after.bottom - before.bottom, -45, 0.5), "the map moved exactly as far as the pointer on the screen: (" .. f(after.left - before.left) .. "," .. f(after.bottom - before.bottom) .. ") px")
        log("[VRF][MapFullscreen] TOUCH PASS moved=(" .. f(after.left - before.left) .. "," .. f(after.bottom - before.bottom) .. ") px for a drag of (80,-45)")
    elseif STEP == "CREST_CLICK" then
        -- The click on a crest under the base scale, with a synthetic READY answer (no request is sent, the profile is untouched): Zuoying is the departure town, Gushan is listed.
        assert(player.CurrentMapName == "zuoying", "stand in Zuoying")
        if ui._T.open then ui:Close() end
        local doc = _FactionWarTownDocument
        local towns = {}
        for _, id in ipairs(doc.TownOrder) do
            table.insert(towns, { id = id, name = doc.TownNames[id], owner = (id == "nanzih" or id == "zuoying") and "A" or "B", strength = id == "gushan" and 55 or 100, capital = doc:IsCapital(id) })
        end
        local links = { { a = "nanzih", b = "zuoying" }, { a = "zuoying", b = "gushan" }, { a = "gushan", b = "yancheng" } }
        local gushan = { town = "gushan", name = "鼓山", capital = false, strength = 55, owner = "B" }
        ui:BeginSelect()
        ui:ShowSelect("zuoying", "READY", { town = "zuoying", name = "左營", capital = false, strength = 100, owner = "A", faction = "A" }, { gushan }, { towns = towns, links = links })
        assert(ui._T.open and ui._T.mode == "select" and ui._T.zoom == ui.SelectZoom, "the selection opened at " .. tostring(ui.SelectZoom) .. "x")
        local view = frame(ui.ViewPath)
        local perUnit = ui:ScreenPixelsPerUnit()
        assert(near(perUnit, view.perUnit, 0.01), "ScreenPixelsPerUnit " .. f(perUnit) .. " is the measured " .. f(view.perUnit) .. " screen pixels to a viewport unit")
        local origin = crestOnScreen("zuoying")
        assert(origin.x > view.left and origin.x < view.right and origin.y > view.bottom and origin.y < view.top, "the departure town is inside the viewport: (" .. f(origin.x) .. "," .. f(origin.y) .. ")")
        ui:SetMapView(4, ui:CenterOffset(ui:Ui(ui.ViewPath .. "/Content/Towns/gushan").UITransformComponent.anchoredPosition, 4))
        local at = crestOnScreen("gushan")
        local side = frame(SIDE)
        assert(at.x > view.left and at.x < side.left and at.y > view.bottom and at.y < view.top, "the Gushan crest is on the map beside the list: (" .. f(at.x) .. "," .. f(at.y) .. ")")
        local radiusPx = ui:HitRadius(ui._T.zoom, perUnit) * perUnit
        assert(radiusPx >= ui.MinHitPx - 1e-6, "the reach is " .. f(radiusPx) .. " screen pixels")
        tap(Vector2(at.x - 20, at.y))
        assert(ui._T.selected == "gushan" and ui:Ui("Confirm").Enable, "a tap 20 screen pixels from the crest picked it")
        ui:Decline()
        tap(Vector2(at.x - (radiusPx + 30), at.y))
        assert(ui._T.selected == nil, "a tap 30 pixels beyond the reach picked nothing")
        tap(crestOnScreen("zuoying"))
        assert(ui._T.selected == nil, "a tap on a crest that cannot be picked did nothing")
        ui:Close()
        assert(not ui._T.open, "the map is closed again")
        log("[VRF][MapFullscreen] CREST_CLICK PASS reach=" .. f(radiusPx) .. " px perUnit=" .. f(perUnit))
    elseif STEP == "CLOSE" then
        if ui._T.open then ui:Close() end
        assert(not ui._T.open and not ui:Ui("Overlay").Enable, "the map starts closed")
        ui:HandleKey(KeyDownEvent(KeyboardKey.M))
        assert(ui._T.open and ui._T.mode == "view" and ui:Ui("Overlay").Enable, "M opens the map in a town")
        ui:HandleKey(KeyDownEvent(KeyboardKey.M))
        assert(not ui._T.open and not ui:Ui("Overlay").Enable, "and M closes it")
        click("OpenButton")
        assert(ui._T.open and ui:Ui("Overlay").Enable, "the entry button opens it")
        click("Overlay/Window/Close")
        assert(not ui._T.open and not ui:Ui("Overlay").Enable, "and the close button closes it")
        log("[VRF][MapFullscreen] CLOSE PASS M, the entry button and the close button behave as before")
    else
        error("unknown STEP: " .. STEP)
    end
end)
if not ok then log_error("[VRF][MapFullscreen] " .. STEP .. " FAIL " .. tostring(failure)) end
