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
        assert(isvalid(card) and card.EnabledInHierarchy, "survivor row is visible")
        local label = function(name) return card:GetChildByName(name, true).TextGUIRendererComponent.Text end
        assert(label("MonsterName") == unit.MonsterName, "name follows deployment order")
        assert(label("Level") == "Lv." .. tostring(unit.Level), "survivor monster level")
        assert(label("ProgressText") == "HP " .. tostring(unit.Hp) .. " / " .. tostring(unit.MaxHp), "each instance retains its HP")
        assert(label("StatsText") == "", "survivors carry no stats line")
        local fill = card:GetChildByName("BarFill", true)
        local ratio = unit.Hp / unit.MaxHp
        assert(fill.Enable and math.abs(fill.UITransformComponent.RectSize.x - 480 * ratio) < 0.5, "health bar follows remaining HP")
        local portrait = card:GetChildByName("Portrait", true)
        assert(portrait.EnabledInHierarchy and portrait.SpriteGUIRendererComponent.ImageRUID.DataId == "thumbnail://" .. unit.StandAnimationRUID, "portrait belongs to the survivor")
        assert(not card:GetChildByName("LevelUpEffect").EnabledInHierarchy, "survivors never play LEVEL UP")
        local pos = card.UITransformComponent.anchoredPosition
        assert((expected == "WIN" and pos.x == -640) or (expected == "LOSE" and pos.x == 640), "viewer-relative winning side")
        assert(pos.y == 288 - (index - 1) * 92, "one row per instance, top to bottom")
        assert(math.abs(pos.x) + 290 <= 960 and pos.y - 42 >= -540, "row fits the screen")
        assert(math.abs(pos.x) - 290 >= 330, "row stays clear of the centre window")
    end
    log("[VRF][ResultCardsProbe] PASS result=" .. expected .. " count=" .. tostring(count) .. " own=" .. own)
end)
if not ok then log_error("[VRF][ResultCardsProbe] FAIL " .. tostring(detail)) end
