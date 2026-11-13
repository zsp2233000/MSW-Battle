-- Maker server_main, fresh template deployment; leaves a quiet scene for the client name-tag probe.
local session = nil
local acquired = false
local ok, detail = pcall(function()
    local map = _EntityService:GetEntityByPath("/maps/template")
    session = map:GetComponent("script.BattleSession")
    local function checkBase(unit)
        local base = session:GetMonsterProfile(unit.MonsterId)
        assert(unit.Level == 1 and unit.MaxHp == base.MaxHp and unit.Hp == base.MaxHp
            and unit.AttackDamageMin == base.AttackDamageMin and unit.AttackDamageMax == base.AttackDamageMax,
            "default Lv1 " .. unit.Entity.Name)
    end
    for _, unit in ipairs(map:GetChildComponentsByTypeName("script.BattleUnit", false)) do checkBase(unit) end
    assert(session:TryDeployMonster("monster_tank", Vector3(-4, 0, 0)), "official deployment")
    checkBase(map:GetChildByName("M1_Player_1"):GetComponent("script.BattleUnit"))
    for _, away in ipairs({ false, true }) do
        local prepared = session:PrepareMatchedRoster({ { monsterId = "monster_tank", x = -4, y = 0 } }, away)
        assert(prepared ~= nil and prepared[1].profile.Level == 1 and prepared[1].profile.MaxHp == 400, "legacy matched roster defaults to Lv1")
        assert(session:PrepareMatchedRoster({ { monsterId = "monster_tank", x = -4, y = 0, Level = 30 } }, away) == nil,
            "matched input rejects Maker level")
    end
    acquired = session:BeginManualSimulation()
    assert(acquired, "clock acquired")
    local ids = { "monster_tank", "monster_warrior", "monster_shooter" }
    local players, enemies = {}, {}
    for index, id in ipairs(ids) do
        for _, level in ipairs({ 1, 30 }) do
            table.insert(players, { monsterId = id, name = "Level_" .. tostring(level) .. "_" .. id,
                position = Vector3(-4, index - 2, 0), overrides = { Level = level } })
        end
        table.insert(enemies, { monsterId = id, name = "Default_" .. id, position = Vector3(4, index - 2, 0) })
    end
    for _, invalid in ipairs({ 0, 31, 1.5, "30", math.huge, 0/0 }) do
        local generation = session.SessionGeneration
        players[1].overrides.Level = invalid
        assert(not session:PrepareBattleForTest(players, enemies) and session.SessionGeneration == generation,
            "invalid level rejected atomically")
    end
    players[1].overrides.Level = 1
    assert(session:PrepareBattleForTest(players, enemies), "leveled scene prepared")
    for _, unit in ipairs(map:GetChildComponentsByTypeName("script.BattleUnit", false)) do
        local base = session:GetMonsterProfile(unit.MonsterId)
        local stats = _MonsterProgression:CalculateStats(base, unit.Level)
        assert(unit.MaxHp == stats.MaxHp and unit.Hp == stats.MaxHp and unit.AttackDamageMin == stats.AttackDamageMin
            and unit.AttackDamageMax == stats.AttackDamageMax, "spawn matches calculation " .. unit.Entity.Name)
        assert(unit.MoveSpeed == base.MoveSpeed and unit.AttackInterval == base.AttackIntervalSeconds
            and unit.AttackRange == base.AttackRange and unit.AttackRangeY == base.AttackRangeY, "behaviour unchanged")
        if unit.Faction == "ENEMY" then checkBase(unit) end
    end
end)
if acquired and isvalid(session) then session:EndManualSimulation() end
if ok then log("[VRF][MonsterLevelRoster] PASS")
else log_error("[VRF][MonsterLevelRoster] FAIL " .. tostring(detail)) end
