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
        local anchor = visual:GetChildByName("HPAnchor")
        assert(isvalid(anchor) and anchor.Parent == visual, "world hp anchor missing " .. source.Name)
        local bar = anchor:GetChildByName("HealthBar")
        assert(isvalid(bar) and bar.Parent == anchor, "world hp bar missing " .. source.Name)
        local pixel = bar.PixelRendererComponent
        assert(isvalid(pixel) and pixel.Width == 60 and pixel.Height == 10, "world hp pixels missing " .. source.Name)
        assert(not isvalid(bar.UITransformComponent), "world hp has UI transform")
        local original = source:GetChildByName("HPAnchor")
        assert(isvalid(original) and not original.Visible, "source hp still visible " .. source.Name)
        local authored = original:GetChildByName("HealthBar")
        assert(isvalid(authored), "authored hp bar missing")
        local expectedScale = authored.TransformComponent.Scale
        local actualScale = bar.TransformComponent.Scale
        assert(actualScale.x == expectedScale.x and actualScale.y == expectedScale.y, "model size lost " .. source.Name)
        local displayScale = visual.TransformComponent.Scale
        local anchorScale = anchor.TransformComponent.Scale
        assert(math.abs(displayScale.x * anchorScale.x - 1) < 0.0001 and math.abs(displayScale.y * anchorScale.y - 1) < 0.0001, "actor stretches hp " .. source.Name)
        local preview = bar:GetChildByName("EditorPreview")
        assert(isvalid(preview) and not preview.Visible, "editor preview still visible " .. source.Name)
        local geometry = _BattleUIController:GetHealthBarGeometry(unit.StandAnimationRUID)
        assert(geometry ~= nil, "standing geometry not ready")
        local center = visual.SpriteRendererComponent.FlipX and -geometry.centerX or geometry.centerX
        local top = visual.TransformComponent:ToWorldPoint(Vector3(center, geometry.top, 0))
        local actual = anchor.TransformComponent.WorldPosition
        assert(math.abs(actual.x - top.x) < 0.001 and math.abs(actual.y - top.y - 0.15) < 0.001, "world hp misplaced " .. source.Name)
        local own = unit.Faction == mine
        if own then ownCount = ownCount + 1 else enemyCount = enemyCount + 1 end
        local ratio = unit.MaxHp > 0 and math.max(0, math.min(1, unit.Hp / unit.MaxHp)) or 0
        local filled = 0
        for x = 3, 58 do
            local color = pixel:GetPixel(x, 5)
            if color.r > 0 or color.g > 0 then
                filled = filled + 1
                assert(own and color.g > color.r or not own and color.r > color.g, "hp side color mismatch " .. source.Name)
            end
        end
        assert(filled == math.floor(56 * ratio), "hp ratio mismatch " .. source.Name)
        assert(bar.VisibleInHierarchy == visual.VisibleInHierarchy, "hp visibility mismatch " .. source.Name)
        if unit.Hp >= unit.MaxHp and unit.Hp > 0 then
            fullCount = fullCount + 1
            assert(bar.VisibleInHierarchy, "full hp bar hidden")
        end
    end
    assert(ownCount > 0 and enemyCount > 0, "both sides must be visible")
    assert(not isvalid(_EntityService:GetEntityByPath("/ui/BattleGroup/HealthBars")), "obsolete screen hp UI remains")
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
