-- SETUP: server_main with one real player and a virtual hf6702; BATTLE: matched server; CLIENT: client; RETURN: matched server.
-- BATTLE uses the existing manual clock only after native admission and automatic battle initialization.
local MODE = 'SETUP'
local LEVEL_KEY, FORMATION_KEY = 'I67FullLevels20261112', 'I67FullForms20261112'
local function await(predicate, tries)
    for _ = 1, tries or 400 do if predicate() then return true end wait(0.1) end
    return false
end
local expected = {
    normal = {monster_tank={level=5,hp=456,min=9,max=13}, monster_warrior={level=8,hp=273,min=24,max=37}},
    peer = {monster_tank={level=12,hp=554,min=11,max=16}, monster_warrior={level=3,hp=235,min=21,max=32}},
}
local ok, detail = pcall(function()
    if MODE == 'SETUP' then
        local users = _UserService.UserEntities.Values
        assert(#users == 2, 'real player and virtual hf6702 required')
        local originalFormation, originalLevels = _FormationService.StorageKey, _MonsterLevelStorage.StorageKey
        local participants = {}
        for _, user in ipairs(users) do
            local id, profile = user.PlayerComponent.UserId, user.PlayerComponent.ProfileCode
            assert(user.CurrentMapName == 'formationlobby' and not _MatchFlow:IsFormationLocked(id), 'idle lobby required')
            local storage = _DataStorageService:GetUserDataStorage(profile)
            for _, key in ipairs({LEVEL_KEY,FORMATION_KEY}) do
                local code, raw = storage:GetAndWait(key)
                assert(code == 1000002 or (code == 0 and raw == nil), 'unused disposable fixture key required')
            end
            local code, raw = storage:GetAndWait(_FormationHandoff.StorageKey)
            assert(code == 0 or code == 1000002, 'backup original transfer')
            participants[#participants+1] = {id=id,profile=profile,storage=storage,transfer=raw}
        end
        _FormationService.StorageKey, _MonsterLevelStorage.StorageKey = FORMATION_KEY, LEVEL_KEY
        local ran, failure = pcall(function()
            for _, p in ipairs(participants) do
                local session = _FormationService:GetSession(p.id)
                _FormationService:Load(session)
                _FormationService:LoadLevels(session)
                assert(await(function() return session.initialized and session.loadState == 'NEW' and session.levelLoadState == 'READY' end), 'fixtures loaded')
                local units = {{monsterId='monster_tank',x=-3,y=-1}, {monsterId='monster_tank',x=-4,y=0}, {monsterId='monster_warrior',x=-5,y=1}}
                _FormationService:SaveForUser(p.id, units, 1, session.saved.slots['1'].revision, _UtilLogic:NewGuid())
                assert(await(function() return not session.pending end) and #session.saved.slots['1'].units == 3, 'saved fixture')
                _FormationService:ActivateForUser(p.id, 1, session.saved.slots['1'].revision)
                assert(await(function() return not session.pending end) and session.saved.activeSlot == 1, 'active fixture')
                local monsters = {}
                for id, stats in pairs(p.profile == 'hf6702' and expected.peer or expected.normal) do monsters[id] = {level=stats.level,experience=0} end
                assert(p.storage:SetAndWait(LEVEL_KEY, _MonsterLevelStorage:Encode({schema=1,monsters=monsters,settled={}})) == 0, 'seed fresh levels after cached lobby read')
            end
            for _, p in ipairs(participants) do
                _MatchFlow:QueueForUser(p.id)
                assert(p.storage:SetAndWait(LEVEL_KEY, _MonsterLevelStorage:Encode({schema=1,monsters={monster_tank={level=30,experience=0},monster_warrior={level=30,experience=0}},settled={}})) == 0, 'progress changes after queue')
            end
            assert(await(function() return #_UserService.UserEntities.Values == 0 end), 'both moved into native instance')
            log('[VRF][LevelMatch67] INSTANCE_READY run BATTLE, CLIENT, RETURN')
            assert(await(function()
                for _, p in ipairs(participants) do
                    local user = _UserService:GetUserEntityByUserId(p.id)
                    if not isvalid(user) or user.CurrentMapName ~= 'formationlobby' then return false end
                end
                return true
            end, 2400), 'both returned after battle and client checks')
            for _, p in ipairs(participants) do
                if _MatchFlow:IsFormationLocked(p.id) then _MatchFlow:ReturnForUser(p.id) end
                assert(await(function() return not _MatchFlow:IsFormationLocked(p.id) end), 'return releases lock')
            end
        end)
        _FormationService.StorageKey, _MonsterLevelStorage.StorageKey = originalFormation, originalLevels
        for _, p in ipairs(participants) do
            assert(p.storage:DeleteAndWait(LEVEL_KEY) == 0 and p.storage:DeleteAndWait(FORMATION_KEY) == 0, 'delete disposable fixtures')
            if p.transfer == nil then
                assert(p.storage:DeleteAndWait(_FormationHandoff.StorageKey) == 0, 'restore absent transfer')
            else
                assert(p.storage:SetAndWait(_FormationHandoff.StorageKey, p.transfer) == 0, 'restore original transfer bytes')
            end
            local session = _FormationService:GetSession(p.id)
            if session ~= nil then _FormationService:Load(session) _FormationService:LoadLevels(session) end
        end
        assert(ran, failure)
        log('[VRF][LevelMatch67] FLOW_PASS real queue; cross-room snapshot; later storage changes ignored; CLEANUP_PASS')
        return
    end
    local map = MODE == 'CLIENT' and _UserService.LocalPlayer.CurrentMap or _EntityService:GetEntityByPath('/maps/matchprobe')
    local battle = map:GetComponent('script.BattleSession')
    assert(await(function() return battle.Phase == 'BATTLE' end), 'automatic battle started')
    if MODE == 'RETURN' then
        battle:EndManualSimulation()
        local ids = {}
        for _, user in ipairs(_UserService.UserEntities.Values) do table.insert(ids, user.PlayerComponent.UserId) end
        _RoomService:MoveUsersToStaticRoom(ids, 'formationlobby')
        log('[VRF][LevelMatch67] RETURN_DISPATCHED')
        return
    end
    if MODE == 'BATTLE' then
        _MonsterLevelStorage.StorageKey = LEVEL_KEY
        assert(battle:BeginManualSimulation(), 'hold initialized battle for presentation checks')
    end
    local units = map:GetChildComponentsByTypeName('script.BattleUnit', false)
    assert(#units == 6, 'three units per side')
    local home, away = 0, 0
    local view = MODE == 'CLIENT' and map:GetComponent('script.BattleView') or nil
    for _, unit in ipairs(units) do
        local profile = unit.Faction == 'PLAYER' and battle.HomeProfile or battle.AwayProfile
        local stats = (profile == 'hf6702' and expected.peer or expected.normal)[unit.MonsterId]
        assert(stats and unit.Level == stats.level and unit.MaxHp == stats.hp
            and (MODE == 'CLIENT' or (unit.AttackDamageMin == stats.min and unit.AttackDamageMax == stats.max)), 'literal expected level and combat stats: '..unit.Entity.Name)
        if unit.Faction == 'PLAYER' then home=home+1 else away=away+1 end
        if view ~= nil then
            assert(await(function() return isvalid(view:GetVisual(unit.Entity)) end), 'visible battle proxy ready')
            local visual = view:GetVisual(unit.Entity)
            local label = visual:GetChildByName('NameTag')
            assert(isvalid(label) and label.NameTagComponent.Name == 'Lv.'..tostring(stats.level)..' '..unit.MonsterName, 'visible name tag uses frozen level')
        end
    end
    assert(home == 3 and away == 3, 'both battle sides verified')
    log('[VRF][LevelMatch67] '..MODE..'_PASS units=6 both sides; frozen levels; HP'..(MODE == 'CLIENT' and '; visible name tags' or '; damage'))
end)
if not ok then log('[VRF][LevelMatch67] '..MODE..'_FAIL '..tostring(detail)) end
