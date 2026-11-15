-- Maker server_main: public pure calculations, with literal expectations from #64.
local ok, detail = pcall(function()
    local fresh = _MonsterProgression:DefaultProgress()
    assert(fresh.level == 1 and fresh.experience == 0, "unrecorded monster starts at Lv1 / 0")
    fresh.level = 12; fresh.experience = 3
    local another = _MonsterProgression:DefaultProgress()
    assert(another.level == 1 and another.experience == 0, "defaults are detached values")
    for level = 1, 30 do
        assert(_MonsterProgression:IsValidLevel(level), "valid level " .. tostring(level))
    end
    for _, invalid in ipairs({ 0, 31, 1.5, "5", false, {}, math.huge, -math.huge, 0/0 }) do
        assert(not _MonsterProgression:IsValidLevel(invalid), "raw invalid level rejected")
    end
    assert(not _MonsterProgression:IsValidLevel(nil), "missing level rejected")
    for _, case in ipairs({
        { 1, 0, true }, { 5, 3, true }, { 29, 28, true }, { 30, 0, true },
        { 1, 1, false }, { 5, 5, false }, { 30, 1, false }, { 0, 0, false },
        { 31, 0, false }, { 1.5, 0, false }, { "5", 0, false }, { false, 0, false },
        { 5, -1, false }, { 5, 1.5, false }, { 5, "3", false }, { 5, false, false },
        { 5, math.huge, false }, { 5, 0/0, false },
    }) do
        assert(_MonsterProgression:IsValidProgress(case[1], case[2]) == case[3], "stored progress validation")
    end
    assert(not _MonsterProgression:IsValidProgress(nil, 0)
        and not _MonsterProgression:IsValidProgress(1, nil), "incomplete progress rejected")
    for _, case in ipairs({
        { '{"level":1,"experience":0}', true }, { '{"level":5,"experience":3}', true },
        { '{"level":29,"experience":28}', true }, { '{"level":30,"experience":0}', true },
        { '{"level":0,"experience":0}', false }, { '{"level":31,"experience":0}', false },
        { '{"level":1.5,"experience":0}', false }, { '{"level":"5","experience":0}', false },
        { '{"level":5,"experience":5}', false }, { '{"level":30,"experience":1}', false },
        { '{"level":5,"experience":-1}', false }, { '{"level":5,"experience":1.5}', false },
        { '{"level":5,"experience":"3"}', false }, { '{"level":5}', false },
        { '{"experience":0}', false }, { '{"level":1,"experience":0,"extra":1}', false },
    }) do
        local raw = '{"schema":1,"monsters":{"monster_tank":' .. case[1] .. '},"settled":[]}'
        local document = _MonsterLevelStorage:Decode(raw)
        assert((document ~= nil) == case[2], "storage preserves strict validation: " .. case[1])
        if document ~= nil then
            local roundTrip = _MonsterLevelStorage:Decode(_MonsterLevelStorage:Encode(document))
            assert(roundTrip.monsters.monster_tank.level == document.monsters.monster_tank.level
                and roundTrip.monsters.monster_tank.experience == document.monsters.monster_tank.experience,
                "existing save values survive encoding")
        end
    end
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
    -- Literal #70 expectations: one experience point per current level, nothing at MAX.
    assert(_MonsterProgression:RequiredExperience(1) == 1, "Lv1 needs 1")
    assert(_MonsterProgression:RequiredExperience(29) == 29, "Lv29 needs 29")
    assert(_MonsterProgression:RequiredExperience(30) == 0, "Lv30 is MAX and needs 0")
    assert(_MonsterProgression:RequiredExperience(0) == nil and _MonsterProgression:RequiredExperience(31) == nil,
        "levels outside 1-30 are rejected")
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
    log("[VRF][MonsterProgression] PASS defaults; raw validation; strict save round-trip; experience; stats")
end)
if not ok then log_error("[VRF][MonsterProgression] FAIL " .. tostring(detail)) end
