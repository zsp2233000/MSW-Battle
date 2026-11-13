-- SETUP in server_main with one real player and a virtual hf2602; RESULT then ABORT in each matched instance.
-- The main coroutine retains fixture ownership, checks abort bytes, restores original reads, and cleans up.
local MODE = 'SETUP'
local LEVEL_KEY = 'Issue65MatchedLevels20261110'
local FORMATION_KEY = 'Issue65MatchedFormations20261110'
local function await(predicate, tries)
    for _ = 1, tries or 400 do if predicate() then return true end wait(0.1) end
    return false
end
local ok, detail = pcall(function()
    if MODE == 'SETUP' then
        local users = _UserService.UserEntities.Values
        assert(#users == 2, 'real player and virtual peer required')
        local original = _FormationService.StorageKey
        local participants = {}
        for _, user in ipairs(users) do
            local profile = user.PlayerComponent.ProfileCode
            local storage = _DataStorageService:GetUserDataStorage(profile)
            local code, raw = storage:GetAndWait(LEVEL_KEY)
            assert(code == 1000002 or (code == 0 and raw == nil), 'unused isolated level key')
            participants[#participants+1] = {id=user.PlayerComponent.UserId, profile=profile, storage=storage}
        end
        _FormationService.StorageKey = FORMATION_KEY
        local runOk, runDetail = pcall(function()
            for _, p in ipairs(participants) do
                local session = _FormationService:GetSession(p.id)
                _FormationService:Load(session)
                assert(await(function() return session.initialized and not session.pending
                    and (session.loadState == 'READY' or session.loadState == 'NEW') end), 'isolated formations loaded')
                local units = {{monsterId='monster_tank',x=-3,y=-1},
                    {monsterId='monster_warrior',x=-4,y=0}, {monsterId='monster_shooter',x=-5,y=1}}
                local slot = session.editSlot
                _FormationService:SaveForUser(p.id, units, slot, session.saved.slots[tostring(slot)].revision, _UtilLogic:NewGuid())
                assert(await(function() return not session.pending end) and #session.saved.slots[tostring(slot)].units == 3, 'fixture saved')
                _FormationService:ActivateForUser(p.id, slot, session.saved.slots[tostring(slot)].revision)
                assert(await(function() return not session.pending end), 'fixture activated')
            end
            local beforeAbort = {}
            for round = 1, 2 do
                for _, p in ipairs(participants) do _MatchFlow:QueueForUser(p.id) end
                assert(await(function() return #_UserService.UserEntities.Values == 0 end), 'both admitted to instance')
                log('[VRF][LevelMatch65] INSTANCE_READY '..(round == 1 and 'RESULT' or 'ABORT'))
                assert(await(function()
                    for _, p in ipairs(participants) do
                        local user = _UserService:GetUserEntityByUserId(p.id)
                        if not isvalid(user) or user.CurrentMapName ~= 'formationlobby' or _MatchFlow:IsFormationLocked(p.id) then return false end
                    end
                    return true
                end, 1800), 'both participants returned unlocked')
                for _, p in ipairs(participants) do
                    local code, raw = p.storage:GetAndWait(LEVEL_KEY)
                    assert(code == 0 and raw ~= nil, 'first natural result saved for each participant')
                    if round == 1 then beforeAbort[p.profile] = raw
                    else assert(raw == beforeAbort[p.profile], 'aborted match leaves exact progress bytes unchanged: '..p.profile
                        ..' before='..tostring(beforeAbort[p.profile])..' after='..tostring(raw)) end
                end
            end
        end)
        _FormationService.StorageKey = original
        for _, p in ipairs(participants) do
            assert(p.storage:DeleteAndWait(LEVEL_KEY) == 0, 'level fixture cleanup')
            assert(p.storage:DeleteAndWait(FORMATION_KEY) == 0, 'formation fixture cleanup')
            local user = _UserService:GetUserEntityByUserId(p.id)
            if isvalid(user) then
                local session = _FormationService:GetSession(p.id)
                _FormationService:Load(session)
                assert(await(function() return session.initialized and not session.pending
                    and (session.loadState == 'READY' or session.loadState == 'NEW') end), 'original formation read restored')
            end
        end
        assert(runOk, runDetail)
        log('[VRF][LevelMatch65] PASS natural result; departed participant; abort bytes unchanged; CLEANUP_PASS')
    else
        _FormationService.StorageKey = FORMATION_KEY
        _MonsterLevelStorage.StorageKey = LEVEL_KEY
        local map = _EntityService:GetEntityByPath('/maps/matchprobe')
        local battle = map:GetComponent('script.BattleSession')
        assert(await(function() return battle.Phase == 'BATTLE' end), 'natural battle started')
        local ids, peer = {}, nil
        for _, user in ipairs(_UserService.UserEntities.Values) do
            table.insert(ids, user.PlayerComponent.UserId)
            if user.PlayerComponent.ProfileCode == 'hf2602' then peer = user.PlayerComponent.UserId end
        end
        if MODE == 'ABORT' then
            assert(battle.ResultDeaths == '' and next(battle:GetExperienceResults()) == nil, 'no settlement before result')
            _RoomService:MoveUsersToStaticRoom(ids, 'formationlobby')
            assert(await(function() return #_UserService.UserEntities.Values == 0 end), 'both leave active battle through native room boundary')
            log('[VRF][LevelMatch65] ABORT_DISPATCHED verify unchanged saves in server_main')
            return
        end
        assert(peer ~= nil and _RoomService:MoveUserToStaticRoom(peer, 'formationlobby'), 'one participant leaves during battle')
        assert(await(function() return battle.Phase == 'RESULT' end, 1200), 'elimination produces natural result')
        assert(await(function()
            local results = battle:GetExperienceResults()
            return results[battle.HomeProfile] and results[battle.AwayProfile]
                and results[battle.HomeProfile].status == 'SAVED' and results[battle.AwayProfile].status == 'SAVED'
        end), 'both settlements saved including departed peer')
        local deaths = _HttpService:JSONDecode(battle.ResultDeaths)
        local results = battle:GetExperienceResults()
        for _, side in ipairs({{battle.HomeProfile, 'PLAYER', battle.InitialPlayerAlive, battle.PlayerAlive},
            {battle.AwayProfile, 'ENEMY', battle.InitialEnemyAlive, battle.EnemyAlive}}) do
            local total = 0
            local code, raw = _DataStorageService:GetUserDataStorage(side[1]):GetAndWait(LEVEL_KEY)
            assert(code == 0, 'participant private save exists')
            local document = _MonsterLevelStorage:Decode(raw)
            for id, count in pairs(deaths[side[2]]) do
                total = total + count
                local expected = _MonsterProgression:ApplyExperience(1, 0, count)
                assert(document.monsters[id].level == expected.level and document.monsters[id].experience == expected.experience,
                    'stored progress equals own faction deaths, not opponent kills')
                local change = results[side[1]].monsters[id]
                assert(change.gained == count and change.before.level == 1 and change.after.level == expected.level, 'retained result receipt')
            end
            assert(total == side[3] - side[4], 'all and only dead units counted')
            assert(#document.settled == 1 and document.settled[1] == battle.MatchKey, 'single durable match receipt')
        end
        for _, user in ipairs(_UserService.UserEntities.Values) do _MatchFlow:ReturnForUser(user.PlayerComponent.UserId) end
        log('[VRF][LevelMatch65] RESULT_PASS both own-faction counts; departed peer saved; receipts retained; return dispatched')
    end
end)
if not ok then log('[VRF][LevelMatch65] FAIL '..tostring(detail)) end
