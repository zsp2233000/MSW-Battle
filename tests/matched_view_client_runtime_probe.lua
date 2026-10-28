-- Run on the client after the matched battle has units. Reads only public presentation and synced state.
local ok, detail = pcall(function()
    local player = _UserService.LocalPlayer
    assert(isvalid(player), "local player required")
    local map = player.CurrentMap
    assert(isvalid(map) and map.Name == "matchprobe", "local player is not on matchprobe")
    local view = map:GetComponent("script.BattleView")
    local session = map:GetComponent("script.BattleSession")
    assert(isvalid(view) and isvalid(session), "formal view missing")
    assert(map:GetComponent("script.BattleViewPrototype") == nil, "prototype component still attached")
    local mine = view:GetLocalFaction()
    assert(mine == "PLAYER" or mine == "ENEMY", "local profile is not a participant")
    local sign = mine == "PLAYER" and 1 or -1
    local units = map:GetChildComponentsByTypeName("script.BattleUnit", false)
    assert(#units >= 2, "battle units missing")
    local ownCount, enemyCount, fullCount = 0, 0, 0
    for _, unit in ipairs(units) do
        local source = unit.Entity
        local visual = view:GetVisual(source)
        assert(isvalid(visual), "missing visual " .. source.Name)
        local sourcePosition = source.TransformComponent.WorldPosition
        local visualPosition = visual.TransformComponent.WorldPosition
        local expectedX = sign == 1 and sourcePosition.x or 1 - sourcePosition.x
        local difference = math.max(math.abs(visualPosition.x - expectedX), math.abs(visualPosition.y - sourcePosition.y))
        assert(difference < 0.35, "position diverged " .. source.Name)
        assert(not isvalid(visual.KinematicbodyComponent) and not isvalid(visual.TriggerComponent), "visual has combat components")
        assert(source.SpriteRendererComponent.Color.a == 0, "original sprite still visible")
        local bar = _EntityService:GetEntityByPath("/ui/BattleGroup/HealthBars/HP_" .. source.Name)
        assert(isvalid(bar), "screen hp bar missing " .. source.Name)
        local fill = bar:GetChildByName("Img_Value")
        assert(isvalid(fill), "screen hp fill missing " .. source.Name)
        local fillRenderer = fill.SpriteGUIRendererComponent
        local fillTransform = fill.UITransformComponent
        assert(isvalid(fillRenderer) and isvalid(fillTransform), "screen hp fill components missing " .. source.Name)
        local color = fillRenderer.Color
        local own = unit.Faction == mine
        if own then
            ownCount = ownCount + 1
            assert(color.g > color.r, "own bar is not green")
        else
            enemyCount = enemyCount + 1
            assert(color.r > color.g, "enemy bar is not red")
        end
        local ratio = unit.MaxHp > 0 and math.max(0, math.min(1, unit.Hp / unit.MaxHp)) or 0
        local progress = bar:GetComponent("script.UIResizableProgressBar")
        assert(isvalid(progress), "screen hp progress missing " .. source.Name)
        assert(fill.Enable == (ratio > 0), "hp fill visibility mismatch " .. source.Name)
        local expectedWidth = progress.OriginalWidth * ratio
        assert(math.abs(fillTransform.RectSize.x - expectedWidth) < 0.5, "hp fill width mismatch " .. source.Name)
        if unit.Hp >= unit.MaxHp and unit.Hp > 0 then
            fullCount = fullCount + 1
            assert(bar.Enable and fill.Enable, "full hp bar hidden")
        end
    end
    assert(ownCount > 0 and enemyCount > 0, "both sides must be visible")
    local home = map:GetChildByName("ViewAvatar_1")
    local away = map:GetChildByName("ViewAvatar_2")
    assert(isvalid(home) and isvalid(away), "spectator avatars missing")
    local ownAvatar = mine == "PLAYER" and home or away
    local otherAvatar = mine == "PLAYER" and away or home
    local ownPosition = ownAvatar.TransformComponent.WorldPosition
    local otherPosition = otherAvatar.TransformComponent.WorldPosition
    assert(ownPosition.x < -1 and otherPosition.x > 1, "own spectator is not on the left")
    assert(math.abs(ownPosition.x + otherPosition.x - 1) < 0.05, "spectators are not symmetric about x=0.5")
    assert(math.abs(ownPosition.y - 4.2) < 0.05 and math.abs(otherPosition.y - 4.2) < 0.05, "spectators left the visible row")
    for _, position in ipairs({ownPosition, otherPosition}) do
        for _, y in ipairs({position.y, position.y + 1.5}) do
            local screen = _UILogic:WorldToScreenPosition(Vector2(position.x, y))
            assert(screen.x > 0 and screen.x < _UILogic.ScreenWidth and screen.y > 0 and screen.y < _UILogic.ScreenHeight, "spectator or name tag is outside the view")
        end
    end
    assert(ownAvatar.TransformComponent.Scale.x < 0 and otherAvatar.TransformComponent.Scale.x > 0, "spectator facing is not inward")
    local body = ownAvatar.KinematicbodyComponent
    assert((not isvalid(body) or body.Enable == false) and not isvalid(ownAvatar.TriggerComponent) and not isvalid(ownAvatar:GetComponent("script.BattleUnit")), "spectator can fight")
    assert(player.Visible == false, "authoritative player body is still visible")
    local camera = _CameraService:GetCurrentCameraComponent()
    local anchor = map:GetChildByName("BattleCameraAnchor", false)
    assert(isvalid(camera) and isvalid(anchor) and isvalid(anchor.CameraComponent), "camera missing")
    assert(camera == anchor.CameraComponent, "camera is not the saved battlefield anchor")
    assert(camera.ZoomRatio == anchor.CameraComponent.ZoomRatio, "camera zoom changed")
    assert(camera.CameraOffset.x == anchor.CameraComponent.CameraOffset.x and camera.CameraOffset.y == anchor.CameraComponent.CameraOffset.y, "camera offset changed")
    assert(_CameraService.TransitionBlendTime == 0, "camera slides on entry")
    log("[VRF][BattleView] OPENING_PASS localFaction=" .. mine .. " units=" .. tostring(#units) .. " own=" .. tostring(ownCount) .. " enemy=" .. tostring(enemyCount) .. " full=" .. tostring(fullCount) .. " sign=" .. tostring(sign))
end)
if not ok then log("[VRF][BattleView] OPENING_FAIL " .. tostring(detail)) end
