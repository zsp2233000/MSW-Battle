-- Maker server_main: public pure calculations, with literal expectations from #64.
local ok, detail = pcall(function()
    for _, case in ipairs({
        { 1, 0, 1, 2, 0 },
        { 1, 0, 6, 4, 0 },
        { 3, 2, 5, 5, 0 },
        { 4, 1, 5, 5, 2 },
        { 29, 28, 1, 30, 0 },
        { 29, 0, 100, 30, 0 },
        { 30, 0, 100, 30, 0 },
        { 30, 20, 0, 30, 0 },
        { 1, 0, 0, 1, 0 },
    }) do
        local progress = _MonsterProgression:ApplyExperience(case[1], case[2], case[3])
        assert(progress.level == case[4] and progress.experience == case[5], "experience case " .. table.concat(case, ","))
    end
    assert(_MonsterProgression:ApplyExperience(0, 0, 1) == nil, "invalid level rejected")
    assert(_MonsterProgression:ApplyExperience(1, -1, 1) == nil, "negative experience rejected")
    assert(_MonsterProgression:ApplyExperience(1, 0, -1) == nil, "negative grant rejected")
    local base = { MaxHp = 101, AttackDamageMin = 3, AttackDamageMax = 7, MaxHpGrowthRate = 0.1, AttackDamageGrowthRate = 0.25 }
    local stats = _MonsterProgression:CalculateStats(base, 2)
    assert(stats.MaxHp == 111 and stats.AttackDamageMin == 3 and stats.AttackDamageMax == 8, "independent growth and flooring")
    assert(base.MaxHp == 101 and base.AttackDamageMax == 7, "input is unchanged")
    base.MaxHpGrowthRate = 0; base.AttackDamageGrowthRate = 0
    stats = _MonsterProgression:CalculateStats(base, 30)
    assert(stats.MaxHp == 101 and stats.AttackDamageMin == 3 and stats.AttackDamageMax == 7, "zero growth")
    local map = _EntityService:GetEntityByPath("/maps/template")
    local session = map:GetComponent("script.BattleSession")
    for _, case in ipairs({
        { "monster_tank", 400, 8, 12, 806, 16, 24 },
        { "monster_warrior", 220, 20, 30, 443, 40, 60 },
        { "monster_shooter", 120, 32, 48, 241, 64, 96 },
    }) do
        local profile = session:GetMonsterProfile(case[1])
        assert(profile.MaxHpGrowthRate == 0.035 and profile.AttackDamageGrowthRate == 0.035, "formal growth rates " .. case[1])
        for index, level in ipairs({ 1, 30 }) do
            stats = _MonsterProgression:CalculateStats(profile, level)
            local offset = index == 1 and 1 or 4
            assert(stats.MaxHp == case[offset + 1] and stats.AttackDamageMin == case[offset + 2]
                and stats.AttackDamageMax == case[offset + 3], "formal Lv" .. tostring(level) .. " " .. case[1])
        end
    end
    log("[VRF][MonsterProgression] PASS")
end)
if not ok then log_error("[VRF][MonsterProgression] FAIL " .. tostring(detail)) end
