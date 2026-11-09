-- Client: run after the server fixture publishes a result on the current battle map.
local ok, detail = pcall(function()
    local player = _UserService.LocalPlayer
    local map = player.CurrentMap
    local session = map:GetComponent("script.BattleSession")
    local ui = _BattleUIController
    local expected = session.RequireMatchedFormations and session:ResultForProfile(player.PlayerComponent.ProfileCode) or session.Result
    for attempt = 1, 100 do
        if ui.OwnResult == expected and ui.result.Enable then break end
        wait(0.1)
    end
    assert(ui.OwnResult == expected and ui.result.Enable, "formal result is visible")
    local own = session.RequireMatchedFormations and session.AwayProfile == player.PlayerComponent.ProfileCode and "ENEMY" or "PLAYER"
    local winner = expected == "WIN" and own or (own == "PLAYER" and "ENEMY" or "PLAYER")
    local units = {}
    if expected ~= "DRAW" then
        for _, unit in ipairs(map:GetChildComponentsByTypeName("script.BattleUnit", false)) do
            if unit.Faction == winner and not unit.IsDead and unit.Hp > 0 then table.insert(units, unit) end
        end
    end
    table.sort(units, function(a, b) return a.DeploymentOrder < b.DeploymentOrder end)
    local count = 0
    for _, entity in ipairs(ui.result.Children:ToTable()) do
        if string.sub(entity.Name, 1, 9) == "Survivor_" then count = count + 1 end
    end
    assert(count == #units, "one visible card per surviving instance")
    for index, unit in ipairs(units) do
        local card = ui.result:GetChildByName("Survivor_" .. tostring(index), false)
        assert(isvalid(card) and card.EnabledInHierarchy, "survivor card is visible")
        assert(card:GetChildByName("MonsterName", true).TextGUIRendererComponent.Text == unit.MonsterName, "name follows deployment order")
        assert(card:GetChildByName("Identity", true).TextGUIRendererComponent.Text == tostring(unit.Hp) .. " / " .. tostring(unit.MaxHp), "each instance retains its HP")
        assert(card:GetChildByName("Portrait", true).SpriteGUIRendererComponent.ImageRUID.DataId == "thumbnail://" .. unit.StandAnimationRUID, "portrait belongs to the survivor")
        local pos = card.UITransformComponent.anchoredPosition
        assert((expected == "WIN" and pos.x < -330) or (expected == "LOSE" and pos.x > 330), "viewer-relative winning side")
        if index == 4 then
            local first = ui.result:GetChildByName("Survivor_1", false).UITransformComponent.anchoredPosition
            assert(pos.x == first.x and pos.y < first.y, "fourth card starts the second row")
        end
    end
    log("[VRF][ResultCardsProbe] PASS result=" .. expected .. " count=" .. tostring(count) .. " own=" .. own)
end)
if not ok then log_error("[VRF][ResultCardsProbe] FAIL " .. tostring(detail)) end
