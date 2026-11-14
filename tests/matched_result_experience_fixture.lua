-- SETUP in server_main with one real player and virtual hf6802. ARM/RETURN in each matched server.
-- Three native matches: confirmed timeout retry, failed writes, then max-level zero gain.
-- Keep SETUP running until CLEANUP_PASS before stopping Play; BACKUP logs retain handoff bytes.
local MODE = "SETUP"
local FORMATION_KEY, LEVEL_KEY = "I68ResultForms20261112A", "I68ResultLevels20261112A"
local function await(predicate, tries)
    for _ = 1, tries or 400 do if predicate() then return true end wait(0.1) end
    return false
end
local ok, detail = pcall(function()
    if MODE ~= "SETUP" then
        local battle = _EntityService:GetEntityByPath("/maps/matchprobe"):GetComponent("script.BattleSession")
        if MODE == "ARM" or MODE == "FAIL" or MODE == "MAX" then
            assert(battle.Phase == "BATTLE", "arm before natural result")
            _MonsterLevelStorage.StorageKey = LEVEL_KEY
            _MonsterLevelStorage.TimeoutSeconds = MODE == "ARM" and 1 or 5
            _FormationStorage:ConfigureMakerFaults(0, MODE == "FAIL" and 20 or 0, 4)
            log("[VRF][ResultExperienceFixture] ARMED " .. MODE)
            return
        end
        assert(await(function() return battle.Phase == "RESULT" end, 1200), "natural elimination")
        assert(await(function()
            for _, receipt in pairs(battle:GetExperienceResults()) do if receipt.status == "PENDING" then return false end end
            return true
        end), "settlements complete")
        local results = battle:GetExperienceResults()
        for profile, receipt in pairs(results) do
            assert(receipt.status == (MODE == "RETURN_FAIL" and "FAILED" or "SAVED"), "expected final settlement status")
            if receipt.status == "SAVED" and profile ~= "hf6802" then
                local tank = receipt.monsters.monster_tank
                assert(tank, "at least one own tank died naturally")
                if tank.before.level == 30 then
                    assert(tank.after.level == 30 and tank.after.experience == 0, "MAX retains no experience")
                else
                    assert(tank.gained == 2 and tank.before.level == 1 and tank.after.level == 2, "two own tank deaths merge to Lv2")
                    local stats = _MonsterProgression:CalculateStats(battle:GetMonsterProfile("monster_tank"), tank.after.level)
                    assert(stats.MaxHp == 413 and stats.AttackDamageMin == 8 and stats.AttackDamageMax == 12, "literal upgraded tank stats")
                end
                log("[VRF][ResultExperienceFixture] CONFIRMED_RETRY_PASS")
            end
        end
        _FormationStorage:ConfigureMakerFaults(0, 0, 0)
        for _, user in ipairs(_UserService.UserEntities.Values) do _MatchFlow:ReturnForUser(user.PlayerComponent.UserId) end
        log("[VRF][ResultExperienceFixture] RETURN_DISPATCHED")
        return
    end
    local users = _UserService.UserEntities.Values
    assert(#users == 2, "one real player and virtual hf6802 required")
    local formationKey, levelKey = _FormationService.StorageKey, _MonsterLevelStorage.StorageKey
    local participants = {}
    for _, user in ipairs(users) do
        local storage = _DataStorageService:GetUserDataStorage(user.PlayerComponent.ProfileCode)
        for _, key in ipairs({FORMATION_KEY, LEVEL_KEY}) do
            local code, raw = storage:GetAndWait(key)
            assert(code == 1000002 or (code == 0 and raw == nil), "unused isolated keys required")
        end
        local code, transfer = storage:GetAndWait(_FormationHandoff.StorageKey)
        assert(code == 0 or code == 1000002, "backup transfer")
        log("[VRF][ResultExperienceFixture] BACKUP " .. _HttpService:JSONEncode({profile=user.PlayerComponent.ProfileCode,transfer=transfer or false}))
        table.insert(participants, {id=user.PlayerComponent.UserId,profile=user.PlayerComponent.ProfileCode,storage=storage,transfer=transfer})
    end
    _FormationService.StorageKey = FORMATION_KEY
    local ran, failure = pcall(function()
        for _, p in ipairs(participants) do
            local session = _FormationService:GetSession(p.id)
            _FormationService:Load(session)
            assert(await(function() return session.initialized and not session.pending and session.loadState == "NEW" end), "isolated formation loaded")
            local units = {}
            if p.profile == "hf6802" then
                for i=1,6 do units[i]={monsterId="monster_tank",x=-1-(i-1)*0.75,y=0} end
            else
                units={{monsterId="monster_tank",x=-1,y=-1},{monsterId="monster_tank",x=-2,y=0},
                    {monsterId="monster_warrior",x=-3,y=1},{monsterId="monster_shooter",x=-4,y=0}}
            end
            _FormationService:SaveForUser(p.id, units, 1, session.saved.slots["1"].revision, _UtilLogic:NewGuid())
            assert(await(function() return not session.pending end) and #session.saved.slots["1"].units == #units, "fixture saved")
            _FormationService:ActivateForUser(p.id, 1, session.saved.slots["1"].revision)
            assert(await(function() return not session.pending end), "fixture active")
        end
        for round=1,3 do
            if round == 3 then
                for _, p in ipairs(participants) do
                    if p.profile ~= "hf6802" then
                        local session = _FormationService:GetSession(p.id)
                        local units = {{monsterId="monster_tank",x=-1,y=0},
                            {monsterId="monster_tank",x=-2,y=0},{monsterId="monster_tank",x=-3,y=0}}
                        _FormationService:SaveForUser(p.id, units, 1, session.saved.slots["1"].revision, _UtilLogic:NewGuid())
                        assert(await(function() return not session.pending end) and #session.saved.slots["1"].units == 3, "MAX roster saved")
                    end
                end
            end
            for _, p in ipairs(participants) do
                -- #70: the real player's shooter is seeded at Lv5 with 2 experience to prove stored progress is shown.
                local monsters = p.profile == "hf6802" and {monster_tank={level=30,experience=0}} or {monster_shooter={level=5,experience=2}}
                if round == 3 then
                    for _, id in ipairs({"monster_tank", "monster_warrior", "monster_shooter"}) do monsters[id]={level=30,experience=0} end
                end
                assert(p.storage:SetAndWait(LEVEL_KEY, _MonsterLevelStorage:Encode({schema=1,monsters=monsters,settled={}})) == 0, "seed isolated levels")
            end
            _MonsterLevelStorage.StorageKey = LEVEL_KEY
            for _, p in ipairs(participants) do _MatchFlow:QueueForUser(p.id) end
            assert(await(function() return #_UserService.UserEntities.Values == 0 end), "native match admission")
            log("[VRF][ResultExperienceFixture] INSTANCE_READY " .. (round == 1 and "ARM" or (round == 2 and "FAIL" or "MAX")))
            assert(await(function()
                for _, p in ipairs(participants) do
                    local user = _UserService:GetUserEntityByUserId(p.id)
                    if not isvalid(user) or user.CurrentMapName ~= "formationlobby" or _MatchFlow:IsFormationLocked(p.id) then return false end
                end
                return true
            end, 3000), "participants returned unlocked")
        end
    end)
    _FormationService.StorageKey = formationKey
    _MonsterLevelStorage.StorageKey = levelKey
    for _, p in ipairs(participants) do
        assert(p.storage:DeleteAndWait(FORMATION_KEY) == 0 and p.storage:DeleteAndWait(LEVEL_KEY) == 0, "remove isolated keys")
        if p.transfer == nil then assert(p.storage:DeleteAndWait(_FormationHandoff.StorageKey) == 0, "remove fixture transfer")
        else assert(p.storage:SetAndWait(_FormationHandoff.StorageKey, p.transfer) == 0, "restore original transfer") end
        local session = _FormationService:GetSession(p.id)
        _FormationService:Load(session)
        _FormationService:LoadLevels(session)
    end
    assert(ran, failure)
    log("[VRF][ResultExperienceFixture] PASS timeout retry; failed save; max level; CLEANUP_PASS")
end)
if not ok then log_error("[VRF][ResultExperienceFixture] FAIL " .. tostring(detail)) end
