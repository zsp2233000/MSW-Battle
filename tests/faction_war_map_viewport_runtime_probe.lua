-- Maker client, in a town with the map open. No board or player data is written.
-- Verify uploaded sprites, anchored wheel math, all 34 neutral labels and the drag event path.
local ui = _FactionWarMapUI
local function near(a, b) return math.abs(a - b) < 0.5 end
local function visibleLabels()
    local count = 0
    for _, label in ipairs(ui._T.places) do if label.Enable then count = count + 1 end end
    return count
end
local ok, reason = pcall(function()
    assert(ui._T.open, "open the map in a town before running the probe")
    local view = ui:Ui(ui.ViewPath)
    local content = ui:Ui(ui.ViewPath .. "/Content").UITransformComponent
    local input = ui:Ui(ui.ViewPath .. "/Input")
    local side = ui:Ui("Overlay/Window/Side").UITransformComponent
    local sideStart = side.anchoredPosition
    assert(isvalid(view.MaskComponent) and isvalid(input.UITouchReceiveComponent), "viewport clip and inputs loaded")
    for _, name in ipairs({ "Terrain", "Districts/nanzih", "Districts/zuoying", "Districts/gushan", "Districts/yancheng" }) do
        local entity = ui:Ui(ui.ViewPath .. "/Content/" .. name)
        local sprite = _ResourceService:LoadSpriteAndWait(entity.SpriteGUIRendererComponent.ImageRUID.DataId)
        assert(sprite ~= nil and sprite.IsLoadComplete, name .. " sprite loaded")
        if name == "Terrain" then
            assert(sprite.Width == 1480 and sprite.Height == 1620, "full terrain is installed")
        else
            local dimensions = entity.UITransformComponent.RectSize
            assert(sprite.Width == dimensions.x * 2 and sprite.Height == dimensions.y * 2, name .. " mask aligned")
        end
    end
    ui:SetMapView(1, Vector2(1e6, 1e6))
    assert(near(content.anchoredPosition.x, 0) and near(content.anchoredPosition.y, 0), "overview doesn't allow blank edges")
    local overview = visibleLabels()
    assert(overview > 0 and overview < 34, "overview declutters the label layer")
    local cursor = Vector2(-165, -120)
    ui:ZoomMapAt(cursor, 0.2)
    local zoom = content.UIScale.x
    local offset = content.anchoredPosition
    assert(zoom > 1.15 and zoom < 1.25, "a small wheel event should zoom by a noticeable step")
    assert(near((cursor.x - offset.x) / zoom, cursor.x)
        and near((cursor.y - offset.y) / zoom, cursor.y), "zoom fixes the point under the cursor")
    ui:ZoomMapAt(Vector2(view.UITransformComponent.RectSize.x, 0), 3)
    assert(content.UIScale.x == zoom, "wheel outside the viewport is ignored")
    for _ = 1, 20 do ui:ZoomMapAt(cursor, 3) end
    assert(near(content.UIScale.x, ui.MaxZoom) and visibleLabels() == 34, "zoom caps at max with all 34 labels")
    ui:SetMapView(ui.MaxZoom, Vector2(0, 0))
    assert(ui:Ui(ui.ViewPath .. "/Content/Towns/zuoying/Name").Visible, "town labels are shown in detail view")

    local h = _UILogic.ScreenHeight
    local w = _UILogic.ScreenWidth
    local p = Vector2(w / 2, h / 2)
    local q = Vector2(p.x + 80, p.y - 45)
    local a = _UILogic:ScreenToLocalUIPosition(p, view.UITransformComponent)
    local b = _UILogic:ScreenToLocalUIPosition(q, view.UITransformComponent)
    input:SendEvent(UITouchDownEvent(input, -1, p))
    input:SendEvent(UITouchDragEvent(input, Vector2(0, 0), -1, q))
    input:SendEvent(UITouchUpEvent(input, -1, q))
    assert(ui._T.dragId == nil, "pointer released")
    assert(near(content.anchoredPosition.x, b.x - a.x) and near(content.anchoredPosition.y, b.y - a.y), "drag moves the canvas at screen speed")
    assert(near(side.anchoredPosition.x, sideStart.x) and near(side.anchoredPosition.y, sideStart.y), "war board is stationary")
    ui:SetMapView(2, Vector2(1e6, -1e6))
    local size = view.UITransformComponent.RectSize
    assert(near(content.anchoredPosition.x, size.x / 2) and near(content.anchoredPosition.y, -size.y / 2), "drag/pan clamps to the artwork")
    for _ = 1, 20 do ui:ZoomMapAt(cursor, -3) end
    assert(near(content.UIScale.x, 1) and near(content.anchoredPosition.x, 0)
        and near(content.anchoredPosition.y, 0), "zooming out restores overview")
    log("[VRF][ViewportProbe] PASS assets=5 overview=" .. tostring(overview) .. " close=34 zoom=ok drag=ok bounds=ok")
end)
if not ok then log_error("[VRF][ViewportProbe] FAIL " .. tostring(reason)) end
